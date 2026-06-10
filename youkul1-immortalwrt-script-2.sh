#!/bin/bash
# Copyright (c) 2022-2023 Curious <https://www.curious.host>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/Curious-r/OpenWrtBuildWorkflows
#-------------------------------------------------------------------------------------------------------
#
# homeproxy: fix 2 upstream bugs for ujail + fw4 integration
#   P1: ujail — add procd_add_jail_mount "$HP_DIR/ruleset/" so sing-box can see .srs files
#   P2: nft wrapper — fw4 reload doesn't look at /var/run/homeproxy/fw4_post.nft;
#       replace with (echo "table inet fw4 {"; cat fw4_post.nft; echo "}") | nft -f -

set -euo pipefail
echo "=== script-2: homeproxy patching ==="

# Fix: remove smpackage miniupnpd-iptables to avoid conflict with official miniupnpd nftables variant
rm -rf feeds/smpackage/miniupnpd-iptables package/feeds/smpackage/miniupnpd-iptables

INIT_PATH="feeds/smpackage/luci-app-homeproxy/root/etc/init.d/homeproxy"

if [ ! -f "$INIT_PATH" ]; then
	echo "script-2: FATAL: homeproxy init not found at $INIT_PATH"
	exit 1
fi

# ---------------------------------------------------------------------------
# P1: ujail ruleset mount
# Anchor: "procd_add_jail_mount \"\$HP_DIR/certs/\"" — insert ruleset/ after it
# ---------------------------------------------------------------------------
sed -i '/procd_add_jail_mount "$HP_DIR\/certs\/"/a\\t\t\tprocd_add_jail_mount "$HP_DIR\/ruleset\/"' "$INIT_PATH"
grep -q 'ruleset' "$INIT_PATH" && echo "P1 ujail ruleset mount: OK" || { echo "P1 FAIL"; exit 1; }

# ---------------------------------------------------------------------------
# P2: nft wrapper (start_service + stop_service)
# Replace "fw4 reload >"/dev/null" 2>&1" with the nft wrapper
# ---------------------------------------------------------------------------
sed -i 's|fw4 reload >"/dev/null" 2>&1|(echo "table inet fw4 {"; cat "$RUN_DIR/fw4_post.nft"; echo "}") | nft -f - 2>/dev/null|g' "$INIT_PATH"

# Verify P2 — there should be 2 occurrences of the nft wrapper (start + stop)
count=$(grep -c 'nft -f - 2>/dev/null' "$INIT_PATH" || true)
if [ "$count" -eq 2 ]; then
	echo "P2 nft wrapper: OK (${count}x)"
else
	echo "P2 FAIL: expected 2 nft wrappers, found ${count}"
	exit 1
fi

# ---------------------------------------------------------------------------
# Final syntax check
# ---------------------------------------------------------------------------
INIT_BAK=$(mktemp)
cp "$INIT_PATH" "$INIT_BAK"
# Basic shell syntax check: run sh -n on a copy
if sh -n "$INIT_BAK" 2>/dev/null; then
	echo "Syntax check: OK"
else
	echo "Syntax check: FAILED"
	rm -f "$INIT_BAK"
	exit 1
fi
rm -f "$INIT_BAK"

echo "=== script-2: homeproxy patches done ==="
