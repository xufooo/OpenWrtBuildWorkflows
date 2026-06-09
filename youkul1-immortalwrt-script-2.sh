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
# Patch homeproxy init + LuCI for dnsmasq_default_dns flag
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
import sys, re

# =============================================================================
# Patch 1: homeproxy init — dnsmasq_default_dns flag
# =============================================================================
init_path = "feeds/smpackage/luci-app-homeproxy/root/etc/init.d/homeproxy"
with open(init_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Insert config_get after dns_port read, wrap mkdir+case in if block
# Anchor: the "# DNSMasq rules" comment line (any leading whitespace)
old_anchor = '# DNSMasq rules'
new_anchor = '''# DNSMasq rules
\t\tlocal dnsmasq_default_dns
\t\tconfig_get_bool dnsmasq_default_dns "config" "dnsmasq_default_dns" "1"
\t\tif [ "$dnsmasq_default_dns" = "1" ]; then'''

if old_anchor not in content:
    print("FATAL (P1): '# DNSMasq rules' comment not found")
    sys.exit(1)
content = content.replace(old_anchor, new_anchor, 1)

# Close the if block before "# Setup routing table"
old_anchor2 = '# Setup routing table'
new_anchor2 = '''\t\tfi
\n\t\t# Setup routing table'''
if old_anchor2 not in content:
    print("FATAL (P1): '# Setup routing table' comment not found")
    sys.exit(1)
content = content.replace(old_anchor2, new_anchor2, 1)

with open(init_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("P1 init dnsmasq_default_dns: OK")

# Verify P1
with open(init_path, 'r', encoding='utf-8') as f:
    final = f.read()
for pattern in ['dnsmasq_default_dns', 'if [ "$dnsmasq_default_dns" = "1" ]', 'Setup routing table']:
    if pattern not in final:
        print(f"VERIFY FAIL P1: {pattern}")
        sys.exit(1)
print("VERIFY OK: P1 init")

# =============================================================================
# Patch 2: LuCI client.js — dnsmasq_default_dns flag
# =============================================================================
luci_path = "feeds/smpackage/luci-app-homeproxy/htdocs/luci-static/resources/view/homeproxy/client.js"
with open(luci_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Insert before ipv6_support option
old_anchor3 = "o = s.taboption('routing', form.Flag, 'ipv6_support', _('IPv6 support'));"
if old_anchor3 not in content:
    print("FATAL (P2): ipv6_support option not found")
    sys.exit(1)

new_flag = """o = s.taboption('routing', form.Flag, 'dnsmasq_default_dns', _('Set default DNS'),
\t_('When enabled, homeproxy sets itself as the default DNS server in dnsmasq. Disable to let SmartDNS manage DNS routing instead.'));
o.depends('routing_mode', 'custom');
o.default = o.disabled;
o.rmempty = false;

\to = s.taboption('routing', form.Flag, 'ipv6_support', _('IPv6 support'));"""

content = content.replace(old_anchor3, new_flag, 1)

with open(luci_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("P2 LuCI dnsmasq_default_dns: OK")

# Verify P2
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
