# R4S firmware build

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

This is now a patched kernel. Its package release is 1002, distinct from the
official release, so official kmods cannot silently replace the matching ones.
Use modules from the same build archive; do not force-install official kmods.
Clock and network driver selections remain upstream defaults. User-space C/C++
packages use -O2 instead of -Os, retaining the generic AArch64 CPU selection;
this does not change Go optimization, kernel flags or promise a throughput gain.

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
kernel package release and ABI (now release 1002, changed with the PCIe patch).
The build does not publish or configure an automatic third-party APK update
server.

This workflow verifies package selection and image manifest. A successful
build is not a claim of hardware boot validation or increased performance.

## Additional integrations

- Add anaelorlinski's PCIe PHY reset-on-probe fix, preserving the upstream lane
  power-on fix. This targets warm-reboot initialization, not faster Ethernet.
- Expose miniupnpd 2.3.9's existing ext_allow_private_ipv4 option in UCI/LuCI,
  default off. Keep the official core, secure_mode and inbound policy.

## Native software flow offloading

Use the upstream Firewall page's software flow offloading option. The retired
r4s-accel package, device allowlist page and its fw4/PassWall/SQM lifecycle hooks
are removed. No replacement forwarding chain, automatic China-IP classifier,
SFE, NATFlow or conntrack-flushing service is added. PassWall and SQM source
scripts remain unmodified by this build.

The image keeps upstream initial offloading settings; it does not enable
software or hardware offloading automatically. FullCone remains a separate,
initially disabled option. Hardware flow offloading requires supported hardware
and drivers; a visible switch alone is not evidence of support.

Native software offloading operates on eligible forwarded connections. Traffic
redirected to a local proxy and a user's request to use a proxy core's direct
outbound are not equivalent to ordinary kernel forwarding. The build does not
claim to accelerate all traffic classified as domestic, or speed up encryption
and remote proxy nodes. Software offloading and SQM are not unconditionally
exclusive; interface placement, shaping and classification still matter.

Flowtables cache existing connection paths. A policy change is not a guarantee
that every established connection is immediately reclassified. This revision
does not add policy-change experiments, force-close connections or promise
seamless migration. Keep runtime settings and any backup migration separate
from this clean firmware build; do not restore the retired controller's files.

Local regressions check package selection, absence of retired files/hooks and
preservation of native forwarding templates. Isolated checks use exact pinned
fw4, SQM, PassWall, UPnP and Linux PCIe sources. CI verifies prepared sources,
the final SquashFS contents and package manifest, then publishes the firmware.
These build checks are not a device boot or performance certification; CI does
not perform router experiments or import private device test records.
