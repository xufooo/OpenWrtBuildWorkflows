"""Offline regression checks for source preparation and package selection."""

import importlib.util
import gzip
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("r4s_build", Path(__file__).with_name("build.py"))
build = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build)


class BuildTests(unittest.TestCase):
    def image_fixture(self, root, retired=None, hook=None):
        mbr = bytearray(512)
        mbr[510:512] = b"\x55\xaa"
        struct.pack_into("<II", mbr, 446 + 16 + 8, 1, 1)
        header = bytearray(96)
        header[:4] = b"hsqs"
        struct.pack_into("<Q", header, 40, 96)
        image = root / "test.img.gz"
        image.write_bytes(gzip.compress(mbr + header))
        contents = {name: "binary fixture" for name in (
            "usr/bin/mosdns", "usr/bin/sing-box", "usr/bin/xray", "usr/bin/lucky",
            "etc/init.d/passwall", "etc/init.d/mosdns", "etc/init.d/lucky")}
        contents.update({
            "etc/config/firewall": "option fullcone4 0\noption fullcone6 0\n",
            "sbin/fw4": "stock fw4",
            "usr/share/firewall4/templates/ruleset.uc": "flowtable ft {}\nflow offload @ft;",
            "usr/share/passwall/nftables.sh": "stock PassWall",
            "etc/init.d/sqm": "stock SQM",
            "etc/init.d/miniupnpd": "upnpd_write_bool ext_allow_private_ipv4 0",
            "usr/share/ucode/fw4.uc": "function nft_try_brcmfullcone() {}",
            "www/luci-static/resources/view/firewall/zones.js": "var option = 'fullcone4';",
        })
        if retired:
            contents[retired] = "retired fixture"
        if hook:
            contents[hook] += "\n# r4s-accel lifecycle v1"

        def unsquashfs(*args, **kwargs):
            self.assertEqual(args[0], "unsquashfs")
            if args[1] == "-lln":
                return "\n".join("squashfs-root/" + name for name in contents)
            self.assertEqual(args[1], "-cat")
            return contents[args[-1]]

        return image, unsquashfs

    def test_image_accepts_native_forwarding_without_retired_component(self):
        with tempfile.TemporaryDirectory() as temp:
            image, reader = self.image_fixture(Path(temp))
            with patch.object(build, "run", side_effect=reader):
                build.verify_image(image)

    def test_image_rejects_retired_files_and_hooks(self):
        for retired, hook in (("usr/libexec/r4s-accel", None),
                              ("etc/config/r4s_accel", None),
                              (None, "usr/share/passwall/nftables.sh"),
                              (None, "etc/init.d/sqm"), (None, "sbin/fw4")):
            with self.subTest(retired=retired, hook=hook), tempfile.TemporaryDirectory() as temp:
                image, reader = self.image_fixture(Path(temp), retired, hook)
                with patch.object(build, "run", side_effect=reader), self.assertRaisesRegex(SystemExit, "Retired"):
                    build.verify_image(image)

    def integration_fixture(self, tree):
        fixtures = {
            "feeds/packages/net/miniupnpd/files/miniupnpd.init": "\t\tupnpd_write_bool secure_mode 1\n",
            "feeds/luci/applications/luci-app-upnp/htdocs/luci-static/resources/view/upnp/upnp.js":
                "\t\to = s.taboption('advanced', form.Flag, 'secure_mode', _('Enable secure mode'),\n",
            "package/r4s-extras/passwall/luci-app-passwall/root/usr/share/passwall/nftables.sh":
                "start)\n\tstart\n\t;;\nstop)\n\tstop\n\t;;\n",
        }
        for relative, content in fixtures.items():
            path = tree / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)

    def fullcone_fixture(self, tree):
        target = tree / "target/linux/rockchip/Makefile"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("KERNEL_PATCHVER:=6.12\n")
        ui = tree / "feeds/luci/applications/luci-app-firewall/htdocs/luci-static/resources/view/firewall/zones.js"
        ui.parent.mkdir(parents=True, exist_ok=True)
        ui.write_text('var option = "fullcone4";\n')

    def test_prepare_preserves_package_names_and_sources(self):
        with tempfile.TemporaryDirectory() as temp:
            tree = Path(temp) / "openwrt"

            def checkout(spec, destination):
                destination.mkdir(parents=True, exist_ok=True)
                if spec is build.LOCK["openwrt"]:
                    (destination / "feeds.conf.default").write_text("")
                    self.fullcone_fixture(destination)
                    self.integration_fixture(destination)
                    golang = destination / "feeds/packages/lang/golang/golang1.27/Makefile"
                    golang.parent.mkdir(parents=True)
                    golang.touch()
                    for feed, name in (("luci", "luci-app-weechat"), ("packages", "sing-box")):
                        source = destination / "feeds" / feed / name
                        source.mkdir(parents=True)
                        (source / "Makefile").write_text("upstream source\n")
                        link = destination / "package" / "feeds" / feed / name
                        link.parent.mkdir(parents=True, exist_ok=True)
                        link.symlink_to(source, target_is_directory=True)
                elif spec is build.LOCK["extras"]["lucky"]:
                    (destination / "lucky").mkdir()
                    (destination / "lucky" / "Makefile").write_text("PKG_HASH:=skip\n")
                elif spec is build.LOCK["extras"]["passwall_packages"]:
                    (destination / "sing-box").mkdir()
                    (destination / "sing-box" / "Makefile").touch()
                    (destination / "xray-core").mkdir()
                    (destination / "xray-core/Makefile").write_text("PKG_BUILD_DEPENDS:=golang/host\n")

            with patch.object(build, "checkout", side_effect=checkout), patch.object(build, "run"):
                build.prepare(tree)
            extras = tree / "package" / "r4s-extras"
            self.assertTrue((extras / "luci-theme-argon").is_dir())
            self.assertFalse((extras / "argon").exists())
            self.assertFalse((tree / "package/feeds/luci/luci-app-weechat").is_symlink())
            self.assertFalse((tree / "package/feeds/packages/sing-box").is_symlink())
            self.assertEqual((tree / "feeds/luci/luci-app-weechat/Makefile").read_text(), "upstream source\n")
            self.assertIn(build.LOCK["extras"]["lucky"]["arm64_sha256"],
                          (extras / "lucky/lucky/Makefile").read_text())
            self.assertEqual((tree / ".config").read_bytes(), (build.HERE / "config.seed").read_bytes())
            self.assertFalse((tree / "files").exists())
            self.assertIn("PKG_BUILD_DEPENDS:=golang1.27/host", (extras / "passwall_packages/xray-core/Makefile").read_text())
            build.check_fullcone(tree)

    def make_config(self, tree):
        options = [f"CONFIG_PACKAGE_{name}=y" for name in build.REQUIRED]
        options += ["CONFIG_" + name + "=y" for name in (
            "TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r4s",
            "TARGET_ROOTFS_SQUASHFS", "PACKAGE_luci-app-passwall_Nftables_Transparent_Proxy",
            "SING_BOX_BUILD_UTLS", "SING_BOX_BUILD_QUIC", "SING_BOX_BUILD_GRPC",
        )]
        (tree / ".config").write_text("\n".join(options) + "\n")
        with (tree / ".config").open("a") as config:
            config.write('CONFIG_TARGET_OPTIMIZATION="-O2 -pipe -mcpu=generic"\n')
        self.fullcone_fixture(tree)
        with patch.object(build, "run"):
            build.prepare_fullcone(tree)
        self.integration_fixture(tree)
        build.prepare_integrations(tree)

    def test_fullcone_patch_tampering_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            tree = Path(temp)
            self.make_config(tree)
            (tree / "target/linux/generic/hack-6.12/982-r4s-bcm-fullcone.patch").write_text("changed\n")
            with self.assertRaisesRegex(SystemExit, "kernel.patch"):
                build.check_fullcone(tree)

    def test_fullcone_patches_have_valid_unified_diff_counts(self):
        for path in build.fullcone_patches().values():
            build.run("git", "apply", "--numstat", str(path), capture=True)

    def test_fullcone_default_validation_rejects_enabling_either_family(self):
        stock = "config defaults\n\toption fullcone4 0\n\toption fullcone6 0\n"
        build.check_fullcone_defaults(stock)
        for option in ("fullcone4", "fullcone6"):
            with self.subTest(option=option), self.assertRaisesRegex(SystemExit, option):
                build.check_fullcone_defaults(stock.replace(f"{option} 0", f"{option} 1"))

    def test_fullcone_prepared_sources_are_checked(self):
        with tempfile.TemporaryDirectory() as temp:
            tree = Path(temp)
            self.make_config(tree)
            kernel = tree / "build_dir/target-aarch64/linux-rockchip_armv8/linux-6.12.112/net/netfilter/nf_nat_masquerade.c"
            kernel.parent.mkdir(parents=True)
            kernel.write_text("void nf_nat_fullcone_helpers_register(void) {}\n")
            root = tree / "build_dir/target-aarch64/firewall4-2026/root"
            fw4 = root / "usr/share/ucode/fw4.uc"
            fw4.parent.mkdir(parents=True)
            fw4.write_text("function nft_try_brcmfullcone() {}\n")
            config = root / "etc/config/firewall"
            config.parent.mkdir(parents=True)
            config.write_text("option fullcone4 0\noption fullcone6 0\n")
            pcie = kernel.parents[2] / "drivers/phy/rockchip/phy-rockchip-pcie.c"
            pcie.parent.mkdir(parents=True)
            pcie.write_text("rockchip_pcie_phy_reset(rk_phy);\n")
            cli = root / "sbin/fw4"
            cli.parent.mkdir(parents=True)
            cli.write_text("stock fw4\n")
            template = root / "usr/share/firewall4/templates/ruleset.uc"
            template.parent.mkdir(parents=True)
            template.write_text("flowtable ft {}\nflow offload @ft;\n")
            sqm = tree / "build_dir/target-aarch64/sqm-scripts-2026/platform/openwrt/sqm-init"
            sqm.parent.mkdir(parents=True)
            sqm.write_text("stock sqm init\n")
            build.check_prepared(tree)
            fw4.write_text("stock fw4\n")
            with self.assertRaisesRegex(SystemExit, "Prepared firewall4"):
                build.check_prepared(tree)

    def test_fullcone_abi_must_not_match_official_release(self):
        with tempfile.TemporaryDirectory() as temp:
            tree = Path(temp)
            self.make_config(tree)
            (tree / "target/linux/rockchip/Makefile").write_text("KERNEL_PATCHVER:=6.12\n")
            with self.assertRaisesRegex(SystemExit, "ABI isolation"):
                build.check_fullcone(tree)

    def test_fullcone_luci_accepts_upstream_single_quotes(self):
        with tempfile.TemporaryDirectory() as temp:
            tree = Path(temp)
            self.make_config(tree)
            ui = tree / "feeds/luci/applications/luci-app-firewall/htdocs/luci-static/resources/view/firewall/zones.js"
            ui.write_text("var option = 'fullcone4';\n")
            build.check_fullcone(tree)

    def test_fullcone_defaults_are_off_in_pinned_patch(self):
        source = build.fullcone_patches()["firewall4.patch"].read_text()
        self.assertIn("+\toption fullcone4\t0\n", source)
        self.assertIn("+\toption fullcone6\t0\n", source)
        self.assertNotIn("+\toption fullcone4\t1\n", source)

    def test_fullcone_luci_patch_does_not_enable_on_read(self):
        source = build.fullcone_patches()["luci.patch"].read_text()
        reader = source.split("o.cfgvalue = function(section_id)", 1)[1].split("o.write =", 1)[0]
        self.assertNotIn("uci.set", reader)
        self.assertIn("=== '1'", reader)

    def test_collect_includes_matching_modules_and_only_public_key(self):
        with tempfile.TemporaryDirectory() as temp:
            tree = Path(temp) / "tree"
            tree.mkdir()
            self.make_config(tree)
            target = tree / "bin/targets/rockchip/armv8"
            target.mkdir(parents=True)
            (target / "openwrt-friendlyarm_nanopi-r4s-squashfs-sysupgrade.img.gz").touch()
            manifest = "\n".join(f"{name} - 1-r1" for name in build.REQUIRED)
            manifest += f"\nkernel - 6.12.112~test-r{build.LOCK['fullcone']['kernel_release']}\n"
            (target / "openwrt-friendlyarm_nanopi-r4s.manifest").write_text(manifest)
            for name in ("sources.lock.buildinfo", "feeds.revisions.buildinfo", "config.seed.buildinfo"):
                (tree / name).write_text("test fixture\n")
            (tree / "public-key.pem").write_text("public fixture\n")
            (tree / "private-key.pem").write_text("private fixture\n")
            output = Path(temp) / "output"
            with patch.object(build, "verify_image"), patch.object(build, "run") as commands:
                build.collect(tree, output)
            tar = next(call.args for call in commands.call_args_list if call.args[0] == "tar")
            self.assertIn("targets/rockchip/armv8/packages", tar)
            self.assertTrue((output / "public-key.pem").exists())
            self.assertFalse((output / "private-key.pem").exists())

    def test_required_configuration_passes(self):
        with tempfile.TemporaryDirectory() as temp:
            tree = Path(temp)
            self.make_config(tree)
            build.check_config(tree)

    def test_additional_patches_are_valid_diffs(self):
        for path in (build.HERE / "patches").glob("*.patch"):
            build.run("git", "apply", "--numstat", str(path), capture=True)

    def test_integration_does_not_rewrite_passwall_routing(self):
        with tempfile.TemporaryDirectory() as temp:
            tree = Path(temp)
            self.integration_fixture(tree)
            pw_path = tree / "package/r4s-extras/passwall/luci-app-passwall/root/usr/share/passwall/nftables.sh"
            original = pw_path.read_bytes()
            build.prepare_integrations(tree)
            self.assertEqual(pw_path.read_bytes(), original)
            self.assertFalse((tree / "package/r4s-accel").exists())
            self.assertFalse((tree / "package/network/config/firewall4/patches/998-r4s-lifecycle.patch").exists())
            self.assertFalse((tree / "feeds/packages/net/sqm-scripts/patches/950-r4s-lifecycle.patch").exists())
            self.assertIn("ext_allow_private_ipv4 0", (tree / "feeds/packages/net/miniupnpd/files/miniupnpd.init").read_text())

    def test_native_forwarding_contract_rejects_retired_hooks(self):
        stock = ["stock fw4", "flowtable ft {}\nflow offload @ft;", "stock PassWall", "stock SQM"]
        build.check_native_forwarding(*stock)
        for index in (0, 2, 3):
            source = stock.copy()
            source[index] += "\n# r4s-accel lifecycle v1"
            with self.subTest(index=index), self.assertRaisesRegex(SystemExit, "Retired"):
                build.check_native_forwarding(*source)
        with self.assertRaisesRegex(SystemExit, "Native firewall4"):
            build.check_native_forwarding("stock", "no flowtable", "stock", "stock")

    def test_retired_package_selection_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            tree = Path(temp)
            self.make_config(tree)
            with (tree / ".config").open("a") as config:
                config.write("CONFIG_PACKAGE_r4s-accel=y\n")
            with self.assertRaisesRegex(SystemExit, "forbidden"):
                build.check_config(tree)

    def test_stale_integration_files_are_rejected(self):
        for relative in ("package/r4s-accel",
                         "package/network/config/firewall4/patches/998-r4s-lifecycle.patch",
                         "feeds/packages/net/sqm-scripts/patches/950-r4s-lifecycle.patch"):
            with self.subTest(relative=relative), tempfile.TemporaryDirectory() as temp:
                tree = Path(temp)
                self.make_config(tree)
                stale = tree / relative
                stale.parent.mkdir(parents=True, exist_ok=True)
                stale.touch()
                with self.assertRaisesRegex(SystemExit, "Retired"):
                    build.check_config(tree)

    def test_missing_theme_still_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            tree = Path(temp)
            self.make_config(tree)
            config = tree / ".config"
            config.write_text(config.read_text().replace("CONFIG_PACKAGE_luci-theme-argon=y\n", ""))
            with self.assertRaisesRegex(SystemExit, "luci-theme-argon"):
                build.check_config(tree)

    def test_overlay_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            tree = Path(temp)
            self.make_config(tree)
            (tree / "files").mkdir()
            with self.assertRaisesRegex(SystemExit, "personal configuration"):
                build.check_config(tree)


if __name__ == "__main__":
    unittest.main()
