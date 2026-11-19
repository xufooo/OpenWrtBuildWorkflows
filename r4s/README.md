# R4S firmware build

OpenWrt 25.12.6, rockchip/armv8, NanoPi R4S squashfs image. The source commit
and extra package repositories are recorded in sources.lock.json; official
feeds use the exact revisions supplied by the OpenWrt release.

Includes PassWall (nftables), Xray, sing-box, MosDNS, Lucky, Argon, SQM,
nlbwmon, UPnP, WOL, ttyd, file manager and diagnostic tools. No Docker.
Applications keep their upstream initial configuration. No device backup,
credentials, subscriptions, IP/DNS/route overrides or files overlay is imported.
The public network-tuning defaults below are the only new runtime profile.

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
The upstream target checksum file is named `openwrt-sha256sums` in the archive;
`SHA256SUMS` covers all collected files. Their names remain distinct on
case-insensitive filesystems such as the default macOS filesystem.
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

- Backport the OpenWrt 25.12 branch's dnsmasq 2.93 fix for slow loading and
  reloading of large hosts files. This does not change MosDNS configuration.
- Apply the official October and November uhttpd package updates. These
  improve request handling and stop one source monopolizing LuCI script slots.
  Exact package commits are listed separately from the base release in
  `sources.lock.json`; no application defaults are imported.

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

## R4S network tuning candidate

This candidate keeps OpenWrt 25.12.6, the same kernel, drivers and official SQM
package. It does not change CAKE parameters, select a new QoS engine, enable
SQM or flow offloading, or embed bandwidth limits. It is not a verified fix for
WAN throughput loss. No router operations or speed tests run from this workflow.

The separate `r4s-net-tune` package is restricted to R4S board identities;
feature/ring changes target physical ports eth0/eth1 only. Packet steering
follows the native global LuCI policy. It references YAOF revision c7540bb and the public
OpenWrt-Add tuning scripts at aefd16b; it does not install the author's broad
default-settings package. Reference commits and installed-file hashes are
recorded in `network-tuning.buildinfo`.

- Prefer native all-CPU packet steering and 128 flow entries in the initial
  profile. An explicitly disabled steering setting is respected. Subsequent
  LuCI changes remain authoritative. With r4s_net_tune.main.affinity=upstream
  no fixed IRQ or RPS mask is installed; with affinity=starwhiz the published
  R4S recipe below owns both masks.
  This public-default migration runs once, is recorded in the package's UCI
  config, and defers rather than committing pre-existing pending UCI changes.
  When flow steering is configured, also size its global RFS socket table to
  cover the physical RX queues. Per-queue entries alone do not activate RFS
  while `rps_sock_flow_entries` is zero. This table is bounded and reversible;
  disabling steering/flow entries also relinquishes this package's RFS table.
- Reapply the native configured steering after relevant network events,
  using a quiet interval rather than rewriting upstream scripts. SQM changes
  and IFB creation/removal do not independently trigger physical NIC tuning.
- Default to the published StarWhiz R4S split (NanoPi-R6S-CPU-Optimization
  for Gigabit SQM, R4S directory): NIC interrupts stay on the A53 cluster
  (eth0 mask 4, eth1 mask 8) and each interface's RPS delivery targets one
  A72 (eth0 0x10, eth1 0x20), so the NAPI poll and the network stack run on
  different cores. packet_steering is set to 0 because it rewrites rps_cpus
  on every network/firewall event and would undo the masks. Set
  r4s_net_tune.main.affinity=upstream to restore the OpenWrt 25.12 layout
  (IRQ 0x10/0x20 plus packet steering); the previous masks are restored when
  the service stops.
- Keep the kernel socket-buffer ceilings and netdev_max_backlog at their
  upstream defaults, matching OpenWrt and YAOF. The older 64 MB ceilings and
  16384 backlog are opt-in via r4s_net_tune.main.buffers; they are not memory
  reservations and are not evidence of improved throughput.
- Apply supported RX-checksum/GRO settings, respecting explicit device GRO
  configuration. Unsupported/fixed features are not forced.
- Ring resizing is limited to early boot while the physical interface is down.
  No live ring resize, adaptive-coalescing change or network restart is used.

The service records only a small allowlist of original numeric/feature values
under its root-only runtime directory and restores its runtime changes on stop.
Ring restoration is not attempted on a live interface; an early-boot ring
change may require a reboot to return to the driver's defaults. Native UCI
steering settings remain visible and are not secretly reverted by the service.
Live package installation/upgrade does not automatically start the tuning
service; start it explicitly or reboot after reviewing the profile.

Excluded from this profile: CPU overclock/governor changes, mitigation changes,
proxy ARP, DNS, IPv6, ZRAM, author-specific proxy rules and unproven CAKE/IFB
kernel patches. FriendlyWrt's 6.6 kernel is a comparison source, not a kernel
downgrade in this build. Final boot, throughput and loaded-latency acceptance
remain separate from source checks and successful compilation.
