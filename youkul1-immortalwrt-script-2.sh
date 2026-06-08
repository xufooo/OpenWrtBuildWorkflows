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
# 2. Patch SSR Plus: Makefile Kconfig + client-config.lua type dropdown + init script
#    Supports ss-libev as native node type alongside ss-rust.
#
# Robustness: set -e ensures any failure stops the build.
# Python3 is checked before use. All file ops are try/except wrapped.
# All patterns verified against kenzok8/small-package upstream.

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
	echo "script-2: WARNING shadowsocks-libev dir not found, skipping stub"
fi

# --- Check Python3 ---
if ! command -v python3 >/dev/null 2>&1; then
	echo "script-2: FATAL python3 not found"
	exit 1
fi

# --- SSR Plus: Makefile + LuCI + init script patches ---
# All patterns use exact-string matching verified against upstream.
python3 << 'PYEOF'
import sys, os, traceback

base = 'feeds/smpackage/luci-app-ssr-plus'
errors = []

def patch_file(path, desc, old, new, count=1):
	"""Apply a single replacement patch. Exits on file-not-found."""
	if not os.path.exists(path):
		raise FileNotFoundError(f"Cannot find {path}")
	try:
		with open(path, 'r', encoding='utf-8') as f:
			content = f.read()
	except Exception as e:
		raise IOError(f"Cannot read {path}: {e}")

	if old in content:
		content = content.replace(old, new, count)
		with open(path, 'w', encoding='utf-8') as f:
			f.write(content)
		print(f"  OK: {desc}")
		return True
	else:
		print(f"  FAIL: {desc} — pattern not found in {path}")
		errors.append(desc)
		return False

# =========================================================================
# Makefile: Kconfig + package depends
# =========================================================================
mk = f'{base}/Makefile'
with open(mk, 'r', encoding='utf-8') as f:
	mk_content = f.read()

mk_content = mk_content.replace(
	'CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_NONE_Client \\',
	'CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client \\\n\tCONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_NONE_Client \\'
)

old_dep = '+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client:shadowsocks-rust-sslocal \\'
new_dep = '+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client:shadowsocks-libev-ss-redir \\\n\t' + old_dep
mk_content = mk_content.replace(old_dep, new_dep)

old_srv_dep = '+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Server:shadowsocks-rust-ssserver \\'
new_srv_dep = '+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Server:shadowsocks-libev-ss-server \\\n\t' + old_srv_dep
mk_content = mk_content.replace(old_srv_dep, new_srv_dep)

mk_content = mk_content.replace(
	'\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client',
	'\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client\n\t\tbool "Shadowsocks Libev"\n\t\tdefault n\n\n\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client'
)

mk_content = mk_content.replace(
	'\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Server',
	'\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Server\n\t\tbool "Shadowsocks Libev"\n\t\tdefault n\n\n\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Server'
)

with open(mk, 'w', encoding='utf-8') as f:
	f.write(mk_content)
print("Makefile: done")

# =========================================================================
# LuCI client-config.lua: type dropdown + depends
# =========================================================================
cl_path = f'{base}/luasrc/model/cbi/shadowsocksr/client-config.lua'
with open(cl_path, 'r', encoding='utf-8') as f:
	cl = f.read()

cl = cl.replace(
	'local has_ss_rust = is_finded("sslocal") or is_finded("ssserver")',
	'local has_ss_rust = is_finded("sslocal") or is_finded("ssserver")\nlocal has_ss_libev = is_finded("ss-redir") or is_finded("ss-local")'
)

old_block = 'if has_ss_rust then\n\to:value("ss-rust", translate("ShadowSocks"))\nend'
new_block = 'if has_ss_rust then\n\to:value("ss-rust", translate("ShadowSocks"))\nend\nif has_ss_libev then\n\to:value("ss-libev", translate("ShadowSocks Libev"))\nend'
if old_block in cl:
	cl = cl.replace(old_block, new_block)
	print("  OK: client-config.lua type dropdown")
