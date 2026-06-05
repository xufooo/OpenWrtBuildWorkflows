#!/bin/bash

# --- shadowsocks-libev: config stub (required by SSR Plus depends) ---
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

python3 << 'PYEOF'
import sys

base = 'feeds/smpackage/luci-app-ssr-plus'

# =============================================================================
# Makefile: Kconfig + package depends
# =============================================================================
with open(f'{base}/Makefile', 'r') as f:
    content = f.read()

mf_guard = 'CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client'
if mf_guard not in content:
    print("FATAL: Makefile format changed — cannot apply ss-libev patches")
    sys.exit(1)

content = content.replace(
    'CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_NONE_Client \\',
    'CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client \\\n\tCONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_NONE_Client \\'
)

old_dep = '+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client:shadowsocks-rust-sslocal \\'
new_dep = (
    '+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client:shadowsocks-libev-config \\\n'
    '\t+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client:shadowsocks-libev-ss-local \\\n'
    '\t+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client:shadowsocks-libev-ss-redir \\\n'
    '\t+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client:shadowsocks-rust-sslocal \\'
)
if old_dep in content:
    content = content.replace(old_dep, new_dep)
    print("Makefile: client depends OK")
else:
    print("WARNING: Makefile client depends pattern NOT found")

old_server_dep = '+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Server:shadowsocks-rust-ssserver \\'
new_server_dep = '+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Server:shadowsocks-libev-ss-server \\\n\t' + old_server_dep
if old_server_dep in content:
    content = content.replace(old_server_dep, new_server_dep)
    print("Makefile: server depends OK")
else:
    print("WARNING: Makefile server depends pattern NOT found")

content = content.replace(
    '\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client',
    '\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client\n\t\tbool "Shadowsocks Libev"\n\t\tdefault n\n\n\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client'
)

content = content.replace(
    '\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Server',
    '\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Server\n\t\tbool "Shadowsocks Libev"\n\t\tdefault n\n\n\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Server'
)

with open(f'{base}/Makefile', 'w') as f:
    f.write(content)
print("Makefile: done")

# =============================================================================
# LuCI client-config.lua: type dropdown + depends
# =============================================================================
with open(f'{base}/luasrc/model/cbi/shadowsocksr/client-config.lua', 'r') as f:
    content = f.read()

lua_guard = 'local has_ss_rust = is_finded("sslocal") or is_finded("ssserver")'
if lua_guard in content:
    content = content.replace(lua_guard,
        lua_guard + '\nlocal has_ss_libev = is_finded("ss-redir") or is_finded("ss-local")')
    print("client-config: has_ss_libev detection OK")
else:
    print("WARNING: client-config has_ss_rust NOT found")

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

dep_guard = 'o:depends("type", "ss-rust")'
if dep_guard in content:
    content = content.replace(dep_guard,
        'o:depends("type", "ss-rust")\n\to:depends("type", "ss-libev")')
    print("client-config: ss-libev depends OK")
else:
    print("WARNING: client-config depends NOT found")

with open(f'{base}/luasrc/model/cbi/shadowsocksr/client-config.lua', 'w') as f:
    f.write(content)
print("LuCI client-config.lua: done")

# =============================================================================
# LuCI gen_config.lua: ss-libev -> ss type mapping
# =============================================================================
gen_config_path = f'{base}/root/usr/share/shadowsocksr/gen_config.lua'
with open(gen_config_path, 'r') as f:
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

with open(gen_config_path, 'w') as f:
    f.write(content)

# =============================================================================
# LuCI subscribe.lua: add ss-libev to preferred_ss_backend()
# =============================================================================
subscribe_path = f'{base}/root/usr/share/shadowsocksr/subscribe.lua'
with open(subscribe_path, 'r') as f:
    content = f.read()

