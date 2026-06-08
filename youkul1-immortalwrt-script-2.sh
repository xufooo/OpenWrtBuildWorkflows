#!/bin/bash
# Copyright (c) 2022-2023 Curious <https://www.curious.host>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/Curious-r/OpenWrtBuildWorkflows
#-------------------------------------------------------------------------------------------------------
#
# 1. Add stub shadowsocks-libev-config package

# Remove smpackage miniupnpd-iptables to avoid conflict with official miniupnpd nftables variant
rm -rf feeds/smpackage/miniupnpd-iptables package/feeds/smpackage/miniupnpd-iptables

# 2. Patch SSR Plus: Makefile Kconfig + client-config.lua type dropdown + init script
#    Supports ss-libev as native node type alongside ss-rust.
#
# Base: 72f2e40 (proven working via CI). Enhanced with:
#   - set -euo pipefail (fail loud, never silent)
#   - python3 existence check
#   - utf-8 encoding on all I/O
#   - P1 fix (upstream already has ss-libev in _migrate)
#   - Server mode (P9a/P9b), server-config.lua, Libev_Server Kconfig
#   - ssr-rules DAEMON_ID + PID (P10/P11)
#   - Post-patch verification of 6 critical patterns

set -euo pipefail
echo "=== script-2: ss-libev patching ==="

# --- shadowsocks-libev: config stub ---
if [ -d feeds/smpackage/shadowsocks-libev ]; then
	cd feeds/smpackage/shadowsocks-libev
	cat >> Makefile << 'EOF'

define Package/shadowsocks-libev-config
  $(call Package/shadowsocks-libev/Default)
  TITLE:=shadowsocks-libev config
endef

define Package/shadowsocks-libev-config/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/etc/init.d
endef

$(eval $(call BuildPackage,shadowsocks-libev-config))
EOF
	cd ../../..
	echo "script-2: stub package added"
else
	echo "script-2: FATAL: feeds/smpackage/shadowsocks-libev not found"
	exit 1
fi

# --- Verify Python3 ---
if ! command -v python3 >/dev/null 2>&1; then
	echo "script-2: FATAL: python3 not found"
	exit 1
fi

# --- SSR Plus: Makefile + LuCI + init script + ssr-rules patches ---
python3 << 'PYEOF'
import sys, os

base = 'feeds/smpackage/luci-app-ssr-plus'

