# R4S first build

OpenWrt 25.12.6, rockchip/armv8, NanoPi R4S squashfs image. The source commit
and extra package repositories are recorded in sources.lock.json; official
feeds use the exact revisions supplied by the OpenWrt release.

Includes PassWall (nftables), Xray, sing-box, MosDNS, Lucky, Argon, SQM,
nlbwmon, UPnP, WOL, ttyd, file manager and diagnostic tools. No Docker.
All applications keep their upstream initial configuration. No device backup,
credentials, subscriptions, network overrides or files overlay is imported.

Adds the public YAOF BCM FullCone kernel/fw4/LuCI patches, pinned to commit
8f53c9e82281550477804102e2538486ef13838b with local SHA256 checks. FullCone
IPv4 and IPv6 are both disabled initially; the Firewall page provides the
switch. Enabling IPv4 does not enable NAT6. No YAOF default-settings package,
personal configuration, CPU overclock or vermagic override is imported.

This is now a patched kernel. Its package release is 1001, distinct from the
official release, so official kmods cannot silently replace the matching ones.
Use modules from the same build archive; do not force-install official kmods.
Clock and network driver selections remain upstream defaults.

FullCone permits unsolicited UDP traffic to existing mapped endpoints. Review
service listening addresses and inbound policy before enabling it. Patch and
image checks are not a live NAT or security certification.

Extra applications use their publicly maintained OpenWrt package definitions:
PassWall's feeds, sbwml's MosDNS/LuCI feed, Lucky's official feed and Argon.
Lucky's upstream recipe uses its author's official release binary. MosDNS
uses its feed's normal public patch set, not a private firmware binary.

Pushes to r4s-build start GitHub Actions. Later runs may be
started manually. Builds do not cancel other running builds.

Artifacts include firmware, checksums, package manifest, full build config,
source/feed revisions and APK packages/indexes. Private signing keys are not
uploaded. Official device package repository configuration is retained.
Additional apps are independently packaged, not copied as unmanaged binaries.
They can be updated using compatible upstream APK releases or a new build;
this does not promise the official OpenWrt server hosts third-party packages.
The archive includes target-specific module packages and indexes, and the APK
public key (never the private key). Kernel modules must match the firmware
kernel package release and ABI. The first build does not
publish or configure an automatic third-party APK update server.

This workflow verifies package selection and image manifest. A successful
build is not a claim of hardware boot validation or increased performance.
