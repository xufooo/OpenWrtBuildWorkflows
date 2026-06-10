#!/bin/bash
# Copyright (c) 2022-2023 Curious <https://www.curious.host>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/Curious-r/OpenWrtBuildWorkflows
#-------------------------------------------------------------------------------------------------------
#
# homeproxy upstream fixes for mt7620 builds
#
#   P1: ujail — add procd_add_jail_mount_rw "$HP_DIR/ruleset/"
#        so sing-box inside ujail can access local .srs rule set files.
#
#   P2: nft wrapper — REMOVED. This was a destructive patch that replaced
#        "fw4 reload" with a bare "nft -f -" wrapper. On stop, it injected
#        an empty inet fw4 table into the kernel, destroying ALL firewall
#        rules. The uci-defaults script already registers fw4_post.nft as
#        a firewall include — fw4 reload handles it natively.
#
#   P3: self-bypass — insert an nft rule to let root-owned outbound TCP
#        traffic skip the redirect. This fixes the LuCI network detection
#        (wget --spider) which would otherwise be hijacked by homeproxy's
#        redirect_tproxy rules and fail if sing-box is misconfigured.

set -euo pipefail
echo "=== script-2: homeproxy patching ==="

# Fix: remove smpackage miniupnpd-iptables to avoid conflict with official
# miniupnpd nftables variant.
rm -rf feeds/smpackage/miniupnpd-iptables package/feeds/smpackage/miniupnpd-iptables

INIT_PATH="feeds/smpackage/luci-app-homeproxy/root/etc/init.d/homeproxy"

if [ ! -f "$INIT_PATH" ]; then
	echo "script-2: FATAL: homeproxy init not found at $INIT_PATH"
	exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
	echo "script-2: FATAL: python3 not found"
	exit 1
fi

python3 << 'PYEOF'
import sys

init_path = "feeds/smpackage/luci-app-homeproxy/root/etc/init.d/homeproxy"
with open(init_path, 'r', encoding='utf-8') as f:
    content = f.read()

# ===========================================================================
# P1: ujail ruleset mount (read-write)
# Insert after "procd_add_jail_mount \"$HP_DIR/certs/\"" in client ujail block
# ===========================================================================
old1 = '\t\t\tprocd_add_jail_mount "$HP_DIR/certs/"'
new1 = old1 + '\n\t\t\tprocd_add_jail_mount_rw "$HP_DIR/ruleset/"'
if old1 not in content:
    print("P1 FAIL: certs mount anchor not found")
    sys.exit(1)
content = content.replace(old1, new1, 1)

if 'procd_add_jail_mount_rw "$HP_DIR/ruleset/"' not in content:
    print("P1 FAIL: ruleset mount not inserted")
    sys.exit(1)
print("P1 ujail ruleset mount: OK")

# ===========================================================================
# P3: self-bypass for root-owned outbound TCP traffic
# Insert before the final log line in start_service.
# ===========================================================================
old3 = '\tlog "sing-box $(sing-box version -n) started."'
new3 = '\t# Self-bypass: root outbound TCP skips redirect (LuCI network check, opkg etc.)\n\tnft insert rule inet fw4 homeproxy_output_redir meta skuid 0 counter return 2>/dev/null || true\n' + old3
if old3 not in content:
    print("P3 FAIL: log anchor not found")
    sys.exit(1)
content = content.replace(old3, new3, 1)

if 'skuid 0' not in content:
    print("P3 FAIL: self-bypass nft rule not inserted")
    sys.exit(1)
print("P3 self-bypass: OK")

with open(init_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("\nAll homeproxy patches applied and verified successfully")
PYEOF

# Syntax check
if sh -n "$INIT_PATH" 2>/dev/null; then
	echo "Syntax check: OK"
else
	echo "Syntax check: FAILED"
	exit 1
fi

echo "=== script-2: homeproxy patches done ==="
