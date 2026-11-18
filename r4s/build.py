#!/usr/bin/env python3
"""Prepare a pinned R4S build without importing any device configuration."""

import hashlib
import gzip
import json
import os
import re
import shutil
import subprocess
import sys
import struct
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
LOCK = json.loads((HERE / "sources.lock.json").read_text())
NET_TUNE = HERE / "packages/r4s-net-tune"
NET_TUNE_FILES = (
    "etc/config/r4s_net_tune", "etc/init.d/r4s-net-tune",
    "usr/libexec/r4s-net-tune", "etc/hotplug.d/net/90-r4s-net-tune",
    "etc/uci-defaults/90-r4s-net-tune",
)
REQUIRED = (
    "luci", "luci-ssl", "luci-theme-argon", "dnsmasq-full", "firewall4",
    "luci-app-passwall", "sing-box", "xray-core", "luci-app-mosdns", "mosdns",
    "luci-app-lucky", "lucky", "luci-app-sqm", "luci-app-nlbwmon",
    "luci-app-upnp", "luci-app-wol", "luci-app-ttyd", "luci-app-filemanager",
    "htop", "ethtool", "tcpdump", "iperf3", "curl", "bind-dig",
    "kmod-nf-nat", "kmod-nft-nat", "kmod-nft-offload", "conntrack", "r4s-net-tune", "flock",
)
# target/linux/rockchip/image/Makefile derives the bootloader name from the
# device name and SoC: $(lastword $(subst _, ,friendlyarm_nanopi-r4s))-rk3399.
DEVICE_SUPPORTED = "friendlyarm,nanopi-r4s"
UBOOT_STAGING_NAME = "nanopi-r4s-rk3399-u-boot-rockchip.bin"
BOOTLOADER_SECTOR = 64
# pine64-img passes 32768 to gen_image_generic.sh, which is an alignment in KiB;
# the 32 MiB reserved area keeps the idbloader/U-Boot clear of the first partition.
PARTITION_ALIGN = 65536
BOOT_PAYLOADS = {"fit": b"\xd0\x0d\xfe\xed", "boot-script": b"\x27\x05\x19\x56"}
# package/network/services/uhttpd: PKG_SOURCE_DATE/PKG_SOURCE_VERSION of the
# backported 2026-11-05 request-slot update.
UHTTPD_SOURCE_DATE = "2026-11-05"
UHTTPD_SOURCE_VERSION = "93b05e0b65d91c23c5aa8fdde378df1f174ec71d"
DNSMASQ_PATCHES = (
    "001-fix_severe_SIGHUP_reload_slowdown.patch",
    "002-tune-store_name-fix-in-47864f3.patch",
)
KERNEL_MODULES = (
    "kmod-ifb", "kmod-nf-nat", "kmod-nft-nat", "kmod-nft-offload",
    "kmod-r8169", "kmod-sched-cake",
)


