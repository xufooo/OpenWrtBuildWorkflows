"""Offline regression checks for source preparation and package selection."""

import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("r4s_build", Path(__file__).with_name("build.py"))
build = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build)


class BuildTests(unittest.TestCase):
    def test_prepare_preserves_package_names_and_sources(self):
        with tempfile.TemporaryDirectory() as temp:
            tree = Path(temp) / "openwrt"

            def checkout(spec, destination):
                destination.mkdir(parents=True)
                if spec is build.LOCK["openwrt"]:
                    (destination / "feeds.conf.default").write_text("")
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

    def make_config(self, tree):
        options = [f"CONFIG_PACKAGE_{name}=y" for name in build.REQUIRED]
        options += ["CONFIG_" + name + "=y" for name in (
            "TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r4s",
            "TARGET_ROOTFS_SQUASHFS", "PACKAGE_luci-app-passwall_Nftables_Transparent_Proxy",
            "SING_BOX_BUILD_UTLS", "SING_BOX_BUILD_QUIC", "SING_BOX_BUILD_GRPC",
        )]
        (tree / ".config").write_text("\n".join(options) + "\n")

    def test_required_configuration_passes(self):
        with tempfile.TemporaryDirectory() as temp:
            tree = Path(temp)
            self.make_config(tree)
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
