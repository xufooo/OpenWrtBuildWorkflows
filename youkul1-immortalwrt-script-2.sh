#!/bin/bash
# Copyright (c) 2022-2023 Curious <https://www.curious.host>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/Curious-r/OpenWrtBuildWorkflows
#-------------------------------------------------------------------------------------------------------
#
# homeproxy patches for mt7620 builds:
#
#   P1  ujail ruleset mount (rw)
#   P3  self-bypass for root TCP
#   P4  custom-mode scaffolding — DNS servers, rule sets, DNS rules,
#       routing rules.  Switch to custom, create a routing_node
#       "proxy-out", change 2 outbound fields, start.

set -euo pipefail
echo "=== script-2: homeproxy patching ==="

# Remove smpackage miniupnpd-iptables (conflicts with official nftables variant)
rm -rf feeds/smpackage/miniupnpd-iptables package/feeds/smpackage/miniupnpd-iptables

INIT_PATH="feeds/smpackage/luci-app-homeproxy/root/etc/init.d/homeproxy"
CONF_PATH="feeds/smpackage/luci-app-homeproxy/root/etc/config/homeproxy"

for f in "$INIT_PATH" "$CONF_PATH"; do
	if [ ! -f "$f" ]; then
		echo "script-2: FATAL: $f not found"
		exit 1
	fi
done
command -v python3 >/dev/null 2>&1 || { echo "script-2: FATAL: python3 not found"; exit 1; }

# ===========================================================================
# P1 + P3: init script patches (Python exact-anchor)
# ===========================================================================
python3 << 'PYEOF'
import sys

init_path = "feeds/smpackage/luci-app-homeproxy/root/etc/init.d/homeproxy"
with open(init_path, 'r', encoding='utf-8') as f:
    content = f.read()

# P1: ujail ruleset mount (rw)
old1 = '\t\t\tprocd_add_jail_mount "$HP_DIR/certs/"'
new1 = old1 + '\n\t\t\tprocd_add_jail_mount_rw "$HP_DIR/ruleset/"'
if old1 not in content:
    print("P1 FAIL: anchor not found"); sys.exit(1)
content = content.replace(old1, new1, 1)
assert 'procd_add_jail_mount_rw "$HP_DIR/ruleset/"' in content, "P1 FAIL"
print("P1 ujail ruleset: OK")

# P3: self-bypass for root outbound TCP
old3 = '\tlog "sing-box $(sing-box version -n) started."'
new3 = '\t# Self-bypass: root outbound TCP skips redirect (LuCI check, opkg etc.)\n\tnft insert rule inet fw4 homeproxy_output_redir meta skuid 0 counter return 2>/dev/null || true\n' + old3
if old3 not in content:
    print("P3 FAIL: anchor not found"); sys.exit(1)
content = content.replace(old3, new3, 1)
assert 'skuid 0' in content, "P3 FAIL"
print("P3 self-bypass: OK")

with open(init_path, 'w', encoding='utf-8') as f:
    f.write(content)
PYEOF

sh -n "$INIT_PATH" 2>/dev/null || { echo "Init syntax FAILED"; exit 1; }
echo "Init syntax: OK"

# ===========================================================================
# P4: custom-mode scaffolding (append to default config)
# ===========================================================================
if grep -q 'HP_TEMPLATE' "$CONF_PATH" 2>/dev/null; then
	echo "P4 scaffolding: already present, skipping"
else
	cat >> "$CONF_PATH" << 'CONFEOF'

#
# ── Custom routing mode scaffolding ──────────────────────────────────
#   Quick start: switch routing_mode to "custom", then:
#   1. Add a proxy node on the Nodes tab
#   2. Create a routing_node "proxy-out" (Routing Nodes tab)
#      referencing your node.  Set its outbound to empty.
#   3. Change 2 fields from "direct-out" → "proxy-out":
#        • Remote DNS server:  outbound
#        • Route rule "Default → Proxy":  outbound
#      (or set routing.default_outbound in Routing Settings tab)
#   4. Start the service
#
#   Already provisioned: DNS servers (local/remote), rule sets
#   (CN domains / CN IPs), DNS rules (CN→local, *→remote),
#   routing rules (CN IP→direct, *→direct-out).
# ─────────────────────────────────────────────────────────────────────
# HP_TEMPLATE — do not remove

# ── DNS servers ──────────────────────────────────────────────────────
config dns_server 'local-dns'
	option label 'Local DNS (CN)'
	option type 'udp'
	option server '223.5.5.5'
	option server_port '53'
	option outbound 'direct-out'
	option enabled '1'

config dns_server 'remote-dns'
	option label 'Remote DNS (Proxy)'
	option type 'tcp'
	option server '1.1.1.1'
	option server_port '853'
	option tls_sni 'cloudflare-dns.com'
	option outbound 'direct-out'
	option address_resolver 'default-dns'
	option enabled '1'

# ── Rule sets ────────────────────────────────────────────────────────
config ruleset 'cn-domain'
	option label 'CN Domains'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set-unstable/geosite-geolocation-cn.srs'
	option update_interval '72h'
	option enabled '1'

config ruleset 'cn-ip'
	option label 'CN IPs'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/IPCIDR-CHINA@rule-set/cn.srs'
	option update_interval '72h'
	option enabled '1'

# ── DNS rules ────────────────────────────────────────────────────────
config dns_rule
	option label 'CN -> Local DNS'
	option enabled '1'
	list rule_set 'cn-domain'
	option action 'route'
	option server 'local-dns'

config dns_rule
	option label 'Default -> Remote DNS'
	option enabled '1'
	option action 'route'
	option server 'remote-dns'

# ── Routing rules ────────────────────────────────────────────────────
config routing_rule
	option label 'CN IP -> Direct'
	option enabled '1'
	list rule_set 'cn-ip'
	option action 'route'
	option outbound 'direct-out'

config routing_rule
	option label 'Default -> Proxy'
	option enabled '1'
	option action 'route'
	option outbound 'direct-out'
CONFEOF

	grep -q 'HP_TEMPLATE' "$CONF_PATH" && echo "P4 scaffolding: OK" || { echo "P4 FAIL"; exit 1; }
fi

echo "=== script-2: done ==="