def run(*args, cwd=None, capture=False):
    return subprocess.run(args, cwd=cwd, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def checkout(spec, destination):
    if destination.exists():
        raise SystemExit(f"Refusing to overwrite {destination}")
    destination.mkdir(parents=True)
    run("git", "init", "-q", str(destination))
    run("git", "remote", "add", "origin", spec["url"], cwd=destination)
    run("git", "fetch", "--depth=1", "origin", spec["commit"], cwd=destination)
    run("git", "checkout", "--detach", "FETCH_HEAD", cwd=destination)
    actual = run("git", "rev-parse", "HEAD", cwd=destination, capture=True).strip()
    if actual != spec["commit"]:
        raise SystemExit(f"Source revision mismatch: {destination}")


def fullcone_patches():
    paths = {}
    for name, expected in LOCK["fullcone"]["patches"].items():
        path = HERE / "patches" / "fullcone" / name
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise SystemExit(f"FullCone patch checksum mismatch: {name}")
        paths[name] = path
    return paths


def prepare_fullcone(tree):
    patches = fullcone_patches()
    destinations = {
        "kernel.patch": "target/linux/generic/hack-6.12/982-r4s-bcm-fullcone.patch",
        "firewall4.patch": "package/network/config/firewall4/patches/999-r4s-bcm-fullcone.patch",
    }
    for name, relative in destinations.items():
        destination = tree / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            raise SystemExit(f"Refusing to overwrite {destination}")
        shutil.copyfile(patches[name], destination)
    target = tree / "target/linux/rockchip/Makefile"
    source = target.read_text()
    anchor = "KERNEL_PATCHVER:=6.12\n"
    if source.count(anchor) != 1 or re.search(r"^LINUX_RELEASE\s*[:?+]?=", source, re.M):
        raise SystemExit("Rockchip kernel release changed; review FullCone ABI isolation")
    # OpenWrt's kernel dependency includes this release. Do not impersonate
    # official modules: the config-only vermagic hash does not cover patches.
    target.write_text(source.replace(anchor, anchor + f"LINUX_RELEASE:={LOCK['fullcone']['kernel_release']}\n"))
    luci = tree / "feeds/luci"
    run("git", "apply", "--check", str(patches["luci.patch"]), cwd=luci)
    run("git", "apply", str(patches["luci.patch"]), cwd=luci)


def check_fullcone(tree):
    fullcone_patches()
    for name, relative in (
        ("kernel.patch", "target/linux/generic/hack-6.12/982-r4s-bcm-fullcone.patch"),
        ("firewall4.patch", "package/network/config/firewall4/patches/999-r4s-bcm-fullcone.patch"),
    ):
        path = tree / relative
        if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != LOCK["fullcone"]["patches"][name]:
            raise SystemExit(f"FullCone build patch missing or changed: {name}")
    target = (tree / "target/linux/rockchip/Makefile").read_text()
    if f"LINUX_RELEASE:={LOCK['fullcone']['kernel_release']}\n" not in target:
        raise SystemExit("FullCone kernel package ABI isolation missing")
    ui = tree / "feeds/luci/applications/luci-app-firewall/htdocs/luci-static/resources/view/firewall/zones.js"
    if not ui.exists() or not re.search(r"['\"]fullcone4['\"]", ui.read_text()):
        raise SystemExit("FullCone LuCI integration missing")


def check_fullcone_defaults(firewall):
    for option in ("fullcone4", "fullcone6"):
        values = re.findall(rf"^\s*option\s+{option}\s+['\"]?([01])['\"]?\s*$", firewall, re.M)
        if values != ["0"]:
            raise SystemExit(f"FullCone must be disabled in initial firewall config: {option}")


def check_native_forwarding(cli, ruleset, passwall, sqm):
    for name, source in (("firewall4", cli), ("PassWall", passwall), ("SQM", sqm)):
        if "r4s-accel" in source:
            raise SystemExit(f"Retired selective acceleration hook remains in {name}")
    if "flow offload @ft" not in ruleset or "flowtable ft" not in ruleset:
        raise SystemExit("Native firewall4 flowtable forwarding is missing")


def check_package_backports(tree):
    """Require the backported dnsmasq fix and uhttpd update in the prepared tree."""
    dnsmasq = tree / "package/network/services/dnsmasq"
    for name in DNSMASQ_PATCHES:
        patch = dnsmasq / "patches" / name
        if not patch.is_file():
            raise SystemExit(f"dnsmasq host-load backport patch missing: {name}")
        body = patch.read_text()
        if "store_name" not in body or "+++ b/" not in body:
            raise SystemExit(f"dnsmasq host-load backport patch is not the store_name fix: {name}")
    recipe = (dnsmasq / "Makefile").read_text()
    if not re.search(r"^PKG_RELEASE:=([2-9]|[1-9]\d+)$", recipe, re.M):
        raise SystemExit("dnsmasq release bump from the host-load backport is missing")
    uhttpd = (tree / "package/network/services/uhttpd/Makefile").read_text()
    for token in (f"PKG_SOURCE_DATE:={UHTTPD_SOURCE_DATE}",
                  f"PKG_SOURCE_VERSION:={UHTTPD_SOURCE_VERSION}"):
        if token not in uhttpd:
            raise SystemExit(f"uhttpd request-slot update missing from prepared tree: {token}")


def check_prepared(tree):
    check_fullcone(tree)
    check_package_backports(tree)
    kernels = list(tree.glob("build_dir/target-*/linux-rockchip_armv8/linux-*/net/netfilter/nf_nat_masquerade.c"))
    firewalls = list(tree.glob("build_dir/target-*/firewall4-*/root/usr/share/ucode/fw4.uc"))
    if len(kernels) != 1 or "void nf_nat_fullcone_helpers_register(void)" not in kernels[0].read_text():
        raise SystemExit("Prepared kernel lacks BCM FullCone support")
    if len(firewalls) != 1 or "function nft_try_brcmfullcone" not in firewalls[0].read_text():
        raise SystemExit("Prepared firewall4 lacks BCM FullCone support")
    check_fullcone_defaults((firewalls[0].parents[3] / "etc/config/firewall").read_text())
    pcie = kernels[0].parents[2] / "drivers/phy/rockchip/phy-rockchip-pcie.c"
    if "rockchip_pcie_phy_reset(rk_phy);" not in pcie.read_text():
        raise SystemExit("Prepared kernel lacks PCIe probe reset")
    fw4_cli = firewalls[0].parents[3] / "sbin/fw4"
    sqm = list(tree.glob("build_dir/target-*/sqm-scripts-*/platform/openwrt/sqm-init"))
    if len(sqm) != 1:
        raise SystemExit("Prepared stock SQM init script missing or ambiguous")
    check_native_forwarding(
        fw4_cli.read_text(),
        (firewalls[0].parents[3] / "usr/share/firewall4/templates/ruleset.uc").read_text(),
        (tree / "package/r4s-extras/passwall/luci-app-passwall/root/usr/share/passwall/nftables.sh").read_text(),
        sqm[0].read_text(),
    )
    print("Prepared FullCone, PCIe and native forwarding sources passed (not a runtime network test)")


def replace_once(path, before, after):
    text = path.read_text()
    if text.count(before) != 1:
        raise SystemExit(f"Pinned source changed; review integration: {path}")
    path.write_text(text.replace(before, after))


def prepare_net_tune(tree):
    destination = tree / "package/r4s-net-tune"
    if destination.exists():
        raise SystemExit("Refusing to overwrite the R4S network tuning package")
    shutil.copytree(NET_TUNE, destination,
                    ignore=shutil.ignore_patterns(".DS_Store", "__pycache__", "*.pyc"))


def check_net_tune(tree):
    package = tree / "package/r4s-net-tune"
    for relative in ("Makefile", *("files/" + name for name in NET_TUNE_FILES)):
        expected = NET_TUNE / relative
        actual = package / relative
        if not actual.is_file() or actual.is_symlink() or actual.read_bytes() != expected.read_bytes():
            raise SystemExit(f"R4S network tuning source missing or changed: {relative}")


def prepare_integrations(tree):
    destinations = {
        "pcie-reset.patch": "target/linux/rockchip/patches-6.12/402-1-r4s-pcie-reset.patch",
    }
    for name, relative in destinations.items():
        destination = tree / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            raise SystemExit(f"Refusing to overwrite {destination}")
        shutil.copyfile(HERE / "patches" / name, destination)
    upnp = tree / "feeds/packages/net/miniupnpd/files/miniupnpd.init"
    replace_once(upnp, "\t\tupnpd_write_bool secure_mode 1\n",
                 "\t\tupnpd_write_bool secure_mode 1\n\t\tupnpd_write_bool ext_allow_private_ipv4 0\n")
    ui = tree / "feeds/luci/applications/luci-app-upnp/htdocs/luci-static/resources/view/upnp/upnp.js"
    anchor = "\t\to = s.taboption('advanced', form.Flag, 'secure_mode', _('Enable secure mode'),"
    replace_once(ui, anchor, "\t\to = s.taboption('advanced', form.Flag, 'ext_allow_private_ipv4', _('Allow private IPv4 WAN'));\n"
                 "\t\to.default = '0';\n\t\to.rmempty = false;\n\n" + anchor)


def prepare(tree):
    checkout(LOCK["openwrt"], tree)
    apply_package_backports(tree)
    # The release already pins all official feeds. Use GitHub mirrors, same SHAs.
    feeds = (tree / "feeds.conf.default").read_text()
    feeds = feeds.replace("https://git.openwrt.org/feed/packages.git", "https://github.com/openwrt/packages.git")
    feeds = feeds.replace("https://git.openwrt.org/project/luci.git", "https://github.com/openwrt/luci.git")
    feeds = feeds.replace("https://git.openwrt.org/feed/routing.git", "https://github.com/openwrt/routing.git")
    feeds = feeds.replace("https://git.openwrt.org/feed/telephony.git", "https://github.com/openwrt/telephony.git")
    (tree / "feeds.conf").write_text(feeds)
    run("./scripts/feeds", "update", "-a", cwd=tree)
    run("./scripts/feeds", "install", "-a", cwd=tree)
    prepare_fullcone(tree)
    extras = tree / "package" / "r4s-extras"
    for name, spec in LOCK["extras"].items():
        # luci.mk derives the package name from the recipe directory name.
        directory = "luci-theme-argon" if name == "argon" else name
        checkout(spec, extras / directory)
    prepare_integrations(tree)
    prepare_net_tune(tree)
    # Xray 26.10.21 requires Go 1.27; select the pinned official host variant.
    xray = extras / "passwall_packages/xray-core/Makefile"
    recipe = xray.read_text()
    dependency = "PKG_BUILD_DEPENDS:=golang/host"
    if recipe.count(dependency) != 1 or not (tree / "feeds/packages/lang/golang/golang1.27/Makefile").is_file():
        raise SystemExit("Xray Go toolchain selection changed; review the pinned recipes")
    xray.write_text(recipe.replace(dependency, "PKG_BUILD_DEPENDS:=golang1.27/host"))
    # The pinned LuCI WeeChat UI selects a virtual package whose variants form
    # a Kconfig cycle. It is not part of this image; leave its source untouched.
    weechat_ui = tree / "package" / "feeds" / "luci" / "luci-app-weechat"
    if weechat_ui.is_symlink():
        weechat_ui.unlink()
    lucky_recipe = extras / "lucky" / "lucky" / "Makefile"
    recipe = lucky_recipe.read_text()
    if "PKG_HASH:=skip" not in recipe:
        raise SystemExit("Lucky download recipe changed; review its checksum handling")
    lucky_recipe.write_text(recipe.replace("PKG_HASH:=skip", "PKG_HASH:=" + LOCK["extras"]["lucky"]["arm64_sha256"]))
    # Resolve package name collisions explicitly: the maintained PassWall feed
    # supplies matching core recipes. Official package repositories stay intact.
    for recipe in (extras / "passwall_packages").glob("*/Makefile"):
        link = tree / "package" / "feeds" / "packages" / recipe.parent.name
        if link.is_symlink():
            link.unlink()
    for recipe in (extras / "mosdns").glob("*/Makefile"):
        for feed in ("packages", "luci"):
            link = tree / "package" / "feeds" / feed / recipe.parent.name
            if link.is_symlink():
                link.unlink()
    shutil.copyfile(HERE / "config.seed", tree / ".config")
    shutil.copyfile(HERE / "sources.lock.json", tree / "sources.lock.buildinfo")
    revisions = {}
    for feed in (tree / "feeds").iterdir():
        if feed.is_dir() and (feed / ".git").exists():
            revisions[feed.name] = run("git", "rev-parse", "HEAD", cwd=feed, capture=True).strip()
    (tree / "feeds.revisions.buildinfo").write_text(json.dumps(revisions, indent=2) + "\n")


def apply_package_backports(tree):
    for commit in LOCK["openwrt_package_backports"]:
        run("git", "fetch", "--depth=2", "origin", commit, cwd=tree)
        diff = run("git", "diff", "--binary", f"{commit}^", commit,
                   cwd=tree, capture=True)
        if not diff:
            raise SystemExit(f"Empty OpenWrt package backport: {commit}")
        subprocess.run(["git", "apply", "--index"], cwd=tree,
                       input=diff, text=True, check=True)


def check_config(tree):
    config = set((tree / ".config").read_text().splitlines())
    missing = [name for name in REQUIRED if f"CONFIG_PACKAGE_{name}=y" not in config]
    for option in (
        "TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r4s",
        "TARGET_ROOTFS_SQUASHFS", "PACKAGE_luci-app-passwall_Nftables_Transparent_Proxy",
        "SING_BOX_BUILD_UTLS", "SING_BOX_BUILD_QUIC", "SING_BOX_BUILD_GRPC",
    ):
        if f"CONFIG_{option}=y" not in config:
            missing.append(option)
    if 'CONFIG_TARGET_OPTIMIZATION="-O2 -pipe -mcpu=generic"' not in config:
        missing.append("O2 with unchanged generic AArch64 ISA")
    forbidden = [line for line in config if re.match(
        r"CONFIG_PACKAGE_(dockerd|luci-app-dockerman|luci-app-openclash|luci-app-homeproxy|luci-app-ssr-plus|r4s-accel)=y$", line)]
    if missing or forbidden:
        raise SystemExit(f"Missing selections: {missing}; forbidden selections: {forbidden}")
    if (tree / "files").exists():
        raise SystemExit("Unexpected files overlay: no personal configuration may enter this build")
    check_fullcone(tree)
    check_net_tune(tree)
    for name, relative in (
        ("pcie-reset.patch", "target/linux/rockchip/patches-6.12/402-1-r4s-pcie-reset.patch"),
    ):
        if (tree / relative).read_bytes() != (HERE / "patches" / name).read_bytes():
            raise SystemExit(f"Integration patch missing or changed: {name}")
    for relative in ("package/r4s-accel",
                     "package/network/config/firewall4/patches/998-r4s-lifecycle.patch",
                     "feeds/packages/net/sqm-scripts/patches/950-r4s-lifecycle.patch"):
        if (tree / relative).exists():
            raise SystemExit(f"Retired selective acceleration integration remains: {relative}")
    print("R4S target, required packages and stock configuration checks passed")


def _partition(table, index):
    base = 446 + index * 16
    return table[base + 4], *struct.unpack_from("<II", table, base + 8)


def _partition_mib(tree, option):
    match = re.search(rf"^CONFIG_{option}=(\d+)$", (tree / ".config").read_text(), re.M)
    if not match:
        raise SystemExit(f"Target partition size {option} missing from .config")
    return int(match.group(1))


def _staging_image_directory(tree):
    directories = [path for path in tree.glob("staging_dir/target-*/image") if path.is_dir()]
    if len(directories) != 1:
        raise SystemExit(f"Expected one staging image directory, found {len(directories)}")
    return directories[0]


def verify_boot_area(image, tree):
    """Check the staged bootloader bytes, partition layout and boot payload.

    The boot partition is created by scripts/gen_image_generic.sh, which only
    builds a FAT filesystem when GUID is set. Rockchip images leave GUID unset,
    so the expected type is ext4 with the label kernel; FAT is still accepted if
    the filesystem and its payload are intact, so an upstream switch is not
    reported as corruption.
    """
    kernel_mib = _partition_mib(tree, "TARGET_KERNEL_PARTSIZE")
    rootfs_mib = _partition_mib(tree, "TARGET_ROOTFS_PARTSIZE")
    staging = _staging_image_directory(tree)
    bootloader = staging / UBOOT_STAGING_NAME
    if not bootloader.is_file():
        present = sorted(path.name for path in staging.glob("*-u-boot-rockchip.bin"))
        raise SystemExit(f"Device U-Boot image {UBOOT_STAGING_NAME} missing; staging holds {present}")
    payload = bootloader.read_bytes()
    if len(payload) < 512:
        raise SystemExit("Device U-Boot image is empty")
    with gzip.open(image, "rb") as stream:
        table = stream.read(512)
        if table[510:512] != b"\x55\xaa":
            raise SystemExit("Firmware MBR signature missing")
        kernel_type, kernel_start, kernel_count = _partition(table, 0)
        rootfs_type, rootfs_start, rootfs_count = _partition(table, 1)
        if (kernel_type, rootfs_type) != (0x83, 0x83):
            raise SystemExit(f"Unexpected partition types {kernel_type:#x}/{rootfs_type:#x}")
        if kernel_count != kernel_mib * 2048 or rootfs_count != rootfs_mib * 2048:
            raise SystemExit("Partition sizes do not match the target configuration")
        loader_start = BOOTLOADER_SECTOR * 512
        if kernel_start * 512 < loader_start + len(payload):
            raise SystemExit("Device U-Boot overlaps the boot partition")
        if kernel_start % PARTITION_ALIGN:
            raise SystemExit("Boot partition does not start on the 32 MiB U-Boot boundary")
        if rootfs_start % PARTITION_ALIGN:
            raise SystemExit("Root partition ignores the U-Boot aligned reserved area")
        if kernel_start + kernel_count > rootfs_start:
            raise SystemExit("Boot and root partitions overlap")
        stream.seek(loader_start)
        if stream.read(len(payload)) != payload:
            raise SystemExit("Embedded U-Boot bytes differ from the staged bootloader")
        offset = loader_start + len(payload)
        while offset < kernel_start * 512:
            chunk = stream.read(min(1 << 20, kernel_start * 512 - offset))
            if not chunk:
                raise SystemExit("Truncated firmware image")
            if chunk.strip(b"\0"):
                raise SystemExit("Stale bytes remain between the bootloader and the boot partition")
            offset += len(chunk)
        stream.seek(kernel_start * 512 + 1024)
        superblock = stream.read(1024)
        if len(superblock) != 1024:
            raise SystemExit("Truncated boot partition")
        if struct.unpack_from("<H", superblock, 0x38)[0] == 0xEF53:
            block_size = 1024 << struct.unpack_from("<I", superblock, 0x18)[0]
            blocks = struct.unpack_from("<I", superblock, 4)[0]
            free = struct.unpack_from("<I", superblock, 12)[0]
            if block_size not in (1024, 2048, 4096) or blocks * block_size != kernel_count * 512:
                raise SystemExit("Boot ext4 filesystem size does not cover its partition")
            label = superblock[0x78:0x88].split(b"\0")[0]
        elif superblock[0x36:0x3E] == b"FAT16   " or superblock[0x52:0x5A] == b"FAT32   ":
            label = superblock[0x2B:0x36].rstrip(b" ") if superblock[0x36:0x3E] == b"FAT16   " \
                else superblock[0x47:0x52].rstrip(b" ")
            blocks, free = kernel_count, kernel_count - 1
        else:
            raise SystemExit("Boot partition is neither ext4 nor FAT")
        if label != b"kernel":
            raise SystemExit(f"Boot filesystem label is {label!r}, expected b'kernel'")
        if not 0 < blocks - free <= blocks:
            raise SystemExit("Boot filesystem is empty")
        stream.seek(kernel_start * 512)
        found = set()
        carry = b""
        remaining = kernel_count * 512
        while remaining and len(found) < len(BOOT_PAYLOADS):
            chunk = stream.read(min(1 << 20, remaining))
            if not chunk:
                raise SystemExit("Truncated boot partition")
            window = carry + chunk
            for name, magic in BOOT_PAYLOADS.items():
                if name not in found and magic in window:
                    found.add(name)
            carry = window[-3:]
            remaining -= len(chunk)
    missing = sorted(set(BOOT_PAYLOADS) - found)
    if missing:
        raise SystemExit(f"Boot partition lacks {missing}: kernel or boot script not installed")


def verify_device_metadata(image, tree):
    """Require the fwtool metadata to name this device and no other firmware."""
    tool = tree / "staging_dir/host/bin/fwtool"
    if not tool.is_file():
        raise SystemExit("fwtool host tool missing; refusing to guess the image device identity")
    with tempfile.TemporaryDirectory() as temp:
        metadata = Path(temp) / "metadata.json"
        result = subprocess.run([str(tool), "-q", "-i", str(metadata), str(image)],
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if not metadata.is_file() or not metadata.stat().st_size:
            raise SystemExit(
                f"Firmware metadata missing or unreadable (fwtool exit {result.returncode}): "
                f"{result.stderr.strip()}")
        data = json.loads(metadata.read_text())
    if data.get("metadata_version") not in ("1.0", "1.1"):
        raise SystemExit(f"Unsupported firmware metadata version: {data.get('metadata_version')}")
    supported = data.get("supported_devices") or []
    if DEVICE_SUPPORTED not in supported:
        raise SystemExit(f"Firmware targets {supported}, expected {DEVICE_SUPPORTED}")


def verify_image(image, tree=None):
    # Rockchip SD images use an MBR; read the actual second partition rootfs.
    with gzip.open(image, "rb") as stream:
        mbr = stream.read(512)
        if mbr[510:512] != b"\x55\xaa":
            raise SystemExit("Firmware MBR signature missing")
        sector, count = struct.unpack_from("<II", mbr, 446 + 16 + 8)
        if not sector or not count:
            raise SystemExit("Firmware root partition missing")
        stream.seek(sector * 512)
        header = stream.read(96)
        if header[:4] != b"hsqs":
            raise SystemExit("Root partition is not SquashFS")
        used = struct.unpack_from("<Q", header, 40)[0]
        if not 96 <= used <= count * 512:
            raise SystemExit("Invalid SquashFS size")
        with tempfile.TemporaryDirectory() as temp:
            squashfs = Path(temp) / "root.squashfs"
            with squashfs.open("wb") as output:
                output.write(header)
                remaining = used - len(header)
                while remaining:
                    chunk = stream.read(min(1024 * 1024, remaining))
                    if not chunk:
                        raise SystemExit("Truncated firmware rootfs")
                    output.write(chunk)
                    remaining -= len(chunk)
            listing = set(run("unsquashfs", "-lln", str(squashfs), capture=True).splitlines())
            entries = {}
            for line in listing:
                fields = line.split()
                name = next((word for word in fields if word.startswith("squashfs-root/")), None)
                if name:
                    entries[name] = fields
            paths = set(entries)
            for name in ("usr/bin/mosdns", "usr/bin/sing-box", "usr/bin/xray", "usr/bin/lucky",
                         "etc/init.d/passwall", "etc/init.d/mosdns", "etc/init.d/lucky"):
                if f"squashfs-root/{name}" not in paths:
                    raise SystemExit(f"Required file missing from firmware: {name}")
            firewall = run("unsquashfs", "-cat", str(squashfs), "etc/config/firewall", capture=True)
            check_fullcone_defaults(firewall)
            retired = {path for path in paths if "r4s-accel" in path or "r4s_accel" in path}
            if retired:
                raise SystemExit(f"Retired selective acceleration files remain in firmware: {sorted(retired)}")
            for name in NET_TUNE_FILES:
                if f"squashfs-root/{name}" not in paths:
                    raise SystemExit(f"R4S network tuning file missing from firmware: {name}")
                actual = run("unsquashfs", "-cat", str(squashfs), name, capture=True)
                if actual != (NET_TUNE / "files" / name).read_text():
                    raise SystemExit(f"R4S network tuning file changed in firmware: {name}")
                if name != "etc/config/r4s_net_tune" and entries[f"squashfs-root/{name}"][0][3:4] != "x":
                    raise SystemExit(f"R4S network tuning script is not executable: {name}")
            if "squashfs-root/etc/rc.d/S19r4s-net-tune" not in paths:
                raise SystemExit("R4S network tuning boot service is not enabled in firmware")
            boot = entries["squashfs-root/etc/rc.d/S19r4s-net-tune"]
            if not boot[0].startswith("l") or boot[-2:] != ["->", "../init.d/r4s-net-tune"]:
                raise SystemExit("R4S network tuning boot service link is invalid")
            check_native_forwarding(*(run("unsquashfs", "-cat", str(squashfs), path, capture=True)
                                      for path in ("sbin/fw4", "usr/share/firewall4/templates/ruleset.uc",
                                                   "usr/share/passwall/nftables.sh", "etc/init.d/sqm")))
            upnp = run("unsquashfs", "-cat", str(squashfs), "etc/init.d/miniupnpd", capture=True)
            if "upnpd_write_bool ext_allow_private_ipv4 0" not in upnp:
                raise SystemExit("UPnP private WAN option missing")
            fw4 = run("unsquashfs", "-cat", str(squashfs), "usr/share/ucode/fw4.uc", capture=True)
            if "function nft_try_brcmfullcone" not in fw4:
                raise SystemExit("FullCone fw4 support missing from firmware")
            ui = run("unsquashfs", "-cat", str(squashfs),
                     "www/luci-static/resources/view/firewall/zones.js", capture=True)
            if '"fullcone4"' not in ui and "'fullcone4'" not in ui:
                raise SystemExit("FullCone LuCI support missing from firmware")
    if tree is not None:
        verify_boot_area(image, tree)
        verify_device_metadata(image, tree)


def _manifest_versions(manifest):
    versions = {}
    for line in manifest.splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[1] == "-":
            versions[fields[0]] = fields[2]
    return versions


def check_service_versions(tree, manifest):
    """Require the manifest versions to match the prepared service recipes."""
    versions = _manifest_versions(manifest)
    dnsmasq = (tree / "package/network/services/dnsmasq/Makefile").read_text()
    upstream = re.search(r"^PKG_UPSTREAM_VERSION:=(\S+)$", dnsmasq, re.M)
    release = re.search(r"^PKG_RELEASE:=(\d+)$", dnsmasq, re.M)
    if not upstream or not release:
        raise SystemExit("dnsmasq recipe lost its version fields")
    expected = f"{upstream.group(1)}-r{release.group(1)}"
    if versions.get("dnsmasq-full") != expected:
        raise SystemExit(f"dnsmasq-full is {versions.get('dnsmasq-full')}, expected {expected}")
    uhttpd = (tree / "package/network/services/uhttpd/Makefile").read_text()
    uhttpd_release = re.search(r"^PKG_RELEASE:=(\d+)$", uhttpd, re.M)
    if not uhttpd_release:
        raise SystemExit("uhttpd recipe lost its release field")
    # Manifest versions normalize the source date to dots (e.g. 2026.11.05~93b05e0b-r1).
    date = UHTTPD_SOURCE_DATE.replace("-", ".")
    expected_uhttpd = f"{date}~{UHTTPD_SOURCE_VERSION[:8]}-r{uhttpd_release.group(1)}"
    if versions.get("uhttpd") != expected_uhttpd:
        raise SystemExit(f"uhttpd is {versions.get('uhttpd')}, expected {expected_uhttpd}")


def check_kernel_modules(tree, manifest):
    """Require shipped target kernel modules to pin the kernel built here."""
    versions = _manifest_versions(manifest)
    kernel = versions.get("kernel")
    if not kernel:
        raise SystemExit("Firmware manifest lacks the kernel package")
    metadata = tree / "tmp/.packageinfo"
    if not metadata.is_file():
        raise SystemExit("Build package metadata tmp/.packageinfo is missing")
    depends, current = {}, None
    for line in metadata.read_text().splitlines():
        header = re.match(r"^Package: (\S+)$", line)
        if header:
            current = header.group(1)
        elif current and line.startswith("Depends:"):
            depends[current] = line.split(":", 1)[1].strip()
    for name in KERNEL_MODULES:
        if name not in versions:
            raise SystemExit(f"Kernel module {name} missing from the image manifest")
        if f"kernel (={kernel})" not in depends.get(name, ""):
            raise SystemExit(f"Kernel module {name} is not pinned to the built kernel {kernel}")


def _sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_provenance(image, kernel, output):
    def environment(name):
        return os.environ.get(name) or "unknown"

    try:
        commit = subprocess.run(("git", "rev-parse", "HEAD"), cwd=HERE, text=True,
                                stdout=subprocess.PIPE, check=True).stdout.strip()
    except (subprocess.CalledProcessError, OSError):
        commit = "unknown"
    payload = {
        "schema": "r4s-build-provenance/1",
        "source": {
            "repository": environment("GITHUB_REPOSITORY"),
            "commit": environment("GITHUB_SHA") if os.environ.get("GITHUB_SHA") else commit,
            "ref": environment("GITHUB_REF_NAME"),
        },
        "workflow": {
            "name": environment("GITHUB_WORKFLOW"),
            "run_id": environment("GITHUB_RUN_ID"),
            "run_attempt": environment("GITHUB_RUN_ATTEMPT"),
            "run_number": environment("GITHUB_RUN_NUMBER"),
            "server": environment("GITHUB_SERVER_URL"),
        },
        "openwrt": {"commit": LOCK["openwrt"]["commit"]},
        "device": DEVICE_SUPPORTED,
        "kernel_package": kernel,
        "image": {
            "name": image.name,
            "bytes": image.stat().st_size,
            "sha256": _sha256(image),
        },
        "inputs": {name: hashlib.sha256((HERE / name).read_bytes()).hexdigest()
                   for name in ("sources.lock.json", "config.seed")},
    }
    (output / "build-provenance.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n")


def collect(tree, output):
    check_config(tree)
    target = tree / "bin" / "targets" / "rockchip" / "armv8"
    images = list(target.glob("*friendlyarm_nanopi-r4s-squashfs-sysupgrade.img.gz"))
    if len(images) != 1:
        raise SystemExit(f"Expected one R4S image, found {len(images)}")
    verify_image(images[0], tree)
    manifests = list(target.glob("*friendlyarm_nanopi-r4s.manifest"))
    if len(manifests) != 1:
        raise SystemExit("R4S image manifest missing")
    manifest = manifests[0].read_text()
    packages = {line.split()[0] for line in manifest.splitlines() if line.strip()}
    if not re.search(rf"^kernel\s+-\s+\S+-r{LOCK['fullcone']['kernel_release']}$", manifest, re.M):
        raise SystemExit("Firmware manifest lacks the isolated FullCone kernel package release")
    check_service_versions(tree, manifest)
    check_kernel_modules(tree, manifest)
    missing = set(REQUIRED) - packages
    if missing:
        raise SystemExit(f"Required packages missing from image manifest: {sorted(missing)}")
    if "r4s-accel" in packages:
        raise SystemExit("Retired selective acceleration package remains in image manifest")
    output.mkdir(parents=True)
    for file in target.iterdir():
        if file.is_file():
            name = "openwrt-sha256sums" if file.name == "sha256sums" else file.name
            shutil.copy2(file, output / name)
    for name in ("sources.lock.buildinfo", "feeds.revisions.buildinfo", "config.seed.buildinfo"):
        shutil.copy2(tree / name, output / name)
    shutil.copy2(tree / ".config", output / "full.config.buildinfo")
    tuning_info = {
        "references": LOCK["network_tuning"]["references"],
        "files": {name: hashlib.sha256((NET_TUNE / "files" / name).read_bytes()).hexdigest()
                  for name in NET_TUNE_FILES},
        "validation_scope": "source, package selection and image contents; not device throughput",
    }
    (output / "network-tuning.buildinfo").write_text(json.dumps(tuning_info, indent=2) + "\n")
    if (tree / "public-key.pem").exists():
        shutil.copy2(tree / "public-key.pem", output / "public-key.pem")
    run("tar", "--zstd", "-cf", str(output / "r4s-apk-packages.tar.zst"),
        "-C", str(tree / "bin"), "packages", "targets/rockchip/armv8/packages")
    write_provenance(images[0], _manifest_versions(manifest)["kernel"], output)
    sums = []
    for file in sorted(output.iterdir()):
        if file.is_file() and file.name != "SHA256SUMS":
            with file.open("rb") as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            sums.append(f"{digest}  {file.name}\n")
    (output / "SHA256SUMS").write_text("".join(sums))
    print(f"Verified R4S firmware and package artifacts: {output}")


if __name__ == "__main__":
    command = sys.argv[1]
    tree = Path(sys.argv[2]).resolve()
    if command == "prepare":
        prepare(tree)
    elif command == "check-config":
        check_config(tree)
    elif command == "check-prepared":
        check_prepared(tree)
    elif command == "collect":
        collect(tree, Path(sys.argv[3]).resolve())
    else:
        raise SystemExit(f"Unknown command: {command}")