# Add has_ss_libev detection after has_ss_rust
sub_guard = 'local has_ss_rust = luci.sys.exec(\'type -t -p sslocal 2>/dev/null || type -t -p ssserver 2>/dev/null\') ~= ""'
if sub_guard in content:
    content = content.replace(sub_guard,
        sub_guard + '\nlocal has_ss_libev = luci.sys.exec(\'type -t -p ss-redir 2>/dev/null || type -t -p ss-local 2>/dev/null || type -t -p ss-server 2>/dev/null\') ~= ""')
    print("subscribe.lua: has_ss_libev detection OK")
else:
    print("WARNING: subscribe.lua has_ss_rust NOT found")

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

with open(subscribe_path, 'w') as f:
    f.write(content)
# =============================================================================
# LuCI server-config.lua: add ss-libev server type detection
# =============================================================================
server_config_path = f'{base}/luasrc/model/cbi/shadowsocksr/server-config.lua'
with open(server_config_path, 'r') as f:
    content = f.read()

# Add ss-libev server type option when ss-server binary exists
old_block = 'if nixio.fs.access("/usr/bin/mihomo") or nixio.fs.access("/usr/libexec/mihomo") or nixio.fs.access("/usr/bin/ssserver") or nixio.fs.access("/usr/libexec/ssserver") then\n\to:value("ss", translate("ShadowSocks"))\nend'
new_block = 'if nixio.fs.access("/usr/bin/mihomo") or nixio.fs.access("/usr/libexec/mihomo") or nixio.fs.access("/usr/bin/ssserver") or nixio.fs.access("/usr/libexec/ssserver") then\n\to:value("ss", translate("ShadowSocks"))\nend\nif nixio.fs.access("/usr/bin/ss-server") or nixio.fs.access("/usr/libexec/ss-server") then\n\to:value("ss-libev", translate("ShadowSocks Libev"))\nend'
if old_block in content:
    content = content.replace(old_block, new_block)
    print("server-config.lua: added ss-libev server type option")
else:
    print("WARNING: server-config.lua ss block NOT found")

# Add ss-libev to depends for ss-specific options
depends_fixes = [
    # timeout: ss + ssr -> ss + ss-libev + ssr
    ('o:depends("type", "ss")\no:depends("type", "ssr")',
     'o:depends("type", "ss")\no:depends("type", "ss-libev")\no:depends("type", "ssr")'),
    # password: socks5 + ss + ssr -> socks5 + ss + ss-libev + ssr
    ('o:depends("type", "socks5")\no:depends("type", "ss")\no:depends("type", "ssr")',
     'o:depends("type", "socks5")\no:depends("type", "ss")\no:depends("type", "ss-libev")\no:depends("type", "ssr")'),
    # encrypt_method_ss: ss only -> ss + ss-libev
    ('o:depends("type", "ss")\n',
     'o:depends("type", "ss")\no:depends("type", "ss-libev")\n'),
]
for old_dep, new_dep in depends_fixes:
    if old_dep in content:
        content = content.replace(old_dep, new_dep)
        print("server-config.lua: added ss-libev depends")
    else:
        print("WARNING: depends block NOT found: " + old_dep[:60])

with open(server_config_path, 'w') as f:
    f.write(content)

# =============================================================================
# Init script patches
# =============================================================================
init_path = f'{base}/root/etc/init.d/shadowsocksr'
with open(init_path, 'r') as f:
    content = f.read()

errors = []

# P1: Stop _migrate_xray_protocol_node from converting ss-libev->ss-rust
# line-based match, robust against whitespace drift
p1_done = False
for i, line in enumerate(content.split(chr(10))):
    if '[ "$type" = "ss" ] || [ "$type" = "ss-libev" ]' in line:
        repl = line.replace('[ "$type" = "ss" ] || [ "$type" = "ss-libev" ]', '[ "$type" = "ss" ]')
        content = content.replace(line, repl)
        p1_done = True
        break
if p1_done:
    print("P1 migration stop: OK")
else:
    errors.append("P1 migration stop")

# P2: supports_builtin_socks() - add ss-libev
# line-based match, robust against whitespace drift
p2_done = False
for i, line in enumerate(content.split(chr(10))):
    if 'ss|clash|tuic|v2ray)' in line:
        indent = line[:len(line) - len(line.lstrip())]
        repl = indent + 'ss|ss-libev|clash|tuic|v2ray)'
        content = content.replace(line, repl)
        p2_done = True
        break