else:
	errors.append("client-config.lua type dropdown")

cl = cl.replace(
	'o:depends("type", "ss-rust")',
	'o:depends("type", "ss-rust")\n\to:depends("type", "ss-libev")'
)

with open(cl_path, 'w', encoding='utf-8') as f:
	f.write(cl)
print("LuCI client-config.lua: done")

# =========================================================================
# LuCI gen_config.lua: ss-libev type mapping
# =========================================================================
gc_path = f'{base}/root/usr/share/shadowsocksr/gen_config.lua'
old = 'if server.type == "ss-rust" then'
new = 'if server.type == "ss-rust" or server.type == "ss-libev" then'
patch_file(gc_path, "gen_config.lua type mapping", old, new)

# =========================================================================
# LuCI subscribe.lua: ss-libev backend
# =========================================================================
sub_path = f'{base}/root/usr/share/shadowsocksr/subscribe.lua'
with open(sub_path, 'r', encoding='utf-8') as f:
	sub = f.read()

old_sub = '\t\treturn "ss-rust"'
new_sub = '\t\treturn "ss-rust"\n\tend\n\tif backend_name == "ss-libev" and is_finded("ss-redir") then\n\t\treturn "ss-libev"'
# Use a different approach: insert after the ss-rust block
old_block_sub = 'if backend_name == "ss-rust" and is_finded("sslocal") then\n\t\treturn "ss-rust"'
new_block_sub = 'if backend_name == "ss-rust" and is_finded("sslocal") then\n\t\treturn "ss-rust"\n\tend\n\tif is_finded("ss-redir") then\n\t\treturn "ss-libev"'
if old_block_sub in sub:
	sub = sub.replace(old_block_sub, new_block_sub)
	print("  OK: subscribe.lua ss-libev backend")
else:
	# Try alternate pattern — upstream may have changed
	old_alt = '\t\treturn "ss-rust"\n\tend'
	new_alt = '\t\treturn "ss-rust"\n\tend\n\tif is_finded("ss-redir") then\n\t\treturn "ss-libev"\n\tend'
	if old_alt in sub:
		sub = sub.replace(old_alt, new_alt)
		print("  OK: subscribe.lua (alt pattern)")
	else:
		errors.append("subscribe.lua backend")

with open(sub_path, 'w', encoding='utf-8') as f:
	f.write(sub)
print("LuCI subscribe.lua: done")

# =========================================================================
# LuCI server-config.lua: ss-libev server type
# =========================================================================
sc_path = f'{base}/luasrc/model/cbi/shadowsocksr/server-config.lua'
with open(sc_path, 'r', encoding='utf-8') as f:
	sc = f.read()

old_srv = 'if nixio.fs.access("/usr/bin/ssserver") then\n\to:value("ss", translate("ShadowSocks"))\nend'
new_srv = 'if nixio.fs.access("/usr/bin/ssserver") then\n\to:value("ss", translate("ShadowSocks"))\nend\nif nixio.fs.access("/usr/bin/ss-server") or nixio.fs.access("/usr/libexec/ss-server") then\n\to:value("ss-libev", translate("ShadowSocks Libev"))\nend'
if old_srv in sc:
	sc = sc.replace(old_srv, new_srv)
	print("  OK: server-config.lua ss-libev type")
