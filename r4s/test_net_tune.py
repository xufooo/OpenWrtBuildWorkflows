#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Local mocks only: copied shell scripts are rooted in TemporaryDirectory.

No production environment override is shipped. The fixture rewrites literal
absolute paths and PATH in its private copy, never touching host sysfs/procfs.
"""
import json
import os
from pathlib import Path
import re
import signal
import shlex
import subprocess
import sys
import tempfile
import time
import unittest

PACKAGE = Path(__file__).resolve().parent / "packages/r4s-net-tune"
FILES = PACKAGE / "files"
HELPER = "usr/libexec/r4s-net-tune"
MOCK = r'''
import fcntl, json, os, pathlib, sys, time
r = pathlib.Path(os.environ["MOCK_ROOT"])
cmd = pathlib.Path(sys.argv[0]).name
a = sys.argv[1:]
def load(name): return json.loads((r / name).read_text())
def save(name, data): (r / name).write_text(json.dumps(data))
def log():
    with (r / "calls").open("a") as f:
        f.write(json.dumps([cmd, a, time.monotonic()]) + "\n")
if cmd == "flock":
    fcntl.flock(int(a[-1]), fcntl.LOCK_EX | (fcntl.LOCK_NB if "-n" in a else 0))
    if a[-1] == "8": log()
    sys.exit(0)
if cmd == "id":
    print(os.environ.get("MOCK_UID", "0")); sys.exit(0)
log()
if cmd == "uci":
    d = load("uci.json")
    if a[0] == "-q": a = a[1:]
    op = a[0]
    if op == "get":
        if a[1] not in d: sys.exit(1)
        print(d[a[1]])
    elif op == "set":
        k, v = a[1].split("=", 1); d[k] = v; save("uci.json", d)
    elif op == "add":
        assert a == ["add", "network", "globals"]
        d["network.@globals[0]"] = "globals"; save("uci.json", d); print("cfg0")
    elif op == "changes": print(d.get("_pending_" + a[1], ""))
    elif op != "commit": sys.exit(2)
elif cmd == "ethtool":
    d = load("eth.json"); dev = d[a[1]]
    if a[0] == "-k":
        for k, v in dev["features"].items(): print(k + ": " + v)
        if dev.get("read_fail"): sys.exit(1)
    elif a[0] == "-g":
        print("Ring parameters for " + a[1] + ":\nPre-set maximums:")
        for k, v in dev["max"].items(): print(k.upper() + ": " + str(v))
        print("Current hardware settings:")
        for k, v in dev["cur"].items(): print(k.upper() + ": " + str(v))
        if dev.get("read_fail"): sys.exit(1)
    elif a[0] in ("-K", "-G"):
        if dev.get("fail"): sys.exit(1)
        if a[0] == "-K":
            k = {"rx": "rx-checksumming", "gro": "generic-receive-offload"}[a[2]]
            if not dev.get("noop"): dev["features"][k] = a[3]
        else:
            assert not (int((r / ("sys/class/net/" + a[1] + "/flags")).read_text(), 16) & 1)
            dev["cur"][a[2]] = int(a[3])
        if dev.get("fail_after_write"): dev["read_fail"] = True
        save("eth.json", d)
    else: sys.exit(3)
elif cmd == "packet_steering":
    assert a == ["reload"]
elif cmd != "logger":
    raise AssertionError("Forbidden command: " + cmd + repr(a))
'''


class NetTune(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="r4s-net-tune-")
        self.root = Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, MOCK_ROOT=str(self.root))
        for cmd in ("uci", "id", "flock", "ethtool", "logger", "packet_steering"):
            self.put("bin/" + cmd, "#!" + sys.executable + "\n" + MOCK, executable=True)
        for source in FILES.rglob("*"):
            if source.is_file():
                content = source.read_text()
                content = content.replace("PATH=/usr/sbin:/usr/bin:/sbin:/bin",
                                          "PATH=" + shlex.quote(str(self.bin) + ":" + os.defpath))
                content = re.sub(r"/(?:var/run/|tmp/sysinfo/|sys/|proc/|etc/|usr/libexec/|lib/functions\.sh)",
                                 lambda match: str(self.root) + match.group(), content)
                self.put(str(source.relative_to(FILES)), content, executable=True)
        self.put("etc/init.d/packet_steering", "#!/bin/sh\nexec " +
                 shlex.quote(str(self.bin / "packet_steering")) + ' "$@"\n', executable=True)
        self.put("lib/functions.sh", '''
config_load() { :; }
config_foreach() { "$1" mock0; "$1" mock1; }
config_get() {
    local idx=0 value
    [ "$2" != mock1 ] || idx=1
    value=$(uci -q get "network.@device[$idx].$3")
    export "$1=$value"
}
''')
        self.put("tmp/sysinfo/board_name", "friendlyarm,nanopi-r4s\n")
        self.put("proc/meminfo", "MemTotal: 3900000 kB\n")
        self.initial = {
            "net.core.rmem_max": "212992", "net.core.wmem_max": "212992",
            "net.ipv4.tcp_rmem": "4096 87380 6291456",
            "net.ipv4.tcp_wmem": "4096 16384 4194304",
            "net.core.netdev_max_backlog": "1000", "net.core.rps_sock_flow_entries": "0",
        }
        for k, v in self.initial.items(): self.put("proc/sys/" + k.replace(".", "/"), v + "\n")
        self.uci = {"r4s_net_tune.main.enabled": "1", "r4s_net_tune.main.ring": "1",
                    "r4s_net_tune.main.defaults_applied": "0",
                    "r4s_net_tune.main.buffers": "1",
                    "network.@globals[0]": "globals", "network.@globals[0].packet_steering": "2",
                    "network.@globals[0].steering_flows": "128"}
        self.eth = {dev: {"features": {"rx-checksumming": "off", "generic-receive-offload": "off"},
                          "cur": {"rx": 256, "tx": 256}, "max": {"rx": 4096, "tx": 1024}}
                    for dev in ("eth0", "eth1")}
        self.save()
        for dev in self.eth:
            (self.root / f"sys/class/net/{dev}/device").mkdir(parents=True)
            self.put(f"sys/class/net/{dev}/flags", "0x1002\n")
            self.put(f"sys/class/net/{dev}/queues/rx-0/rps_flow_cnt", "128\n")
            self.put(f"sys/class/net/{dev}/queues/rx-0/rps_cpus", "3f\n")
        self.put("proc/interrupts",
                 " 42:  0  0  0  0  100  0  GICv3 27 Level  eth0\n"
                 " 43:  0  0  0  0  0  100  GICv3 28 Level  eth1\n")
        for irq, mask in ((42, "10"), (43, "20")):
            self.put("proc/irq/%d/smp_affinity" % irq, mask + "\n")
        self.workers = []

    def tearDown(self):
        for p in self.workers:
            if p.poll() is None: p.terminate()
            p.communicate(timeout=10)
        self.tmp.cleanup()

    def put(self, name, value, executable=False):
        p = self.root / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(value)
        if executable: p.chmod(0o755)

    def save(self):
        self.put("uci.json", json.dumps(self.uci))
        self.put("eth.json", json.dumps(self.eth))

    def run_helper(self, cmd, check=True):
        return subprocess.run(["/bin/sh", str(self.root / HELPER), cmd], env=self.env,
                              capture_output=True, text=True, check=check, timeout=10)

    def read_sys(self, key):
        return (self.root / ("proc/sys/" + key.replace(".", "/"))).read_text().strip()

    def calls(self, cmd=None):
        p = self.root / "calls"
        rows = [json.loads(x) for x in p.read_text().splitlines()] if p.exists() else []
        return [x for x in rows if cmd is None or x[0] == cmd]

    def state(self, name): return self.root / ("var/run/r4s-net-tune/" + name)

    def apply(self):
        self.run_helper("activate")
        self.run_helper("apply")

    def test_board_and_root_guards(self):
        for board in ("friendlyarm,nanopi-r4s", "friendlyarm,nanopi-r4s-enterprise",
                      "friendlyelec,nanopi-r4s"):
            self.put("tmp/sysinfo/board_name", board)
            self.run_helper("activate")
        self.run_helper("stop")
        self.put("tmp/sysinfo/board_name", "friendlyarm,nanopi-r2s")
        self.assertNotEqual(self.run_helper("activate", check=False).returncode, 0)
        self.run_helper("boot")
        self.assertFalse(self.calls("packet_steering"))
        self.env["MOCK_UID"] = "1000"
        self.assertNotEqual(self.run_helper("apply", check=False).returncode, 0)

    def test_ceilings_and_restore(self):
        self.apply()
        self.assertEqual(self.read_sys("net.core.rmem_max"), "67108864")
        self.assertEqual(self.read_sys("net.ipv4.tcp_rmem"), "4096 87380 67108864")
        self.assertEqual(self.read_sys("net.core.netdev_max_backlog"), "16384")
        self.assertEqual(self.read_sys("net.core.rps_sock_flow_entries"), "256")
        self.run_helper("apply")
        self.assertEqual(self.state("net.core.rmem_max.base").read_text().strip(), "212992")
        self.assertEqual(self.state("").stat().st_mode & 0o777, 0o700)
        for p in self.state("").iterdir(): self.assertEqual(p.stat().st_mode & 0o777, 0o600)
        self.run_helper("stop")
        for k, v in self.initial.items(): self.assertEqual(self.read_sys(k), v)

    def test_low_memory_and_no_lowering(self):
        self.put("proc/meminfo", "MemTotal: 512000 kB\n")
        self.put("proc/sys/net/core/wmem_max", "134217728\n")
        self.apply()
        self.assertEqual(self.read_sys("net.core.rmem_max"), "33554432")
        self.assertEqual(self.read_sys("net.core.wmem_max"), "134217728")
        self.assertFalse(self.state("net.core.wmem_max.last").exists())

    def test_buffer_ceilings_are_opt_in(self):
        del self.uci["r4s_net_tune.main.buffers"]; self.save()
        self.apply()
        self.assertEqual(self.read_sys("net.core.rmem_max"), "212992")
        self.assertEqual(self.read_sys("net.ipv4.tcp_rmem"), "4096 87380 6291456")
        self.assertEqual(self.read_sys("net.core.netdev_max_backlog"), "1000")
        self.assertFalse(self.state("net.core.rmem_max.base").exists())

    def test_enabled_zero_restores_and_never_reloads_network(self):
        self.apply()
        self.uci["r4s_net_tune.main.enabled"] = "0"; self.save()
        count = len(self.calls("packet_steering"))
        self.run_helper("apply"); self.run_helper("boot"); self.run_helper("defaults")
        self.assertEqual(len(self.calls("packet_steering")), count)
        for k, v in self.initial.items(): self.assertEqual(self.read_sys(k), v)
        self.assertFalse([x for x in self.calls("ethtool") if x[1][0] == "-G"])
        self.assertTrue(all(x[1] == ["reload"] for x in self.calls("packet_steering")))

    def test_ring_boot_down_only_and_deferred_restore(self):
        self.put("sys/class/net/eth1/flags", "0x1003\n")
        self.run_helper("boot")
        rings = [x[1] for x in self.calls("ethtool") if x[1][0] == "-G"]
        self.assertEqual(rings, [["-G", "eth0", "rx", "4096"], ["-G", "eth0", "tx", "1024"]])
        self.apply()
        self.assertEqual(len([x for x in self.calls("ethtool") if x[1][0] == "-G"]), 2)
        self.put("sys/class/net/eth0/flags", "0x1003\n")
        self.run_helper("stop")
        self.assertTrue(self.state("ring-restore-pending").exists())
        self.assertEqual(len([x for x in self.calls("ethtool") if x[1][0] == "-G"]), 2)
        self.put("sys/class/net/eth0/flags", "0x1002\n")
        self.run_helper("stop")
        d = json.loads((self.root / "eth.json").read_text())
        self.assertEqual(d["eth0"]["cur"], {"rx": 256, "tx": 256})

    def test_gro_config_fixed_unsupported_and_failure(self):
        self.uci.update({"network.@device[0].name": "eth0", "network.@device[0].gro": "0"})
        self.eth["eth0"]["features"]["rx-checksumming"] = "off [fixed]"
        self.eth["eth1"]["features"].pop("rx-checksumming")
        self.eth["eth1"]["fail"] = True; self.save()
        self.apply()
        mutations = [x[1] for x in self.calls("ethtool") if x[1][0] == "-K"]
        self.assertEqual(mutations, [["-K", "eth1", "gro", "on"]])
        self.assertFalse(self.state("eth1.generic-receive-offload.last").exists())
        self.run_helper("stop")
        self.assertEqual(len([x for x in self.calls("ethtool") if x[1][0] == "-K"]), 1)

    def test_stop_preserves_user_changes(self):
        self.apply()
        self.put("proc/sys/net/core/rmem_max", "777777\n")
        d = json.loads((self.root / "eth.json").read_text())
        d["eth0"]["features"]["generic-receive-offload"] = "off"
        self.put("eth.json", json.dumps(d))
        before = len(self.calls("ethtool"))
        self.run_helper("stop")
        self.assertEqual(self.read_sys("net.core.rmem_max"), "777777")
        writes = [x[1] for x in self.calls("ethtool")[before:] if x[1][0] == "-K"]
        self.assertNotIn(["-K", "eth0", "gro", "off"], writes)

    def test_defaults_migrate_only_public_values(self):
        for mode, wanted in ((None, "2"), ("1", "2"), ("0", "0"), ("2", "2")):
            self.uci.pop("network.@globals[0].packet_steering", None)
            if mode is not None: self.uci["network.@globals[0].packet_steering"] = mode
            self.uci["network.@globals[0].steering_flows"] = "0"; self.save()
            self.run_helper("defaults")
            d = json.loads((self.root / "uci.json").read_text())
            self.assertEqual(d["network.@globals[0].packet_steering"], wanted)
            self.assertEqual(d["network.@globals[0].steering_flows"], "128")
            self.assertEqual(d["r4s_net_tune.main.affinity"], "upstream")
        self.uci["network.@globals[0].steering_flows"] = "512"; self.save()
        self.run_helper("defaults")
        self.assertEqual(json.loads((self.root / "uci.json").read_text())["network.@globals[0].steering_flows"], "512")
        sets = [x[1][-1].split("=")[0] for x in self.calls("uci") if "set" in x[1]]
        self.assertLessEqual(set(sets), {"network.@globals[0].packet_steering", "network.@globals[0].steering_flows",
                                        "r4s_net_tune.main.defaults_applied", "r4s_net_tune.main.affinity"})

    def test_defaults_run_once_and_preserve_later_ui_choice(self):
        self.uci["network.@globals[0].packet_steering"] = "1"; self.save()
        self.run_helper("defaults")
        self.uci = json.loads((self.root / "uci.json").read_text())
        self.assertEqual(self.uci["network.@globals[0].packet_steering"], "2")
        self.assertEqual(self.uci["r4s_net_tune.main.defaults_applied"], "1")
        self.uci["network.@globals[0].packet_steering"] = "1"; self.save()
        before = len(self.calls("uci"))
        self.run_helper("defaults")
        self.assertEqual(json.loads((self.root / "uci.json").read_text()), self.uci)
        self.assertFalse([x for x in self.calls("uci")[before:] if "set" in x[1] or "commit" in x[1]])

    def test_affinity_recipe_applies_and_restores(self):
        self.uci["r4s_net_tune.main.affinity"] = "starwhiz"; self.save()
        self.apply()
        for irq, want in ((42, "4"), (43, "8")):
            self.assertEqual((self.root / ("proc/irq/%d/smp_affinity" % irq)).read_text().strip(), want)
        for dev, want in (("eth0", "10"), ("eth1", "20")):
            self.assertEqual((self.root / f"sys/class/net/{dev}/queues/rx-0/rps_cpus").read_text().strip(), want)
        self.uci["r4s_net_tune.main.enabled"] = "0"; self.save()
        self.apply()
        for irq, want in ((42, "10"), (43, "20")):
            self.assertEqual((self.root / ("proc/irq/%d/smp_affinity" % irq)).read_text().strip(), want)
        self.assertFalse(self.state("affinity.applied").exists())

    def test_affinity_upstream_leaves_masks_alone(self):
        # A missing legacy option must not activate the manual IRQ profile.
        self.apply()
        for irq, want in ((42, "10"), (43, "20")):
            self.assertEqual((self.root / ("proc/irq/%d/smp_affinity" % irq)).read_text().strip(), want)
        for dev, want in (("eth0", "3f"), ("eth1", "3f")):
            self.assertEqual((self.root / f"sys/class/net/{dev}/queues/rx-0/rps_cpus").read_text().strip(), want)

    def test_defaults_defer_pending_network_changes(self):
        self.uci["_pending_network"] = "network.globals.user_setting='keep'"
        self.uci["network.@globals[0].packet_steering"] = "1"; self.save()
        self.assertEqual(self.run_helper("defaults", check=False).returncode, 1)
        self.assertEqual(json.loads((self.root / "uci.json").read_text()), self.uci)
        calls = self.calls("uci")
        self.assertFalse([x for x in calls if "set" in x[1] or "commit" in x[1] or "add" in x[1]])

    def test_defaults_defer_pending_package_changes(self):
        self.uci["_pending_r4s_net_tune"] = "r4s_net_tune.main.ring='0'"
        self.uci["network.@globals[0].packet_steering"] = "1"; self.save()
        self.assertEqual(self.run_helper("defaults", check=False).returncode, 1)
        self.assertEqual(json.loads((self.root / "uci.json").read_text()), self.uci)
        self.assertFalse([x for x in self.calls("uci") if "set" in x[1] or "commit" in x[1]])

    def test_rfs_disabled_invalid_and_limits(self):
        for mode, flows, count in (("0", "128", "128"), ("2", "0", "128"),
                                   ("2", "bad", "128"), ("2", "128", "bad"),
                                   ("2", "128", "1048576")):
            self.uci["network.@globals[0].packet_steering"] = mode
            self.uci["network.@globals[0].steering_flows"] = flows; self.save()
            self.put("sys/class/net/eth0/queues/rx-0/rps_flow_cnt", count)
            self.apply()
            self.assertEqual(self.read_sys("net.core.rps_sock_flow_entries"), "0")
            self.assertFalse(self.state("net.core.rps_sock_flow_entries.last").exists())
        self.assertEqual(len(self.calls("packet_steering")), 5)

    def test_physical_device_guard(self):
        for dev in self.eth: (self.root / f"sys/class/net/{dev}/device").rmdir()
        self.run_helper("boot"); self.apply()
        self.assertFalse(self.calls("ethtool"))
        self.assertEqual(self.read_sys("net.core.rps_sock_flow_entries"), "0")

    def test_rfs_ui_disable_restores_only_owned_table(self):
        for option in ("packet_steering", "steering_flows"):
            self.uci["network.@globals[0].packet_steering"] = "2"
            self.uci["network.@globals[0].steering_flows"] = "128"; self.save()
            self.apply()
            self.assertEqual(self.read_sys("net.core.rps_sock_flow_entries"), "256")
            self.uci[f"network.@globals[0].{option}"] = "0"; self.save()
            self.run_helper("apply")
            self.assertEqual(self.read_sys("net.core.rps_sock_flow_entries"), "0")
            self.assertFalse(self.state("net.core.rps_sock_flow_entries.last").exists())
            self.assertEqual(self.read_sys("net.core.rmem_max"), "67108864")
        self.put("proc/sys/net/core/rps_sock_flow_entries", "512\n")
        self.run_helper("apply")
        self.assertEqual(self.read_sys("net.core.rps_sock_flow_entries"), "512")

    def test_rfs_rounded_readback_and_user_change(self):
        self.put("sys/class/net/eth0/queues/rx-0/rps_flow_cnt", "256\n")
        target = self.root / "proc/sys/net/core/rps_sock_flow_entries"
        script = ('set -- activate; . ' + shlex.quote(str(self.root / HELPER)) + '\n' +
                  'sys_write() { printf "512\\n" > ' + shlex.quote(str(target)) + '; }\n' +
                  'tune_rfs\n')
        subprocess.run(["/bin/sh", "-c", script], env=self.env, check=True)
        self.assertEqual(self.state("net.core.rps_sock_flow_entries.last").read_text().strip(), "512")
        target.write_text("1024\n")
        self.run_helper("stop")
        self.assertEqual(target.read_text().strip(), "1024")

    def test_init_install_start_guard_and_stop_path(self):
        init = shlex.quote(str(self.root / "etc/init.d/r4s-net-tune"))
        script = '. ' + init + '''
procd_open_instance() { echo opened; }
procd_set_param() { :; }
procd_close_instance() { :; }
start_service
'''
        self.put("var/run/r4s-net-tune.installing", "")
        p = subprocess.run(["/bin/sh", "-c", script], env=self.env, capture_output=True, text=True, check=True)
        self.assertEqual(p.stdout, "")
        self.assertFalse(self.state("active").exists())
        p = subprocess.run(["/bin/sh", "-c", script + 'stop_service\n'], env=self.env,
                           capture_output=True, text=True, check=True, timeout=10)
        self.assertEqual(p.stdout.strip(), "opened")
        self.assertFalse(self.state("active").exists())

    def test_stop_cancels_pending_watch(self):
        self.run_helper("activate")
        p = subprocess.Popen(["/bin/sh", str(self.root / HELPER), "watch", self.state("active").read_text().strip()], env=self.env,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.workers.append(p)
        time.sleep(0.2)
        self.run_helper("stop")
        p.communicate(timeout=10)
        self.assertFalse(self.calls("packet_steering"))
        self.assertFalse(self.state("pending").exists())

    def test_snapshot_is_not_executed(self):
        self.apply()
        self.state("net.core.rmem_max.base").write_text("$(touch " + str(self.root / "executed") + ")")
        self.assertNotEqual(self.run_helper("stop", check=False).returncode, 0)
        self.assertFalse((self.root / "executed").exists())
        self.assertEqual(self.read_sys("net.core.rmem_max"), "67108864")

    def test_restore_read_failure_preserves_snapshot_for_retry(self):
        self.apply()
        target = self.root / "proc/sys/net/core/rmem_max"
        target.unlink()
        self.assertNotEqual(self.run_helper("stop", check=False).returncode, 0)
        self.assertTrue(self.state("net.core.rmem_max.base").exists())
        self.assertTrue(self.state("net.core.rmem_max.last").exists())
        target.write_text("67108864\n")
        self.run_helper("stop")
        self.assertEqual(target.read_text().strip(), "212992")
        self.assertFalse(self.state("net.core.rmem_max.last").exists())

    def test_restore_write_failure_preserves_snapshot_for_retry(self):
        self.apply()
        script = ('set -- queue; . ' + shlex.quote(str(self.root / HELPER)) + '\n' +
                  'sys_write() { return 1; }; locked stop\n')
        p = subprocess.run(["/bin/sh", "-c", script], env=self.env, capture_output=True, text=True)
        self.assertNotEqual(p.returncode, 0)
        self.assertTrue(self.state("net.core.rmem_max.last").exists())
        self.run_helper("stop")
        for k, v in self.initial.items(): self.assertEqual(self.read_sys(k), v)

    def test_failed_first_write_reacquires_current_baseline(self):
        script = ('set -- queue; . ' + shlex.quote(str(self.root / HELPER)) + '\n' +
                  'activate; sys_write() { return 1; }; apply\n')
        subprocess.run(["/bin/sh", "-c", script], env=self.env, capture_output=True, check=True)
        self.assertTrue(self.state("net.core.rmem_max.base").exists())
        self.assertFalse(self.state("net.core.rmem_max.last").exists())
        self.put("proc/sys/net/core/rmem_max", "333333\n")
        self.run_helper("apply")
        self.assertEqual(self.state("net.core.rmem_max.base").read_text().strip(), "333333")
        self.run_helper("stop")
        self.assertEqual(self.read_sys("net.core.rmem_max"), "333333")

    def test_sysctl_apply_success_failed_readback_keeps_ownership(self):
        self.put("sys/class/net/eth0/queues/rx-0/rps_flow_cnt", "256\n")
        script = ('set -- queue; . ' + shlex.quote(str(self.root / HELPER)) + '\n' +
                  'activate\n' + r'''
sys_read() {
    [ ! -f "$STATE/readfail.$1" ] || return 1
    cat "''' + str(self.root) + r'''/proc/sys/$(printf '%s' "$1" | tr . /)"
}
sys_write() {
    local value="$2"
    [ "$1" != net.core.rps_sock_flow_entries ] || value=512
    printf '%s\n' "$value" > "''' + str(self.root) + r'''/proc/sys/$(printf '%s' "$1" | tr . /)"
    : > "$STATE/readfail.$1"
}
apply
''')
        subprocess.run(["/bin/sh", "-c", script], env=self.env, capture_output=True, check=True)
        self.assertEqual(self.state("net.core.rmem_max.last").read_text().strip(), "67108864")
        self.assertEqual(self.state("net.core.rps_sock_flow_entries.last").read_text().strip(), "512")
        self.run_helper("stop")
        for k, v in self.initial.items(): self.assertEqual(self.read_sys(k), v)

    def test_feature_apply_success_failed_readback_keeps_ownership(self):
        for dev in self.eth.values(): dev["fail_after_write"] = True
        self.save(); self.apply()
        self.assertTrue(self.state("eth0.rx-checksumming.last").exists())
        d = json.loads((self.root / "eth.json").read_text())
        for dev in d.values(): dev.pop("read_fail"); dev.pop("fail_after_write")
        self.put("eth.json", json.dumps(d)); self.run_helper("stop")
        d = json.loads((self.root / "eth.json").read_text())
        self.assertEqual(d["eth0"]["features"]["rx-checksumming"], "off")

    def test_ring_apply_success_failed_readback_keeps_ownership(self):
        for dev in self.eth.values(): dev["fail_after_write"] = True
        self.save(); self.run_helper("boot")
        self.assertTrue(self.state("eth0.RX.last").exists())
        d = json.loads((self.root / "eth.json").read_text())
        for dev in d.values(): dev.pop("read_fail"); dev.pop("fail_after_write")
        self.put("eth.json", json.dumps(d)); self.run_helper("stop")
        d = json.loads((self.root / "eth.json").read_text())
        self.assertEqual(d["eth0"]["cur"]["rx"], 256)

    def test_ethtool_failed_reads_and_writes_retain_baselines(self):
        self.run_helper("boot"); self.apply()
        d = json.loads((self.root / "eth.json").read_text())
        d["eth0"]["read_fail"] = True; self.put("eth.json", json.dumps(d))
        self.assertNotEqual(self.run_helper("stop", check=False).returncode, 0)
        self.assertTrue(self.state("eth0.rx-checksumming.last").exists())
        self.assertTrue(self.state("eth0.RX.last").exists())
        d = json.loads((self.root / "eth.json").read_text())
        d["eth0"].pop("read_fail"); d["eth0"]["fail"] = True; self.put("eth.json", json.dumps(d))
        self.assertNotEqual(self.run_helper("stop", check=False).returncode, 0)
        self.assertTrue(self.state("eth0.rx-checksumming.last").exists())
        self.assertTrue(self.state("eth0.RX.last").exists())
        d["eth0"].pop("fail"); self.put("eth.json", json.dumps(d))
        self.run_helper("stop")
        self.assertFalse(self.state("eth0.rx-checksumming.last").exists())
        self.assertFalse(self.state("eth0.RX.last").exists())

    def test_restart_old_watch_exit_cannot_clean_new_generation(self):
        self.run_helper("activate")
        old = subprocess.Popen(["/bin/sh", str(self.root / HELPER), "watch", self.state("active").read_text().strip()], env=self.env,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.workers.append(old)
        deadline = time.monotonic() + 5
        while not self.calls("flock") and time.monotonic() < deadline: time.sleep(0.05)
        self.assertTrue(self.calls("flock"))
        os.kill(old.pid, signal.SIGSTOP)
        try:
            self.run_helper("stop")
            self.run_helper("activate")
            generation = self.state("active").read_text()
            new = subprocess.Popen(["/bin/sh", str(self.root / HELPER), "watch", generation.strip()], env=self.env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            self.workers.append(new)
            time.sleep(0.3)
            self.assertIsNone(new.poll())
            old.terminate()
        finally:
            os.kill(old.pid, signal.SIGCONT)
        old.communicate(timeout=10)
        self.assertEqual(self.state("active").read_text(), generation)
        deadline = time.monotonic() + 12
        while not self.state("eth1.generic-receive-offload.last").exists() and time.monotonic() < deadline:
            time.sleep(0.1)
        self.assertTrue(self.state("eth1.generic-receive-offload.last").exists())
        self.assertEqual(len(self.calls("packet_steering")), 1)
        self.run_helper("stop")
        new.communicate(timeout=10)

    def test_watch_debounce_sigterm_and_no_reactivation_after_stop(self):
        self.run_helper("activate")
        p = subprocess.Popen(["/bin/sh", str(self.root / HELPER), "watch", self.state("active").read_text().strip()], env=self.env,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.workers.append(p)
        time.sleep(0.4)
        self.run_helper("queue")
        time.sleep(0.4)
        last_event = time.monotonic(); self.run_helper("queue")
        deadline = time.monotonic() + 12
        while not self.state("eth1.generic-receive-offload.last").exists() and time.monotonic() < deadline:
            time.sleep(0.1)
        self.assertTrue(self.state("eth1.generic-receive-offload.last").exists())
        calls = self.calls("packet_steering")
        self.assertEqual(len(calls), 1)
        self.assertGreaterEqual(calls[0][2] - last_event, 2)
        p.terminate(); p.communicate(timeout=10)
        self.assertEqual(p.returncode, 0)
        for k, v in self.initial.items(): self.assertEqual(self.read_sys(k), v)
        self.assertFalse(self.state("active").exists())
        self.run_helper("queue"); self.run_helper("apply")
        self.assertEqual(len(self.calls("packet_steering")), 1)

    def test_hotplug_environment_aliases_and_filters(self):
        self.run_helper("activate")
        script = self.root / "etc/hotplug.d/net/90-r4s-net-tune"
        for var in ("DEVICENAME", "INTERFACE"):
            for dev in ("eth0", "eth1", "ifb4eth0", "ifb4eth1", "ifb4pppoe-wan"):
                for action in ("add", "remove"):
                    old = self.state("serial").read_text()
                    subprocess.run(["/bin/sh", str(script)], env=dict(self.env, **{var: dev, "ACTION": action}), check=True)
                    changed = self.state("serial").read_text() != old
                    self.assertEqual(changed, dev in ("eth0", "eth1"), (var, dev, action))
        old = self.state("serial").read_text()
        subprocess.run(["/bin/sh", str(script)], env=dict(self.env, DEVICENAME="wlan0", ACTION="add"), check=True)
        self.assertEqual(self.state("serial").read_text(), old)

    def test_delayed_old_watch_token_cannot_claim_new_generation(self):
        old = self.run_helper("activate").stdout.strip()
        new = self.run_helper("activate").stdout.strip()
        self.assertNotEqual(old, new)
        pending = self.state("pending").read_text()
        p = subprocess.run(["/bin/sh", str(self.root / HELPER), "watch", old], env=self.env,
                           capture_output=True, text=True, timeout=5, check=True)
        self.assertEqual(p.returncode, 0)
        self.assertEqual(self.state("active").read_text().strip(), new)
        self.assertEqual(self.state("pending").read_text(), pending)
        self.assertFalse(self.calls("packet_steering"))

    def test_syntax_layout_and_init_contract(self):
        for source in FILES.rglob("*"):
            if source.is_file() and source.read_text().startswith("#!"):
                subprocess.run(["/bin/sh", "-n", str(source)], check=True)
        init = (FILES / "etc/init.d/r4s-net-tune").read_text()
        self.assertIn("START=19", init)
        self.assertNotIn("sqm", init)
        self.assertIn("procd_set_param command /usr/libexec/r4s-net-tune watch", init)
        self.assertIn('watch "$generation"', init)
        makefile = (PACKAGE / "Makefile").read_text()
        self.assertIn("PKGARCH:=all", makefile)
        self.assertIn("@TARGET_rockchip", makefile)
        self.assertNotIn("define Package/r4s-net-tune/postinst", makefile)
        self.assertIn("define Package/r4s-net-tune/preinst", makefile)
        prod = (FILES / HELPER).read_text()
        for forbidden in ("network reload", "network restart", "conntrack", "ethtool -C"):
            self.assertNotIn(forbidden, prod)
        # IRQ masks are written only by the UCI-gated StarWhiz recipe.
        self.assertEqual(prod.count('smp_affinity"'), 4)
        self.assertIn("r4s_net_tune.main.affinity", prod)
        self.assertNotIn("MOCK_ROOT", prod)


if __name__ == "__main__":
    unittest.main()
