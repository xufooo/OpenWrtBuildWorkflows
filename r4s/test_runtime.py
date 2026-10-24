"""Run the real controller with mocked nft/netifd; no live firewall changes."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
FILES = HERE / "package/r4s-accel/files"


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.state = self.root / "state"
        self.state.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"], TEST_ROOT=str(self.root))
        self.env["TEST_PYTHON"] = shutil.which("python3")
        for name in ("br-lan", "eth0", "eth1"):
            (self.root / "sys" / name).mkdir(parents=True)
        bridge = self.root / "sys/br-lan/brif"
        bridge.mkdir()
        (bridge / "eth1").symlink_to(self.root / "sys/eth1")
        source = (FILES / "usr/libexec/r4s-accel").read_text()
        source = source.replace("STATE=/var/run/r4s-accel", f"STATE='{self.state}'")
        source = source.replace(". /lib/functions.sh", """config_load() { :; }
config_get() {
    case "$3" in lan) lan_net=lan ;; wan) wan_net=wan ;; fullcone4) enabled=${FULLCONE:-0} ;; esac
}
config_foreach() { "$1" defaults; }
network_get_device() { case "$1" in lan) lan=br-lan ;; wan) wan=eth0 ;; esac; }
network_get_physdev() { case "$1" in lan_phys) lan_phys=eth1 ;; wan_phys) wan_phys=eth0 ;; esac; }""")
        source = source.replace(". /lib/functions/network.sh", "")
        source = source.replace("/sys/class/net/", str(self.root / "sys") + "/")
        for name in ("/sbin/fw4", "/usr/share/passwall/nftables.sh", "/etc/init.d/sqm"):
            hook = self.root / name.lstrip("/")
            hook.parent.mkdir(parents=True, exist_ok=True)
            hook.write_text("# r4s-accel lifecycle v1\n")
            source = source.replace(name, str(hook))
        self.controller = self.root / "controller"
        self.controller.write_text(source)
        self.command("flock", "#!/bin/sh\nexit 0\n")
        self.command("lua", "#!/bin/sh\necho 192.0.2.2\necho 'TCP/UDP admission ready' >&2\n")
        self.command("ip", "#!/bin/sh\nprintf '0: from all lookup local\\n32766: from all lookup main\\n32767: from all lookup default\\n'\n[ -z \"$EXTRA_RULE\" ] || echo '100: from 192.0.2.2 lookup 100'\nexit 0\n")
        self.command("jsonfilter", """#!/bin/sh
case "$4" in *.name) echo forward ;; *.table) echo fw4 ;; *.family) echo inet ;; *) exit 1 ;; esac
[ -z "$EXTRA_CHAIN" ] || echo other
exit 0
""")
        self.command("nft", """#!/bin/sh
exec "$TEST_PYTHON" "$TEST_ROOT/nft.py" "$@"
""")
        (self.root / "nft.py").write_text("""import json,os,sys,pathlib
r=pathlib.Path(os.environ['TEST_ROOT']); a=sys.argv[1:]
with (r/'calls').open('a') as f: f.write(json.dumps(a)+'\\n')
if a[:3]==['list','table','inet']: sys.exit(0 if (r/'fast').exists() else 1)
if a[:2]==['delete','table']:
    if os.getenv('FAIL_DELETE'): sys.exit(2)
    (r/'fast').unlink(missing_ok=True)
if a[:2]==['list','chain']: sys.exit(0)
if a[:2]==['-c','-f'] and os.getenv('FAIL_CHECK'): sys.exit(2)
if a[:1]==['-f']: (r/'fast').touch()
""")
        self.command("conntrack", """#!/bin/sh
echo "$*" >> "$TEST_ROOT/drained"
if [ -n "$FAIL_DRAIN" ]; then echo 'Operation failed' >&2; exit 2; fi
""")

    def command(self, name, text):
        path = self.bin / name
        path.write_text(text)
        path.chmod(0o755)

    def run_controller(self, *args, success=True):
        result = subprocess.run(["sh", str(self.controller), *args], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stderr)

    def test_admission_is_after_fw4_and_both_directions_are_scoped(self):
        self.run_controller("reload")
        rules = (self.state / "rules").read_text()
        self.assertIn("hook forward priority 10", rules)
        self.assertEqual(rules.count("ct original ip saddr @direct"), 2)
        self.assertIn('devices = { "br-lan","eth0","eth1" }', rules)
        self.assertIn("ct mark != 0 return", rules)
        self.assertIn("ct status dnat return", rules)
        self.assertTrue((self.root / "fast").exists())

    def test_suspend_drains_only_admitted_hosts_and_blocks_reload(self):
        self.run_controller("reload")
        self.run_controller("suspend", "passwall")
        self.assertEqual((self.root / "drained").read_text(), "-D -f ipv4 -s 192.0.2.2\n")
        self.run_controller("reload")
        self.assertFalse((self.root / "fast").exists())
        self.run_controller("resume", "passwall")
        self.assertTrue((self.root / "fast").exists())

    def test_failed_rule_check_leaves_no_fast_table(self):
        self.run_controller("reload")
        self.env["FAIL_CHECK"] = "1"
        self.run_controller("reload", success=False)
        self.assertFalse((self.root / "fast").exists())

    def test_failed_deletion_aborts_mutation_with_blocker_retained(self):
        self.run_controller("reload")
        self.env["FAIL_DELETE"] = "1"
        self.run_controller("suspend", "firewall", success=False)
        self.assertTrue((self.state / "blocked.firewall").exists())

    def test_failed_conntrack_drain_aborts_policy_mutation(self):
        self.run_controller("reload")
        self.env["FAIL_DRAIN"] = "1"
        self.run_controller("suspend", "passwall", success=False)
        self.assertFalse((self.root / "fast").exists())
        self.assertTrue((self.state / "active").exists())

    def test_stopped_service_cannot_be_reenabled_by_hotplug(self):
        self.run_controller("reload")
        self.run_controller("suspend", "service")
        self.run_controller("reload")
        self.assertFalse((self.root / "fast").exists())
        self.run_controller("resume", "service")
        self.assertTrue((self.root / "fast").exists())

    def test_fullcone_udp_uses_normal_path(self):
        self.env["FULLCONE"] = "1"
        self.run_controller("reload")
        self.assertNotIn("tcp, udp", (self.state / "rules").read_text())

    def test_unknown_ip_rules_prevent_admission(self):
        self.env["EXTRA_RULE"] = "1"
        self.run_controller("reload")
        self.assertFalse((self.root / "fast").exists())
        self.assertIn("Unsupported policy routing", (self.state / "status").read_text())

    def test_additional_forward_chain_prevents_admission(self):
        self.env["EXTRA_CHAIN"] = "1"
        self.run_controller("reload")
        self.assertFalse((self.root / "fast").exists())
        self.assertIn("Additional forward chains", (self.state / "status").read_text())

    def test_upgraded_unhooked_package_disables_admission(self):
        self.run_controller("reload")
        (self.root / "sbin/fw4").write_text("stock upgrade\n")
        self.run_controller("reload")
        self.assertFalse((self.root / "fast").exists())
        self.assertIn("integration missing", (self.state / "status").read_text())


if __name__ == "__main__":
    unittest.main()
