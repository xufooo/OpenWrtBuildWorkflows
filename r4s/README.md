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
The first build does not
publish or configure an automatic third-party APK update server.

This workflow verifies package selection and image manifest. A successful
build is not a claim of hardware boot validation or increased performance.

## Additional integrations

- Add anaelorlinski's PCIe PHY reset-on-probe fix, preserving the upstream lane
  power-on fix. This targets warm-reboot initialization, not faster Ethernet.
- Expose miniupnpd 2.3.9's existing ext_allow_private_ipv4 option in UCI/LuCI,
  default off. Keep the official core, secure_mode and inbound policy.
- Add the source-packaged r4s-accel controller and LuCI Network page. It uses
  native nftables flowtables, with no fw4 template replacement, SFE or NATFlow.
  It starts disabled, with an empty host list and no imported device settings.

## Selective admission contract

Select individual, stable IPv4 LAN host addresses on the acceleration page.
When PassWall is enabled, these must also be individual IP sources in enabled
PassWall No Proxy ACLs, with ACL processing enabled. This first implementation
rejects mixed proxy/no-proxy ACLs, wildcard, interface, MAC, range and set ACLs
rather than guessing their precedence. Ordinary default PassWall proxy rules
can coexist with those explicit no-proxy ACLs for other clients. If PassWall
is entirely disabled, the acceleration host allowlist alone is sufficient.
There is no automatic admission of all domestic/domain-classified traffic.

Leave the standard firewall software/hardware offload switches off: they are
the broad native admission path, not this controller's switch. The controller
refuses to add flows when they are enabled. Its separate forward base chain
runs at priority 10, after fw4's priority 0 filtering, and requires established,
assured, unmarked LAN/WAN traffic with an explicitly allowed original source.
DNAT and nonmatching interfaces are excluded. Logical, bridge member and lower
physical devices are collected using stock netifd/sysfs interfaces.

IPv6 stays on the normal path; it is not disabled. With IPv4 FullCone enabled,
UDP also stays on the normal path; only eligible TCP is accelerated. Any enabled
SQM queue, installed pbr/mwan3 configuration or unknown IPv4 policy-routing rule
disables admission. Additional forward base chains also disable it, rather than
offloading ahead of an unknown later filter. Existing SQM/IPv6/FullCone
mechanisms are not reimplemented.

Small lifecycle hooks suspend admission before fw4, PassWall nft and SQM rule
changes. They delete only the controller's own table and drain conntrack only
for previously admitted source hosts. This intentionally interrupts those
hosts' established connections during reload; it does not claim seamless TCP
migration. Failed suspension aborts the hooked mutation. Failed reconfiguration
leaves admission closed. Interface changes also rebuild admission. DNS-set
changes do not grant admission: eligible hosts must be outside proxy/domain
classification, so no duplicate DNS-set watcher or custom DNS stack is added.

Upgrading a hooked package to an unmodified upstream build requires rebuilding
the matching integration. Missing hook markers cause admission to remain off
on the next controller invocation; do not bypass this check. The ordinary proxy
and forwarding services do not depend on successful acceleration admission.
MosDNS and PassWall keep their upstream initial configuration: this build does
not enable a DNS takeover chain or introduce personal resolver settings.

Local tests exercise the real controller with mocked nft/netifd and the pure
policy planner. Separate isolated checks apply the patches to the exact pinned
fw4, SQM, PassWall, UPnP and Linux PCIe files. These are not a kernel flowtable,
live proxy, boot or performance acceptance test. CI only builds and checks the
firmware; no device experiments are added.
