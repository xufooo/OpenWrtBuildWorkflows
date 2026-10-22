# R4S first build

OpenWrt 25.12.6, rockchip/armv8, NanoPi R4S squashfs image. The source commit
and extra package repositories are recorded in sources.lock.json; official
feeds use the exact revisions supplied by the OpenWrt release.

Includes PassWall (nftables), Xray, sing-box, MosDNS, Lucky, Argon, SQM,
nlbwmon, UPnP, WOL, ttyd, file manager and diagnostic tools. No Docker.
All applications keep their upstream initial configuration. No device backup,
credentials, subscriptions, network overrides or files overlay is imported.

Uses stock OpenWrt kernel, clock and driver configuration. No vermagic
override, custom kernel, CPU overclock or performance benchmark is included.

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
Kernel modules must match the firmware kernel ABI. The first build does not
publish or configure an automatic third-party APK update server.

This workflow verifies package selection and image manifest. A successful
build is not a claim of hardware boot validation or increased performance.
