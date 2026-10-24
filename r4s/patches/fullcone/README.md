# FullCone patch provenance

Source: https://github.com/QiuSimons/YAOF
Commit: 8f53c9e82281550477804102e2538486ef13838b (25.12 snapshot)
License: upstream repository GPL-3.0; retain each patch's author headers.
SHA256 values are fixed in ../../sources.lock.json.
The LuCI patch's terminal hunk counts are normalized to its retained context;
the inserted code is unchanged.

- kernel.patch: PATCH/kernel/bcmfullcone/982-add-bcm-fullconenat-support.patch
- firewall4.patch: PATCH/pkgs/firewall/firewall4_patches/999-01-firewall4-add-bcm-fullconenat-support.patch
- luci.patch: PATCH/pkgs/firewall/luci/0001-luci-app-firewall-add-brcm-fullcone-nat-option.patch

Only these patches are used. No firmware-author binaries, default-settings
scripts, credentials or existing router configuration are imported. Both
families start disabled. Package release 1001 separates this patched kernel's
packages from official ones; bump it if the kernel patch ABI changes.
