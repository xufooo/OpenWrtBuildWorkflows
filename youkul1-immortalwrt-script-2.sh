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

# --- shadowsocks-libev: config stub ---
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

# --- SSR Plus: Makefile + client-config.lua + init script patches ---
python3 << 'PYEOF'
import sys, os

base = 'feeds/smpackage/luci-app-ssr-plus'

# =============================================================================
# Makefile: Kconfig + package depends
# =============================================================================
with open(f'{base}/Makefile', 'r') as f:
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
    '\t+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client:shadowsocks-rust-sslocal \\'
)
content = content.replace(old_dep, new_dep)

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

with open(f'{base}/Makefile', 'w') as f:
    f.write(content)
print("Makefile: done")

# =============================================================================
# LuCI client-config.lua: type dropdown + depends
# =============================================================================
with open(f'{base}/luasrc/model/cbi/shadowsocksr/client-config.lua', 'r') as f:
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
# LuCI subscribe.lua: add ss-libev to preferred_ss_backend() for subscription import
# =============================================================================
subscribe_path = f'{base}/root/usr/share/shadowsocksr/subscribe.lua'
with open(subscribe_path, 'r') as f:
    content = f.read()

# Add has_ss_libev detection after has_ss_rust
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

with open(subscribe_path, 'w') as f:
    f.write(content)
# =============================================================================
# Init script patches
# =============================================================================
init_path = f'{base}/root/etc/init.d/shadowsocksr'
with open(init_path, 'r') as f:
    content = f.read()

errors = []

# P1: Stop _migrate_xray_protocol_node from converting ss-libev->ss-rust
old = '\t\tif [ "$type" = "ss" ] || [ "$type" = "ss-libev" ]; then'
new = '\t\tif [ "$type" = "ss" ]; then'
if old in content:
    content = content.replace(old, new)
    print("P1 migration stop: OK")
else:
    errors.append("P1 migration stop")

# P2: supports_builtin_socks() — add ss-libev
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
    print("P3 UDP relay normal.: OK")
else:
    errors.append("P3 UDP relay normal.")

# P4: SOCKS5 normalization
old = '\tif [ "$local_server_type" = "ss-rust" ]; then\n\t\ttype="ss"\n\tfi'
new = '\tif [ "$local_server_type" = "ss-rust" ] || [ "$local_server_type" = "ss-libev" ]; then\n\t\ttype="ss"\n\tfi'
if old in content:
    content = content.replace(old, new)
    print("P4 SOCKS5 normal.: OK")
else:
    errors.append("P4 SOCKS5 normal.")

# P5: get_udp_relay_mode normalization (uses if/then/fi to avoid ||/&& precedence bug)
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
    print("P6 Start_Run normal.: OK")
else:
    errors.append("P6 Start_Run normal.")

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
    print("P7 core start TCP: OK")
else:
    errors.append("P7 core start TCP")

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
    print("P8 SOCKS5 binary: OK")
else:
    errors.append("P8 SOCKS5 binary")


# P9: Server mode — ss-libev normalization + ss-server binary
old_p9a = '\t\t\tif [ "$node_type" = "ss-rust" ]; then\n\t\t\t\ttype="ss"\n\t\t\tfi'
new_p9a = '\t\t\tif [ "$node_type" = "ss-rust" ] || [ "$node_type" = "ss-libev" ]; then\n\t\t\t\ttype="ss"\n\t\t\tfi'
if old_p9a in content:
    content = content.replace(old_p9a, new_p9a)
    print("P9a server norm.: OK")
else:
    errors.append("P9a server norm.")

old_p9b = '\t\t\t\t\telif [ "$node_type" = "ss-rust" ] || [ "$node_type" = "ss" ]; then\n\t\t\t\t\t\tss_program="$(first_type ${type}server)"'
new_p9b = '\t\t\t\t\telif [ "$node_type" = "ss-libev" ]; then\n\t\t\t\t\t\tss_program="$(first_type ss-server)"\n\t\t\t\t\telif [ "$node_type" = "ss-rust" ] || [ "$node_type" = "ss" ]; then\n\t\t\t\t\t\tss_program="$(first_type ${type}server)"'
if old_p9b in content:
    content = content.replace(old_p9b, new_p9b)
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

# Suppress AUTORELEASE deprecation warnings
find feeds -name Makefile -exec sed -i -e 's/PKG_RELEASE:=$(AUTORELEASE)/PKG_RELEASE:=1/g' -e 's/PKG_RELEASE=$(AUTORELEASE)/PKG_RELEASE:=1/g' -e 's/PKG_RELEASE:=AUTORELEASE/PKG_RELEASE:=1/g' {} + 2>/dev/null || true