if p2_done:
    print("P2 supports_builtin_socks: OK")
else:
    errors.append("P2 supports_builtin_socks")

# P3: UDP relay normalization
# line-based match, robust against whitespace drift
p3_done = False
for i, line in enumerate(content.split(chr(10))):
    if '[ "$udp_relay_server_type" = "ss-rust" ]' in line:
        repl = line.replace('[ "$udp_relay_server_type" = "ss-rust" ]', '[ "$udp_relay_server_type" = "ss-rust" ] || [ "$udp_relay_server_type" = "ss-libev" ]')
        content = content.replace(line, repl)
        p3_done = True
        break
if p3_done:
    print("P3 UDP relay normal.: OK")
else:
    errors.append("P3 UDP relay normal.")

# P4: SOCKS5 normalization
# line-based match, robust against whitespace drift
p4_done = False
for i, line in enumerate(content.split(chr(10))):
    if '[ "$local_server_type" = "ss-rust" ]' in line:
        repl = line.replace('[ "$local_server_type" = "ss-rust" ]', '[ "$local_server_type" = "ss-rust" ] || [ "$local_server_type" = "ss-libev" ]')
        content = content.replace(line, repl)
        p4_done = True
        break
if p4_done:
    print("P4 SOCKS5 normal.: OK")
else:
    errors.append("P4 SOCKS5 normal.")

# P5: get_udp_relay_mode normalization (uses if/then/fi to avoid ||/&& precedence bug)
# line-based match, robust against whitespace drift
p5_done = False
for i, line in enumerate(content.split(chr(10))):
    if '[ "$type" = "ss-rust" ] && type="ss"' in line:
        indent = line[:len(line) - len(line.lstrip())]
        nl = chr(10)
        tb = chr(9)
        repl = indent + 'if [ "$type" = "ss-rust" ] || [ "$type" = "ss-libev" ]; then' + nl + indent + tb + 'type="ss"' + nl + indent + 'fi'
        content = content.replace(line, repl)
        p5_done = True
        break
if p5_done:
    print("P5 get_udp_relay_mode: OK")
else:
    errors.append("P5 get_udp_relay_mode")

# P6: Start_Run normalization
# line-based match, robust against whitespace drift
p6_done = False
for i, line in enumerate(content.split(chr(10))):
    if '[ "$global_server_type" = "ss-rust" ]' in line:
        repl = line.replace('[ "$global_server_type" = "ss-rust" ]', '[ "$global_server_type" = "ss-rust" ] || [ "$global_server_type" = "ss-libev" ]')
        content = content.replace(line, repl)
        p6_done = True
        break
if p6_done:
    print("P6 Start_Run normal.: OK")
else:
    errors.append("P6 Start_Run normal.")

# P7: Core Start_Run - ss-redir -u for ss-libev
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
    print("P7 core start TCP: OK")
else:
    errors.append("P7 core start TCP")

# P8: SOCKS5 - ss-local for ss-libev
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
    print("P8 SOCKS5 binary: OK")
else:
    errors.append("P8 SOCKS5 binary")


# P9: Server mode - ss-libev normalization + ss-server binary
# line-based match, robust against whitespace drift
p9a_done = False
lines_p9a = content.split(chr(10))
for i, line in enumerate(lines_p9a):
    if '[ "$node_type" = "ss-rust" ]' in line and i+1 < len(lines_p9a) and 'type="ss"' in lines_p9a[i+1]:
        repl = line.replace('[ "$node_type" = "ss-rust" ]', '[ "$node_type" = "ss-rust" ] || [ "$node_type" = "ss-libev" ]')
        content = content.replace(line, repl)
        p9a_done = True
        break
if p9a_done:
    print("P9a server norm.: OK")
else:
    errors.append("P9a server norm.")

