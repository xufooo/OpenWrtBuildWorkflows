#!/bin/bash
# Copyright (c) 2022-2023 Curious <https://www.curious.host>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/Curious-r/OpenWrtBuildWorkflows
#-------------------------------------------------------------------------------------------------------
#
# homeproxy patches for mt7620
#
#  P1  ujail: ruleset mount (rw) so sing-box can write .srs cache in jail
#  P3  self-bypass: root TCP skips redirect (LuCI network check / opkg)
#  P4  custom-mode template — DNS servers, rule sets, DNS rules, routing
#      rules, routing_node placeholder.  Switch to custom → already filled.

set -euo pipefail
echo "=== script-2: homeproxy ==="

rm -rf feeds/smpackage/miniupnpd-iptables package/feeds/smpackage/miniupnpd-iptables

INIT_PATH="feeds/smpackage/luci-app-homeproxy/root/etc/init.d/homeproxy"
CONF_PATH="feeds/smpackage/luci-app-homeproxy/root/etc/config/homeproxy"

for f in "$INIT_PATH" "$CONF_PATH"; do
	[ -f "$f" ] || { echo "FATAL: $f not found"; exit 1; }
done
command -v python3 >/dev/null 2>&1 || { echo "FATAL: python3 not found"; exit 1; }

# ==========================================================================
# P1 + P3 — init script (exact-anchor Python replacement)
# ==========================================================================
python3 << 'PYEOF'
import sys
path = "feeds/smpackage/luci-app-homeproxy/root/etc/init.d/homeproxy"
with open(path, 'r', encoding='utf-8') as f:
    c = f.read()

# P1
old1 = '\t\t\tprocd_add_jail_mount "$HP_DIR/certs/"'
assert old1 in c, "P1 anchor"; c = c.replace(old1, old1 + '\n\t\t\tprocd_add_jail_mount_rw "$HP_DIR/ruleset/"', 1)
assert 'procd_add_jail_mount_rw "$HP_DIR/ruleset/"' in c, "P1 insert"; print("P1 OK")

# P3
old3 = '\tlog "sing-box $(sing-box version -n) started."'
assert old3 in c, "P3 anchor"
c = c.replace(old3, '\t# Self-bypass: root TCP skips redirect (LuCI check, opkg etc.)\n\tnft insert rule inet fw4 homeproxy_output_redir meta skuid 0 counter return 2>/dev/null || true\n' + old3, 1)
assert 'skuid 0' in c, "P3 insert"; print("P3 OK")

with open(path, 'w', encoding='utf-8') as f:
    f.write(c)
PYEOF

sh -n "$INIT_PATH" 2>/dev/null || { echo "Init syntax FAILED"; exit 1; }
echo "Init: OK"

# ==========================================================================
# P4 — custom-mode template (idempotent)
# ==========================================================================
if grep -q 'HP_TEMPLATE' "$CONF_PATH" 2>/dev/null; then
	echo "P4 template: already present, skip"
else
	cat >> "$CONF_PATH" << 'CONFEOF'

#
# ═══════════════════════════════════════════════════════════════════════
#  Custom Routing Template
# ═══════════════════════════════════════════════════════════════════════
#
#  Quick start (3 steps):
#    1. Nodes tab         → add your proxy node(s)
#    2. Routing Nodes tab → enable "proxy-out", set node=your-node
#    3. Change 2 outbound fields below from "direct-out" to "proxy-out":
#         • remote-dns (DNS Servers tab)
#         • Default→Proxy (Routing Rules tab)
#       Then start the service.
#
#  Everything else is ready.  DNS servers, rule sets, DNS rules and
#  routing rules are pre-configured with safe direct-out fallbacks.
#
# HP_TEMPLATE — do not remove this line

# ── Routing Node (placeholder) ─────────────────────────────────────
#  Create this FIRST after adding a proxy node on the Nodes tab.
#  Set node=your-node, enabled=1, outbound empty (direct to server).
config routing_node 'proxy-out'
	option label 'Main Proxy'
	option enabled '0'
	option node 'urltest'
	option domain_resolver 'default-dns'
	option domain_strategy 'prefer_ipv4'

# ── DNS Servers ─────────────────────────────────────────────────────
#  local-dns: domestic DNS for China sites (UDP, direct)
config dns_server 'local-dns'
	option label 'Local DNS (CN)'
	option type 'udp'
	option server '223.5.5.5'
	option server_port '53'
	option outbound 'direct-out'
	option enabled '1'

#  backup-dns: Tencent DNS as China fallback
config dns_server 'backup-dns'
	option label 'Backup DNS (CN)'
	option type 'udp'
	option server '119.29.29.29'
	option server_port '53'
	option outbound 'direct-out'
	option enabled '1'

#  remote-dns: Cloudflare DoT for foreign domains (anti-pollution)
#  → change outbound to 'proxy-out' after creating the routing_node!
config dns_server 'remote-dns'
	option label 'Remote DNS (Proxy)'
	option type 'tcp'
	option server '1.1.1.1'
	option server_port '853'
	option tls_sni 'cloudflare-dns.com'
	option outbound 'direct-out'
	option address_resolver 'default-dns'
	option enabled '1'

# ── Rule Sets ───────────────────────────────────────────────────────
#  Remote binary .srs rule sets, auto-updated every 72h
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

config ruleset 'gfw'
	option label 'GFW List'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-gfw.srs'
	option update_interval '72h'
	option enabled '1'

# ── DNS Rules ───────────────────────────────────────────────────────
#  Matched top-to-bottom, first win.
#  Block SVCB/HTTPS queries to prevent Apple device fingerprinting
config dns_rule
	option label 'Block SVCB/HTTPS'
	option enabled '1'
	list query_type '64'
	list query_type '65'
	option action 'reject'

#  GFW-listed domains → remote DNS (anti-pollution for known blocked)
config dns_rule
	option label 'GFW -> Remote DNS'
	option enabled '1'
	list rule_set 'gfw'
	option action 'route'
	option server 'remote-dns'

#  CN domains → local DNS (fast domestic resolution)
config dns_rule
	option label 'CN -> Local DNS'
	option enabled '1'
	list rule_set 'cn-domain'
	option action 'route'
	option server 'local-dns'

#  Catch-all → remote DNS
config dns_rule
	option label 'Default -> Remote DNS'
	option enabled '1'
	option action 'route'
	option server 'remote-dns'

# ── Routing Rules ───────────────────────────────────────────────────
#  Matched top-to-bottom, first win.
#  CN IP ranges → direct (bypass proxy)
config routing_rule
	option label 'CN IP -> Direct'
	option enabled '1'
	list rule_set 'cn-ip'
	option action 'route'
	option outbound 'direct-out'

#  Catch-all → proxy
#  → change outbound to 'proxy-out' after creating the routing_node!
config routing_rule
	option label 'Default -> Proxy'
	option enabled '1'
	option action 'route'
	option outbound 'direct-out'
CONFEOF

	grep -q 'HP_TEMPLATE' "$CONF_PATH" && echo "P4 template: OK" || { echo "P4 FAIL"; exit 1; }
fi

echo "=== script-2: done ==="
