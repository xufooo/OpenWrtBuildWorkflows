#!/bin/bash
# Copyright (c) 2022-2023 Curious <https://www.curious.host>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/Curious-r/OpenWrtBuildWorkflows
#-------------------------------------------------------------------------------------------------------
#
# Remove smpackage miniupnpd-iptables to avoid conflict with official
# miniupnpd nftables variant.

set -euo pipefail
echo "=== script-2 ==="

rm -rf feeds/smpackage/miniupnpd-iptables package/feeds/smpackage/miniupnpd-iptables

echo "=== done ==="