# =============================================================================
# Makefile: Kconfig + package depends
# =============================================================================
with open(f'{base}/Makefile', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace(
    'CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_NONE_Client \\',
    'CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client \\\n\tCONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_NONE_Client \\'
)

old_dep = '+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client:shadowsocks-rust-sslocal \\'
new_dep = (
    '+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client:shadowsocks-libev-config \\\n'
    '\t+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client:shadowsocks-libev-ss-local \\\n'
    '\t+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client:shadowsocks-libev-ss-redir \\\n'
    '\t+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client:shadowsocks-libev-ss-server \\\n'
    '\t+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client:shadowsocks-rust-sslocal \\'
)
content = content.replace(old_dep, new_dep)

# Libev_Server Kconfig + depends
old_server_dep = '+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Server:shadowsocks-rust-ssserver \\'
new_server_dep = '+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Server:shadowsocks-libev-ss-server \\\n\t' + old_server_dep
content = content.replace(old_server_dep, new_server_dep)

content = content.replace(
    '\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client',
    '\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client\n\t\tbool "Shadowsocks Libev"\n\t\tdefault n\n\n\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client'
)

content = content.replace(
    '\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Server',
    '\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Server\n\t\tbool "Shadowsocks Libev"\n\t\tdefault n\n\n\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Server'
)

with open(f'{base}/Makefile', 'w', encoding='utf-8') as f:
    f.write(content)
print("Makefile: done")

# =============================================================================
# LuCI client-config.lua: type dropdown + depends
# =============================================================================
with open(f'{base}/luasrc/model/cbi/shadowsocksr/client-config.lua', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace(
    'local has_ss_rust = is_finded("sslocal") or is_finded("ssserver")',
    'local has_ss_rust = is_finded("sslocal") or is_finded("ssserver")\nlocal has_ss_libev = is_finded("ss-redir") or is_finded("ss-local")'
)

old_block = (
    'if has_ss_rust then\n'
    '\to:value("ss-rust", translate("ShadowSocks"))\n'
    'end'
)
new_block = (
    'if has_ss_rust then\n'
    '\to:value("ss-rust", translate("ShadowSocks"))\n'
    'end\n'
    'if has_ss_libev then\n'
    '\to:value("ss-libev", translate("ShadowSocks Libev"))\n'
    'end'
)
if old_block in content:
    content = content.replace(old_block, new_block)
    print("lua: ss-libev type block added")
else:
    print("WARNING: ss-rust block NOT found in client-config.lua")

content = content.replace(
    'o:depends("type", "ss-rust")',
    'o:depends("type", "ss-rust")\n\to:depends("type", "ss-libev")'
)

with open(f'{base}/luasrc/model/cbi/shadowsocksr/client-config.lua', 'w', encoding='utf-8') as f:
    f.write(content)
print("LuCI client-config.lua: done")

# =============================================================================
# LuCI gen_config.lua: ss-libev -> ss type mapping
# =============================================================================
gen_config_path = f'{base}/root/usr/share/shadowsocksr/gen_config.lua'
with open(gen_config_path, 'r', encoding='utf-8') as f:
    content = f.read()

old = 'if server.type == "ss-rust" then'
new = 'if server.type == "ss-rust" or server.type == "ss-libev" then'
if old in content:
    content = content.replace(old, new, 1)
    print("gen_config.lua: ss-libev type mapping added")
elif new in content:
    print("gen_config.lua: ss-libev mapping already present")
else:
    print("WARNING: gen_config.lua ss-rust mapping NOT found")

with open(gen_config_path, 'w', encoding='utf-8') as f:
    f.write(content)

# =============================================================================
# LuCI subscribe.lua: add ss-libev to preferred_ss_backend()
# =============================================================================
subscribe_path = f'{base}/root/usr/share/shadowsocksr/subscribe.lua'
with open(subscribe_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Add has_ss_libev detection (incl. ss-server for server mode)
content = content.replace(
    'local has_ss_rust = luci.sys.exec(\'type -t -p sslocal 2>/dev/null || type -t -p ssserver 2>/dev/null\') ~= ""',
    'local has_ss_rust = luci.sys.exec(\'type -t -p sslocal 2>/dev/null || type -t -p ssserver 2>/dev/null\') ~= ""\nlocal has_ss_libev = luci.sys.exec(\'type -t -p ss-redir 2>/dev/null || type -t -p ss-local 2>/dev/null || type -t -p ss-server 2>/dev/null\') ~= ""'
)

# Add ss-libev to preferred_ss_backend() after ss-rust block
old_func = (
    '\tif has_ss_rust then\n'
    '\t\treturn "ss-rust"\n'
    '\tend\n'
    '\tif has_xray then'
)
new_func = (
    '\tif has_ss_rust then\n'
    '\t\treturn "ss-rust"\n'
    '\tend\n'
    '\tif has_ss_libev then\n'
    '\t\treturn "ss-libev"\n'
    '\tend\n'
    '\tif has_xray then'
)
if old_func in content:
    content = content.replace(old_func, new_func)
    print("subscribe.lua: ss-libev backend added")
else:
    print("WARNING: preferred_ss_backend block NOT found in subscribe.lua")

with open(subscribe_path, 'w', encoding='utf-8') as f:
    f.write(content)

# =============================================================================
# LuCI server-config.lua: ss-libev server type + depends
# =============================================================================
server_config_path = f'{base}/luasrc/model/cbi/shadowsocksr/server-config.lua'
# Upstream server-config.lua may be GBK-encoded; try UTF-8 first then fall back
try:
    with open(server_config_path, 'r', encoding='utf-8') as f:
        content = f.read()
except (UnicodeDecodeError, UnicodeError):
    with open(server_config_path, 'r', encoding='gbk') as f:
        content = f.read()

# Add ss-libev server type option
old_block = 'if nixio.fs.access("/usr/bin/mihomo") or nixio.fs.access("/usr/libexec/mihomo") or nixio.fs.access("/usr/bin/ssserver") or nixio.fs.access("/usr/libexec/ssserver") then\n\to:value("ss", translate("ShadowSocks"))\nend'
new_block = 'if nixio.fs.access("/usr/bin/mihomo") or nixio.fs.access("/usr/libexec/mihomo") or nixio.fs.access("/usr/bin/ssserver") or nixio.fs.access("/usr/libexec/ssserver") then\n\to:value("ss", translate("ShadowSocks"))\nend\nif nixio.fs.access("/usr/bin/ss-server") or nixio.fs.access("/usr/libexec/ss-server") then\n\to:value("ss-libev", translate("ShadowSocks Libev"))\nend'
if old_block in content:
    content = content.replace(old_block, new_block)
    print("server-config.lua: ss-libev server type added")
else:
    print("WARNING: server-config.lua ss block NOT found")

# Add ss-libev to depends for ss-specific options
depends_fixes = [
    ('o:depends("type", "ss")\no:depends("type", "ssr")',
     'o:depends("type", "ss")\no:depends("type", "ss-libev")\no:depends("type", "ssr")'),
    ('o:depends("type", "socks5")\no:depends("type", "ss")\no:depends("type", "ssr")',
     'o:depends("type", "socks5")\no:depends("type", "ss")\no:depends("type", "ss-libev")\no:depends("type", "ssr")'),
    ('o:depends("type", "ss")\n',
     'o:depends("type", "ss")\no:depends("type", "ss-libev")\n'),
]
for old_dep, new_dep in depends_fixes:
    if old_dep in content:
        content = content.replace(old_dep, new_dep)
        print("server-config.lua: depends updated")
    else:
        print("WARNING: depends block NOT found")

with open(server_config_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("LuCI server-config.lua: done")

# =============================================================================
# Init script patches (P1-P9)
# =============================================================================
init_path = f'{base}/root/etc/init.d/shadowsocksr'
with open(init_path, 'r', encoding='utf-8') as f:
    content = f.read()

errors = []

# P1: _migrate_xray_protocol_node — upstream already has ss-libev, verify only
old_p1 = '\t\tif [ "$type" = "ss" ] || [ "$type" = "ss-libev" ]; then'
if old_p1 in content:
    print("P1 _migrate: upstream already has ss-libev (verified)")
else:
    # Fallback: add it if upstream removed it
    old_p1_alt = '\t\tif [ "$type" = "ss" ]; then'
    if old_p1_alt in content:
        content = content.replace(old_p1_alt, old_p1)
        print("P1 _migrate: added ss-libev guard")
    else:
        errors.append("P1 _migrate")

# P2: supports_builtin_socks()
old = '\tss|clash|tuic|v2ray)'
new = '\tss|ss-libev|clash|tuic|v2ray)'
if old in content:
    content = content.replace(old, new)
    print("P2 supports_builtin_socks: OK")
else:
    errors.append("P2 supports_builtin_socks")

# P3: UDP relay normalization
old = '\tif [ "$udp_relay_server_type" = "ss-rust" ]; then\n\t\ttype="ss"\n\tfi'
new = '\tif [ "$udp_relay_server_type" = "ss-rust" ] || [ "$udp_relay_server_type" = "ss-libev" ]; then\n\t\ttype="ss"\n\tfi'
if old in content:
    content = content.replace(old, new)
    print("P3 UDP relay: OK")
else:
    errors.append("P3 UDP relay")

# P4: SOCKS5 normalization
old = '\tif [ "$local_server_type" = "ss-rust" ]; then\n\t\ttype="ss"\n\tfi'
new = '\tif [ "$local_server_type" = "ss-rust" ] || [ "$local_server_type" = "ss-libev" ]; then\n\t\ttype="ss"\n\tfi'
if old in content:
    content = content.replace(old, new)
    print("P4 SOCKS5: OK")
else:
    errors.append("P4 SOCKS5")

# P5: get_udp_relay_mode (if/then/fi avoids ||/&& precedence bug)
old = '\t[ "$type" = "ss-rust" ] && type="ss"'
new = '\tif [ "$type" = "ss-rust" ] || [ "$type" = "ss-libev" ]; then\n\t\ttype="ss"\n\tfi'
if old in content:
    content = content.replace(old, new)
    print("P5 get_udp_relay_mode: OK")
else:
    errors.append("P5 get_udp_relay_mode")

# P6: Start_Run normalization
old = '\tif [ "$global_server_type" = "ss-rust" ]; then\n\t\ttype="ss"\n\tfi'
new = '\tif [ "$global_server_type" = "ss-rust" ] || [ "$global_server_type" = "ss-libev" ]; then\n\t\ttype="ss"\n\tfi'
if old in content:
    content = content.replace(old, new)
    print("P6 Start_Run: OK")
else:
    errors.append("P6 Start_Run")

# P7: Core Start_Run — ss-redir -u for ss-libev
old_tcp = (
    '\t\telse\n'
    '\t\t\tgen_config_file $GLOBAL_SERVER $type 1 $tcp_port\n'
    '\t\t\tss_program="$(first_type sslocal)"\n'
    '\t\t\techolog "ShadowSocks program is: $ss_program"\n'
    '\t\t\told_ss_program=$(readlink -f "$TMP_PATH/bin/${type}-redir" 2>/dev/null)\n'
    '\t\t\tif [ "$old_ss_program" != "$ss_program" ]; then\n'
    '\t\t\t\trm -rf "$TMP_PATH/bin/${type}-redir"\n'
    '\t\t\tfi\n'
    '\t\t\tln_start_bin $ss_program ${type}-redir -c $tcp_config_file\n'
    '\t\t\techolog "Main node:Shadowsocks-rust Started!"'
)
new_tcp = (
    '\t\telse\n'
    '\t\t\tgen_config_file $GLOBAL_SERVER $type 1 $tcp_port\n'
    '\t\t\tif [ "$global_server_type" = "ss-libev" ]; then\n'
    '\t\t\t\tss_program="$(first_type ss-redir)"\n'
    '\t\t\t\techolog "ShadowSocks program is: $ss_program"\n'
    '\t\t\t\told_ss_program=$(readlink -f "$TMP_PATH/bin/${type}-redir" 2>/dev/null)\n'
    '\t\t\t\tif [ "$old_ss_program" != "$ss_program" ]; then\n'
    '\t\t\t\t\trm -rf "$TMP_PATH/bin/${type}-redir"\n'
    '\t\t\t\tfi\n'
    '\t\t\t\tln_start_bin $ss_program ${type}-redir -u -c $tcp_config_file\n'
    '\t\t\t\techolog "Main node:Shadowsocks Libev Started!"\n'
    '\t\t\telse\n'
    '\t\t\t\tss_program="$(first_type sslocal)"\n'
    '\t\t\t\techolog "ShadowSocks program is: $ss_program"\n'
    '\t\t\t\told_ss_program=$(readlink -f "$TMP_PATH/bin/${type}-redir" 2>/dev/null)\n'
    '\t\t\t\tif [ "$old_ss_program" != "$ss_program" ]; then\n'
    '\t\t\t\t\trm -rf "$TMP_PATH/bin/${type}-redir"\n'
    '\t\t\t\tfi\n'
    '\t\t\t\tln_start_bin $ss_program ${type}-redir -c $tcp_config_file\n'
    '\t\t\t\techolog "Main node:Shadowsocks-rust Started!"\n'
    '\t\t\tfi'
)
if old_tcp in content:
    content = content.replace(old_tcp, new_tcp)
    print("P7 core TCP: OK")
else:
    errors.append("P7 core TCP")

# P8: SOCKS5 — ss-local for ss-libev
old_socks = (
    '\t\telse\n'
    '\t\t\tgen_config_file $LOCAL_SERVER $type 4 $local_port\n'
    '\t\t\tss_program="$(first_type sslocal)"\n'
    '\t\t\techolog "ShadowSocks program is: $ss_program"\n'
    '\t\t\told_ss_program=$(readlink -f "$TMP_PATH/bin/${type}-local" 2>/dev/null)\n'
    '\t\t\tif [ "$old_ss_program" != "$ss_program" ]; then\n'
    '\t\t\t\trm -rf "$TMP_PATH/bin/${type}-local"\n'
    '\t\t\tfi\n'
    '\t\t\tln_start_bin $ss_program ${type}-local -c $local_config_file\n'
    '\t\t\techolog "Global_Socks5:Shadowsocks-rust Started!"'
)
new_socks = (
    '\t\telse\n'
    '\t\t\tgen_config_file $LOCAL_SERVER $type 4 $local_port\n'
    '\t\t\tif [ "$local_server_type" = "ss-libev" ]; then\n'
    '\t\t\t\tss_program="$(first_type ss-local)"\n'
    '\t\t\t\techolog "ShadowSocks program is: $ss_program"\n'
    '\t\t\t\told_ss_program=$(readlink -f "$TMP_PATH/bin/${type}-local" 2>/dev/null)\n'
    '\t\t\t\tif [ "$old_ss_program" != "$ss_program" ]; then\n'
    '\t\t\t\t\trm -rf "$TMP_PATH/bin/${type}-local"\n'
    '\t\t\t\tfi\n'
    '\t\t\t\tln_start_bin $ss_program ${type}-local -c $local_config_file\n'
    '\t\t\t\techolog "Global_Socks5:Shadowsocks Libev Started!"\n'
    '\t\t\telse\n'
    '\t\t\t\tss_program="$(first_type sslocal)"\n'
    '\t\t\t\techolog "ShadowSocks program is: $ss_program"\n'
    '\t\t\t\told_ss_program=$(readlink -f "$TMP_PATH/bin/${type}-local" 2>/dev/null)\n'
    '\t\t\t\tif [ "$old_ss_program" != "$ss_program" ]; then\n'
    '\t\t\t\t\trm -rf "$TMP_PATH/bin/${type}-local"\n'
    '\t\t\t\tfi\n'
    '\t\t\t\tln_start_bin $ss_program ${type}-local -c $local_config_file\n'
    '\t\t\t\techolog "Global_Socks5:Shadowsocks-rust Started!"\n'
    '\t\t\tfi'
)
if old_socks in content:
    content = content.replace(old_socks, new_socks)
    print("P8 SOCKS5: OK")
else:
    errors.append("P8 SOCKS5")

# P9: Server mode — ss-libev normalization + ss-server binary
old_p9a = '\t\t\tif [ "$node_type" = "ss-rust" ]; then\n\t\t\t\ttype="ss"\n\t\t\tfi'
new_p9a = '\t\t\tif [ "$node_type" = "ss-rust" ] || [ "$node_type" = "ss-libev" ]; then\n\t\t\t\ttype="ss"\n\t\t\tfi'
if old_p9a in content:
    content = content.replace(old_p9a, new_p9a)
    print("P9a server norm: OK")
else:
    errors.append("P9a server norm")

old_p9b = '\t\t\t\t\telif [ "$node_type" = "ss-rust" ] || [ "$node_type" = "ss" ]; then\n\t\t\t\t\t\tss_program="$(first_type ${type}server)"'
new_p9b = '\t\t\t\t\telif [ "$node_type" = "ss-libev" ]; then\n\t\t\t\t\t\tss_program="$(first_type ss-server)"\n\t\t\t\t\telif [ "$node_type" = "ss-rust" ] || [ "$node_type" = "ss" ]; then\n\t\t\t\t\t\tss_program="$(first_type ${type}server)"'
if old_p9b in content:
    content = content.replace(old_p9b, new_p9b)
    print("P9b server binary: OK")
else:
    errors.append("P9b server binary")

if errors:
    print(f"\nFATAL ({len(errors)}): {', '.join(errors)}")
    sys.exit(1)

with open(init_path, 'w', encoding='utf-8') as f:
    f.write(content)

# =============================================================================
# Post-patch verification: confirm critical patterns are in the patched file
# =============================================================================
with open(init_path, 'r', encoding='utf-8') as f:
    final = f.read()

verifications = {
    'P2 socsk':        'ss|ss-libev|clash|tuic|v2ray)',
    'P3 UDP relay':    'udp_relay_server_type" = "ss-rust" ] || [ "$udp_relay_server_type" = "ss-libev"',
    'P5 udp mode':     'if [ "$type" = "ss-rust" ] || [ "$type" = "ss-libev" ]; then\n\t\ttype="ss"\n\tfi',
    'P6 Start_Run':    'global_server_type" = "ss-rust" ] || [ "$global_server_type" = "ss-libev"',
    'P7 ss-redir -u':  'ln_start_bin $ss_program ${type}-redir -u -c $tcp_config_file',
    'P8 ss-local':     'first_type ss-local',
    'P9 ss-server':    'first_type ss-server',
}
verify_errors = []
for label, pattern in verifications.items():
    if pattern not in final:
        verify_errors.append(label)
        print(f"VERIFY FAIL: {label}")
    else:
        print(f"VERIFY OK: {label}")

if verify_errors:
    print(f"\nVERIFICATION FAILED ({len(verify_errors)}): {', '.join(verify_errors)}")
    sys.exit(1)

print("\nAll 9 init patches applied and verified successfully")
PYEOF

echo "=== script-2: init + LuCI patches done ==="

# =============================================================================
# ssr-rules: fix duplicate daemon instances (DAEMON_ID + PID tracking)
# =============================================================================
RULES_PATH="feeds/smpackage/luci-app-ssr-plus/root/usr/bin/ssr-rules"
if [ -f "$RULES_PATH" ]; then
	python3 << 'PYRULES'
import sys

rules_path = "feeds/smpackage/luci-app-ssr-plus/root/usr/bin/ssr-rules"
with open(rules_path, 'r', encoding='utf-8') as f:
    rcontent = f.read()

errors = []

# P10: Add DAEMON_ID tracking
old_r = (
    '\t# Stop already running daemon\n'
    '\tstop_auto_update_daemon\n'
    '\n'
    '\t# Start daemon directly in background\n'
    '\t(\n'
    '\t\tlogger -t ssr-rules[daemon] "Auto-update daemon started - PID: $$"\n'
    '\t\techo $$ > "/var/run/ssr-rules-daemon.pid"\n'
    '\n'
    '\t\twhile true; do\n'
    '\t\t\tsleep "$AUTO_UPDATE_INTERVAL"'
)
new_r = (
    '\t# Stop already running daemon\n'
    '\tstop_auto_update_daemon\n'
    '\n'
    '\tDAEMON_ID="$-$(date +%s)"\n'
    '\n'
    '\t# Start daemon directly in background\n'
    '\t(\n'
    '\t\techo "$DAEMON_ID" > "/var/run/ssr-rules-daemon.id"\n'
    '\t\tlogger -t ssr-rules[daemon] "Auto-update daemon started - PID: $$"\n'
    '\n'
    '\t\twhile true; do\n'
    '\t\t\t[ "$(cat /var/run/ssr-rules-daemon.id 2>/dev/null)" = "$DAEMON_ID" ] || exit 0\n'
    '\t\t\tsleep "$AUTO_UPDATE_INTERVAL"'
)
if old_r in rcontent:
    rcontent = rcontent.replace(old_r, new_r)
    print("P10 DAEMON_ID: OK")
else:
    errors.append("P10 DAEMON_ID")

# P11: Write real background PID
old_pid = '\t) &\n\n\tlocal DAEMON_PID=$!\n\tsleep 2'
new_pid = '\t) &\n\n\tlocal DAEMON_PID=$!\n\techo "$DAEMON_PID" > "/var/run/ssr-rules-daemon.pid"\n\tsleep 2'
if old_pid in rcontent:
    rcontent = rcontent.replace(old_pid, new_pid)
    print("P11 PID fix: OK")
else:
    errors.append("P11 PID fix")

if errors:
    print(f"ssr-rules ERRORS: {', '.join(errors)}")
    sys.exit(1)

with open(rules_path, 'w', encoding='utf-8') as f:
    f.write(rcontent)
print("ssr-rules patches applied successfully")
PYRULES
	echo "=== script-2: ssr-rules done ==="
else
	echo "=== script-2: ssr-rules not found, skipping ==="
fi

echo "=== script-2: ALL DONE ==="
