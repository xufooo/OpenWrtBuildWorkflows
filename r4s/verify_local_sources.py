#!/usr/bin/env python3
"""Apply integrations to pinned, isolated source files, never a device."""
import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("build", HERE / "build.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


def export(repo, commit, source, root, destination=None):
    path = root / (destination or source)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(subprocess.check_output(["git", "show", f"{commit}:{source}"], cwd=repo))
    return path


if __name__ == "__main__":
    official, fw4, packages, passwall, sqm, upnp_ui, phy = map(Path, sys.argv[1:])
    with tempfile.TemporaryDirectory(prefix="r4s-integrations-") as temp:
        tree = Path(temp)
        fwroot = tree / "fw4"
        export(fw4, "b6e5157527d361f99ad52eaa6da273cb0f2dfd59", "root/sbin/fw4", fwroot)
        subprocess.run(["git", "apply", str(HERE / "patches/firewall4-lifecycle.patch")], cwd=fwroot, check=True)
        sqmroot = tree / "sqm"
        export(sqm, "20ba92639546075d8e39346dcb88a3cdfe8ee903", "platform/openwrt/sqm-init", sqmroot)
        subprocess.run(["git", "apply", str(HERE / "patches/sqm-lifecycle.patch")], cwd=sqmroot, check=True)
        kernel = tree / "kernel"
        dest = kernel / "drivers/phy/rockchip/phy-rockchip-pcie.c"
        dest.parent.mkdir(parents=True)
        dest.write_bytes(phy.read_bytes())
        lane = official / "target/linux/rockchip/patches-6.12/036-06-v6.17-phy-rockchip-pcie-Enable-all-four-lanes-if-required.patch"
        subprocess.run(["git", "apply", str(lane)], cwd=kernel, check=True)
        subprocess.run(["git", "apply", str(HERE / "patches/pcie-reset.patch")], cwd=kernel, check=True)
        export(packages, "093d551675b1119a06ef224d419905e8d6b2af1a", "net/miniupnpd/files/miniupnpd.init",
               tree, "feeds/packages/net/miniupnpd/files/miniupnpd.init")
        ui = tree / "feeds/luci/applications/luci-app-upnp/htdocs/luci-static/resources/view/upnp/upnp.js"
        ui.parent.mkdir(parents=True)
        ui.write_bytes(upnp_ui.read_bytes())
        pw = export(passwall, build.LOCK["extras"]["passwall"]["commit"],
                    "luci-app-passwall/root/usr/share/passwall/nftables.sh", tree,
                    "package/r4s-extras/passwall/luci-app-passwall/root/usr/share/passwall/nftables.sh")
        build.prepare_integrations(tree)
        for path in (fwroot / "root/sbin/fw4", sqmroot / "platform/openwrt/sqm-init", pw):
            subprocess.run(["bash", "-n", str(path)], check=True)
        assert "rockchip_pcie_phy_reset(rk_phy);" in dest.read_text()
        print("Pinned fw4, SQM, PassWall, UPnP and PCIe patch application passed")
