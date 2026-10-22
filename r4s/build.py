#!/usr/bin/env python3
"""Prepare a stock R4S build without importing any device configuration."""

import hashlib
import gzip
import json
import re
import shutil
import subprocess
import sys
import struct
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
LOCK = json.loads((HERE / "sources.lock.json").read_text())
REQUIRED = (
    "luci", "luci-ssl", "luci-theme-argon", "dnsmasq-full", "firewall4",
    "luci-app-passwall", "sing-box", "xray-core", "luci-app-mosdns", "mosdns",
    "luci-app-lucky", "lucky", "luci-app-sqm", "luci-app-nlbwmon",
    "luci-app-upnp", "luci-app-wol", "luci-app-ttyd", "luci-app-filemanager",
    "htop", "ethtool", "tcpdump", "iperf3", "curl", "bind-dig",
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


def prepare(tree):
    checkout(LOCK["openwrt"], tree)
    # The release already pins all official feeds. Use GitHub mirrors, same SHAs.
    feeds = (tree / "feeds.conf.default").read_text()
    feeds = feeds.replace("https://git.openwrt.org/feed/packages.git", "https://github.com/openwrt/packages.git")
    feeds = feeds.replace("https://git.openwrt.org/project/luci.git", "https://github.com/openwrt/luci.git")
    feeds = feeds.replace("https://git.openwrt.org/feed/routing.git", "https://github.com/openwrt/routing.git")
    feeds = feeds.replace("https://git.openwrt.org/feed/telephony.git", "https://github.com/openwrt/telephony.git")
    (tree / "feeds.conf").write_text(feeds)
    run("./scripts/feeds", "update", "-a", cwd=tree)
    run("./scripts/feeds", "install", "-a", cwd=tree)
    extras = tree / "package" / "r4s-extras"
    for name, spec in LOCK["extras"].items():
        checkout(spec, extras / name)
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
    forbidden = [line for line in config if re.match(
        r"CONFIG_PACKAGE_(dockerd|luci-app-dockerman|luci-app-openclash|luci-app-homeproxy|luci-app-ssr-plus)=y$", line)]
    if missing or forbidden:
        raise SystemExit(f"Missing selections: {missing}; forbidden selections: {forbidden}")
    if (tree / "files").exists():
        raise SystemExit("Unexpected files overlay: no personal configuration may enter this build")
    print("R4S target, required packages and stock configuration checks passed")


def verify_image(image):
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
            paths = {line.split()[-1] for line in listing if line.split()}
            for name in ("usr/bin/mosdns", "usr/bin/sing-box", "usr/bin/xray", "usr/bin/lucky",
                         "etc/init.d/passwall", "etc/init.d/mosdns", "etc/init.d/lucky"):
                if f"squashfs-root/{name}" not in paths:
                    raise SystemExit(f"Required file missing from firmware: {name}")


def collect(tree, output):
    check_config(tree)
    target = tree / "bin" / "targets" / "rockchip" / "armv8"
    images = list(target.glob("*friendlyarm_nanopi-r4s-squashfs-sysupgrade.img.gz"))
    if len(images) != 1:
        raise SystemExit(f"Expected one R4S image, found {len(images)}")
    verify_image(images[0])
    manifests = list(target.glob("*friendlyarm_nanopi-r4s.manifest"))
    if len(manifests) != 1:
        raise SystemExit("R4S image manifest missing")
    packages = {line.split()[0] for line in manifests[0].read_text().splitlines() if line.strip()}
    missing = set(REQUIRED) - packages
    if missing:
        raise SystemExit(f"Required packages missing from image manifest: {sorted(missing)}")
    output.mkdir(parents=True)
    for file in target.iterdir():
        if file.is_file():
            shutil.copy2(file, output / file.name)
    for name in ("sources.lock.buildinfo", "feeds.revisions.buildinfo", "config.seed.buildinfo"):
        shutil.copy2(tree / name, output / name)
    shutil.copy2(tree / ".config", output / "full.config.buildinfo")
    if (tree / "key-build.pub").exists():
        shutil.copy2(tree / "key-build.pub", output / "key-build.pub")
    run("tar", "--zstd", "-cf", str(output / "r4s-apk-packages.tar.zst"),
        "-C", str(tree / "bin"), "packages")
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
    elif command == "collect":
        collect(tree, Path(sys.argv[3]).resolve())
    else:
        raise SystemExit(f"Unknown command: {command}")