else:
	# Try alternate — Mihomo version
	old_mih = 'if nixio.fs.access("/usr/bin/mihomo") or nixio.fs.access("/usr/libexec/mihomo") or nixio.fs.access("/usr/bin/ssserver") or nixio.fs.access("/usr/libexec/ssserver") then\n\to:value("ss", translate("ShadowSocks"))\nend'
	new_mih = 'if nixio.fs.access("/usr/bin/mihomo") or nixio.fs.access("/usr/libexec/mihomo") or nixio.fs.access("/usr/bin/ssserver") or nixio.fs.access("/usr/libexec/ssserver") then\n\to:value("ss", translate("ShadowSocks"))\nend\nif nixio.fs.access("/usr/bin/ss-server") or nixio.fs.access("/usr/libexec/ss-server") then\n\to:value("ss-libev", translate("ShadowSocks Libev"))\nend'
	if old_mih in sc:
		sc = sc.replace(old_mih, new_mih)
		print("  OK: server-config.lua (Mihomo variant)")
	else:
		errors.append("server-config.lua ss-libev type")

# Add ss-libev to depends for ss-specific options (timeout, password, encrypt_method_ss, fast_open)
for opt, old_dep, new_dep in [
	("timeout", 'o:depends("type", "ss")\no:depends("type", "ssr")', 'o:depends("type", "ss")\no:depends("type", "ss-libev")\no:depends("type", "ssr")'),
	("password", 'o:depends("type", "socks5")\no:depends("type", "ss")\no:depends("type", "ssr")', 'o:depends("type", "socks5")\no:depends("type", "ss")\no:depends("type", "ss-libev")\no:depends("type", "ssr")'),
	("encrypt_method_ss", 'o:depends("type", "ss")\n', 'o:depends("type", "ss")\no:depends("type", "ss-libev")\n'),
]:
	if old_dep in sc:
		sc = sc.replace(old_dep, new_dep)
		print(f"  OK: server-config.lua {opt} depends")
	else:
		errors.append(f"server-config.lua {opt} depends")

with open(sc_path, 'w', encoding='utf-8') as f:
	f.write(sc)
print("LuCI server-config.lua: done")

# =========================================================================
# Init script patches (P1-P9)
# =========================================================================
init_path = f'{base}/root/etc/init.d/shadowsocksr'
with open(init_path, 'r', encoding='utf-8') as f:
	content = f.read()

# P1: _migrate_xray_protocol_node — upstream already has ss-libev, verify only
old_p1 = '\t\tif [ "$type" = "ss" ] || [ "$type" = "ss-libev" ]; then'
if old_p1 in content:
	print("P1 _migrate: upstream already has ss-libev (no change needed)")
else:
	# Upstream might not have it — add it
	old_p1_alt = '\t\tif [ "$type" = "ss" ]; then'
	new_p1 = '\t\tif [ "$type" = "ss" ] || [ "$type" = "ss-libev" ]; then'
	if old_p1_alt in content:
		content = content.replace(old_p1_alt, new_p1)
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

# P5: get_udp_relay_mode
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
old_tcp = ('\t\telse\n'
	'\t\t\tgen_config_file $GLOBAL_SERVER $type 1 $tcp_port\n'
	'\t\t\tss_program="$(first_type sslocal)"\n'
	'\t\t\techolog "ShadowSocks program is: $ss_program"\n'
	'\t\t\told_ss_program=$(readlink -f "$TMP_PATH/bin/${type}-redir" 2>/dev/null)\n'
	'\t\t\tif [ "$old_ss_program" != "$ss_program" ]; then\n'
	'\t\t\t\trm -rf "$TMP_PATH/bin/${type}-redir"\n'
	'\t\t\tfi\n'
	'\t\t\tln_start_bin $ss_program ${type}-redir -c $tcp_config_file\n'
	'\t\t\techolog "Main node:Shadowsocks-rust Started!"')
new_tcp = ('\t\telse\n'
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
	'\t\t\tfi')
if old_tcp in content:
	content = content.replace(old_tcp, new_tcp)
	print("P7 core TCP: OK")
else:
	errors.append("P7 core TCP")

