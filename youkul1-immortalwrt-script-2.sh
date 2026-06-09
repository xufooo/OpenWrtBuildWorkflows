#!/bin/bash
# Copyright (c) 2022-2023 Curious <https://www.curious.host>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/Curious-r/OpenWrtBuildWorkflows
#-------------------------------------------------------------------------------------------------------
#
# homeproxy-singbox: patch homeproxy for SmartDNS integration
#   - Add dnsmasq_default_dns flag: skip default DNS injection when disabled
#   - Custom routing mode defaults to OFF (SmartDNS manages DNS upstream)

set -euo pipefail
echo "=== script-2: homeproxy SmartDNS integration patching ==="

# Fix: remove smpackage miniupnpd-iptables to avoid conflict with official miniupnpd nftables variant
rm -rf feeds/smpackage/miniupnpd-iptables package/feeds/smpackage/miniupnpd-iptables

# --- Verify Python3 ---
if ! command -v python3 >/dev/null 2>&1; then
	echo "script-2: FATAL: python3 not found"
	exit 1
fi

# =============================================================================
# Patch homeproxy init: respect dnsmasq_default_dns flag
# =============================================================================
INIT_PATH="feeds/smpackage/luci-app-homeproxy/root/etc/init.d/homeproxy"
LUCIC_PATH="feeds/smpackage/luci-app-homeproxy/htdocs/luci-static/resources/view/homeproxy/client.js"

if [ ! -f "$INIT_PATH" ]; then
	echo "script-2: FATAL: homeproxy init not found at $INIT_PATH"
	exit 1
fi
if [ ! -f "$LUCIC_PATH" ]; then
	echo "script-2: FATAL: homeproxy client.js not found at $LUCIC_PATH"
	exit 1
fi

python3 << 'PYEOF'
import sys

# =============================================================================
# Patch 1: homeproxy init — dnsmasq_default_dns flag
# =============================================================================
init_path = "feeds/smpackage/luci-app-homeproxy/root/etc/init.d/homeproxy"
with open(init_path, 'r', encoding='utf-8') as f:
    content = f.read()

old_block = '''\t# DNSMasq rules
\tlocal ipv6_support dns_port
\tconfig_get_bool ipv6_support "config" "ipv6_support" "0"
\tconfig_get dns_port "infra" "dns_port" "5333"
\tmkdir -p "$DNSMASQ_DIR"
\techo -e "conf-dir=$DNSMASQ_DIR" > "$DNSMASQ_DIR/../dnsmasq-homeproxy.conf"'''

new_block = '''\t# DNSMasq rules
\tlocal ipv6_support dns_port dnsmasq_default_dns
\tconfig_get_bool ipv6_support "config" "ipv6_support" "0"
\tconfig_get dns_port "infra" "dns_port" "5333"
\tconfig_get_bool dnsmasq_default_dns "config" "dnsmasq_default_dns" "1"
\tif [ "$dnsmasq_default_dns" = "1" ]; then
\tmkdir -p "$DNSMASQ_DIR"
\techo -e "conf-dir=$DNSMASQ_DIR" > "$DNSMASQ_DIR/../dnsmasq-homeproxy.conf"'''

if old_block not in content:
    print("FATAL: init DNSMasq rules block not found")
    sys.exit(1)
content = content.replace(old_block, new_block)

# Close the if block — find the last DNSMASQ_DIR usage before "Setup routing table"
old_line = '\t/etc/init.d/dnsmasq restart >"/dev/null" 2>&1\n\n\t# Setup routing table'
new_line = '\t/etc/init.d/dnsmasq restart >"/dev/null" 2>&1\n\tfi\n\n\t# Setup routing table'
if old_line not in content:
    # Try without the comment
    old_line = '\t/etc/init.d/dnsmasq restart >"/dev/null" 2>&1\n\n\t# Setup routing'
    new_line = '\t/etc/init.d/dnsmasq restart >"/dev/null" 2>&1\n\tfi\n\n\t# Setup routing'
if old_line not in content:
    print("FATAL: init dnsmasq restart -> routing table block not found")
    sys.exit(1)
content = content.replace(old_line, new_line)

with open(init_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("P1 init dnsmasq_default_dns: OK")

# =============================================================================
# Verify P1
# =============================================================================
with open(init_path, 'r', encoding='utf-8') as f:
    final = f.read()
for pattern in ['dnsmasq_default_dns', 'if [ "$dnsmasq_default_dns" = "1" ]', 'mkdir -p "$DNSMASQ_DIR"']:
    if pattern not in final:
        print(f"VERIFY FAIL P1: {pattern}")
        sys.exit(1)
print("VERIFY OK: P1 init")

# =============================================================================
# Patch 2: LuCI client.js — dnsmasq_default_dns flag (custom mode only, default OFF)
# =============================================================================
luci_path = "feeds/smpackage/luci-app-homeproxy/htdocs/luci-static/resources/view/homeproxy/client.js"
with open(luci_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Find the proxy_mode option and add dnsmasq_default_dns right after it in routing
old_anchor = '''o = s.taboption('routing', form.ListValue, 'proxy_mode', _('Proxy mode'));'''
if old_anchor not in content:
    print("FATAL: proxy_mode option not found in client.js")
    sys.exit(1)

# Insert after the proxy_mode block (find the end: o.rmempty = false;)
insert_anchor = '''o = s.taboption('routing', form.Flag, 'ipv6_support', _('IPv6 support'));'''
if insert_anchor not in content:
    print("FATAL: ipv6_support option not found in client.js")
    sys.exit(1)

new_flag = '''o = s.taboption('routing', form.Flag, 'dnsmasq_default_dns', _('Set default DNS'),
\t_('When enabled, homeproxy sets itself as the default DNS server in dnsmasq. Disable to let SmartDNS manage DNS routing instead.'));
o.depends('routing_mode', 'custom');
o.default = o.disabled;
o.rmempty = false;

\to = s.taboption('routing', form.Flag, 'ipv6_support', _('IPv6 support'));'''
content = content.replace(insert_anchor, new_flag)

with open(luci_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("P2 LuCI dnsmasq_default_dns: OK")

# =============================================================================
# Verify P2
# =============================================================================
with open(luci_path, 'r', encoding='utf-8') as f:
    final = f.read()
for pattern in ['dnsmasq_default_dns', "depends('routing_mode', 'custom')", 'o.default = o.disabled']:
    if pattern not in final:
        print(f"VERIFY FAIL P2: {pattern}")
        sys.exit(1)
print("VERIFY OK: P2 LuCI")

print("\nAll homeproxy patches applied and verified successfully")
PYEOF

echo "=== script-2: homeproxy patches done ==="
