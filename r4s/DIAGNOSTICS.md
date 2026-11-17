# R4S Profiling Build

This branch is a diagnostic sibling of the deployed `r4s-build` firmware,
not a throughput fix or a replacement production release.

## Difference From The Baseline

- The same pinned OpenWrt, feeds, kernel version, drivers, networking patches,
  application sources, and initial network settings are retained.
- `CONFIG_KERNEL_PERF_EVENTS=y` selects the native ARM PMU and ARM PMUv3
  support. The official `perf` package is compiled from this same kernel tree.
- Kernel package release 1003 separates these diagnostic modules from the
  production release 1002. Do not mix kernel modules between the two images.
- The artifact includes the actual kernel configuration, matching AArch64
  `vmlinux`, checksums, and an explicit profiling-purpose build record.
- Image collection fails if profiling options, the matching kernel ELF,
  or the executable perf tool are absent.

No extra SQM algorithm, offloading hook, CPU governor, affinity override,
overclock, network configuration, or automatic profiler is introduced.
The existing network tuning package is unchanged from the baseline.

## Validation Boundary

Local tests and CI image checks establish source and artifact consistency,
not live profiling support or network performance. A separate authorized
deployment and runtime event test are still required. No flashing, router
login, private configuration, backup, or performance recording occurs in CI.

If deployed later with explicit permission, sampling must be bounded and
keep private recordings outside this repository. Software-offload state
and proxy services must be preserved, with tested timeout recovery for
temporary SQM changes. Collect function samples together with transfer,
CPU, queue, and TCP evidence; do not present a different benchmark path as
a firmware repair.