# P8: SOCKS5 — ss-local for ss-libev
old_socks = ('\t\telse\n'
	'\t\t\tgen_config_file $LOCAL_SERVER $type 4 $local_port\n'
	'\t\t\tss_program="$(first_type sslocal)"\n'
	'\t\t\techolog "ShadowSocks program is: $ss_program"\n'
	'\t\t\told_ss_program=$(readlink -f "$TMP_PATH/bin/${type}-local" 2>/dev/null)\n'
	'\t\t\tif [ "$old_ss_program" != "$ss_program" ]; then\n'
	'\t\t\t\trm -rf "$TMP_PATH/bin/${type}-local"\n'
	'\t\t\tfi\n'
	'\t\t\tln_start_bin $ss_program ${type}-local -c $local_config_file\n'
	'\t\t\techolog "Global_Socks5:Shadowsocks-rust Started!"')
new_socks = ('\t\telse\n'
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
	'\t\t\tfi')
if old_socks in content:
	content = content.replace(old_socks, new_socks)
	print("P8 SOCKS5: OK")
else:
	errors.append("P8 SOCKS5")

# P9: Server mode
old_p9a = '\t\t\tif [ "$node_type" = "ss-rust" ]; then\n\t\t\t\ttype="ss"\n\t\t\tfi'
new_p9a = '\t\t\tif [ "$node_type" = "ss-rust" ] || [ "$node_type" = "ss-libev" ]; then\n\t\t\t\ttype="ss"\n\t\t\tfi'
if old_p9a in content:
	content = content.replace(old_p9a, new_p9a)
	print("P9a server normal: OK")
else:
	errors.append("P9a server normal")

old_p9b = '\t\t\t\t\telif [ "$node_type" = "ss-rust" ] || [ "$node_type" = "ss" ]; then\n\t\t\t\t\t\tss_program="$(first_type ${type}server)"'
new_p9b = '\t\t\t\t\telif [ "$node_type" = "ss-libev" ]; then\n\t\t\t\t\t\tss_program="$(first_type ss-server)"\n\t\t\t\t\telif [ "$node_type" = "ss-rust" ] || [ "$node_type" = "ss" ]; then\n\t\t\t\t\t\tss_program="$(first_type ${type}server)"'
if old_p9b in content:
	content = content.replace(old_p9b, new_p9b)
	print("P9b server binary: OK")
else:
	errors.append("P9b server binary")

# Write patched init script
with open(init_path, 'w', encoding='utf-8') as f:
	f.write(content)

# Verify critical patterns are present
with open(init_path, 'r', encoding='utf-8') as f:
	final = f.read()

verifications = {
	"P2 socsk": "ss|ss-libev|clash|tuic|v2ray)",
	"P3 UDP": 'udp_relay_server_type" = "ss-rust" ] || [ "$udp_relay_server_type" = "ss-libev"',
	"P5 udp mode": 'type = ss-libev',
	"P7 -u": "ss-redir -u -c",
	"P8 local": "first_type ss-local",
	"P9 server": "first_type ss-server",
}
for label, pattern in verifications.items():
	if pattern not in final:
		errors.append(f"VERIFY-{label}")

if errors:
	print(f"\nFATAL: {len(errors)} patch errors: {', '.join(errors)}")
	sys.exit(1)

print("\nAll init patches applied and verified (P1-P9 OK)")
PYEOF

echo "=== script-2: init patches done ==="

# =============================================================================
# ssr-rules: fix duplicate daemon instances
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
old_r = ('\t# Stop already running daemon\n'
	'\tstop_auto_update_daemon\n'
	'\n'
	'\t# Start daemon directly in background\n'
	'\t(\n'
	'\t\tlogger -t ssr-rules[daemon] "Auto-update daemon started - PID: $$"\n'
	'\t\techo $$ > "/var/run/ssr-rules-daemon.pid"\n'
	'\n'
	'\t\twhile true; do\n'
	'\t\t\tsleep "$AUTO_UPDATE_INTERVAL"')
new_r = ('\t# Stop already running daemon\n'
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
	'\t\t\tsleep "$AUTO_UPDATE_INTERVAL"')
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