# line-based match, robust against whitespace drift
p9b_done = False
for i, line in enumerate(content.split(chr(10))):
    if 'elif [ "$node_type" = "ss-rust" ] || [ "$node_type" = "ss" ]' in line:
        indent = line[:len(line) - len(line.lstrip())]
        nl = chr(10)
        repl = indent + 'elif [ "$node_type" = "ss-libev" ]; then' + nl + indent + chr(9) + 'ss_program="$(first_type ss-server)"' + nl + line
        content = content.replace(line, repl)
        p9b_done = True
        break
if p9b_done:
    print("P9b server binary: OK")
else:
    errors.append("P9b server binary")

if errors:
    print(f"\nERRORS ({len(errors)}): {', '.join(errors)}")
    sys.exit(1)

with open(init_path, 'w') as f:
    f.write(content)
print("\nAll 10 init patches applied successfully")

with open(init_path, 'r') as f:
    final = f.read()
extra_norm = final.count('"$global_server_type" = "ss-libev" ] || [ "$global_server_type"')
if extra_norm > 0:
    print("WARNING: possible double-patch of Start_Run normalization")
else:
    print("Sanity check: no double-patch detected")
PYEOF


# =============================================================================
# ssr-rules: fix duplicate daemon instances (DAEMON_ID + PID tracking)
# Bug: ()& subshell writes $ (parent PID) to pid_file instead of real PID,
#      and old daemons survive restarts because nothing tracks them.
# =============================================================================
rules_path="feeds/smpackage/luci-app-ssr-plus/root/usr/bin/ssr-rules"
if [ -f "$rules_path" ]; then
    python3 << 'PYRULES'
import sys
rules_path = "feeds/smpackage/luci-app-ssr-plus/root/usr/bin/ssr-rules"
with open(rules_path, 'r') as f:
    rcontent = f.read()

errors = []

# P10: Add DAEMON_ID tracking to prevent duplicate daemons
old_r = (
    '\t# Stop already running daemon\n'
    '\tstop_auto_update_daemon\n'
    '\n'
    '\t# Start daemon directly in background\n'
    '\t(\n'
    '\t\tlogger -t ssr-rules[daemon] "Auto-update daemon started - PID: $"\n'
    '\t\techo $ > "/var/run/ssr-rules-daemon.pid"\n'
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
    '\t\tlogger -t ssr-rules[daemon] "Auto-update daemon started - PID: $"\n'
    '\n'
    '\t\twhile true; do\n'
    '\t\t\t[ "$(cat /var/run/ssr-rules-daemon.id 2>/dev/null)" = "$DAEMON_ID" ] || exit 0\n'
    '\t\t\tsleep "$AUTO_UPDATE_INTERVAL"'
)
if old_r in rcontent:
    rcontent = rcontent.replace(old_r, new_r)
    print("P10 ssr-rules DAEMON_ID: OK")
else:
    errors.append("P10 ssr-rules DAEMON_ID")

# P11: Write real background PID (not shell $) to pid file
old_pid = '\t) &\n\n\tlocal DAEMON_PID=$!\n\tsleep 2'
new_pid = '\t) &\n\n\tlocal DAEMON_PID=$!\n\techo "$DAEMON_PID" > "/var/run/ssr-rules-daemon.pid"\n\tsleep 2'
if old_pid in rcontent:
    rcontent = rcontent.replace(old_pid, new_pid)
    print("P11 ssr-rules PID fix: OK")
else:
    errors.append("P11 ssr-rules PID fix")

if errors:
    print(f"ssr-rules ERRORS ({len(errors)}): {', '.join(errors)}")
    sys.exit(1)

with open(rules_path, 'w') as f:
    f.write(rcontent)
print("ssr-rules patches applied successfully")
PYRULES
fi

# Suppress AUTORELEASE deprecation warnings
find feeds -name Makefile -exec sed -i -e 's/PKG_RELEASE:=$(AUTORELEASE)/PKG_RELEASE:=1/g' -e 's/PKG_RELEASE=$(AUTORELEASE)/PKG_RELEASE:=1/g' -e 's/PKG_RELEASE:=AUTORELEASE/PKG_RELEASE:=1/g' {} + 2>/dev/null || true
