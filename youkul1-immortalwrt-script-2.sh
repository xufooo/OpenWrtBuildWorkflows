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
# 2. Patch SSR Plus: Makefile Kconfig + client-config.lua type dropdown
# 3. Patch SSR Plus init script for native ss-libev binary routing (no symlink)

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

# --- SSR Plus: patch Makefile + client-config.lua + init script ---
python3 << 'PYEOF'
import sys, os

base = 'feeds/smpackage/luci-app-ssr-plus'

# === Patch SSR Plus Makefile (Kconfig) ===
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

content = content.replace(
    '\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client',
    '\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client\n\t\tbool "Shadowsocks Libev"\n\t\tdefault n\n\n\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client'
)

with open(f'{base}/Makefile', 'w') as f:
    f.write(content)
print("SSR Plus Makefile: done")

# === Patch client-config.lua (node type dropdown + depends) ===
with open(f'{base}/luasrc/model/cbi/shadowsocksr/client-config.lua', 'r') as f:
    content = f.read()

# 1. Add has_ss_libev detection (independent of has_ss_rust)
content = content.replace(
    'local has_ss_rust = is_finded("sslocal") or is_finded("ssserver")',
    'local has_ss_rust = is_finded("sslocal") or is_finded("ssserver")\nlocal has_ss_libev = is_finded("ss-redir") or is_finded("ss-local")'
)

# 2. Add ss-libev as independent block (NOT inside has_ss_rust)
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

# 3. Add ss-libev to all depends chains
content = content.replace(
    'o:depends("type", "ss-rust")',
    'o:depends("type", "ss-rust")\n\to:depends("type", "ss-libev")'
)

with open(f'{base}/luasrc/model/cbi/shadowsocksr/client-config.lua', 'w') as f:
    f.write(content)
print("SSR Plus client-config.lua: done")

# === Patch init script for native ss-libev binary routing ===
init_path = f'{base}/root/etc/init.d/shadowsocksr'
with open(init_path, 'r') as f:
    content = f.read()

# 1. Detection: add ss-redir+ss-local check BEFORE sslocal check
old_detect = (
    '\t\t\telif [ -n "$(first_type sslocal)" ]; then\n'
    '\t\t\t\tuci -q set "$NAME.$section.type=ss-rust"\n'
    '\t\t\t\tchanged=1'
)
new_detect = (
    '\t\t\telif [ -n "$(first_type ss-redir)" ] && [ -n "$(first_type ss-local)" ]; then\n'
    '\t\t\t\t[ "$type" != "ss-libev" ] && { uci -q set "$NAME.$section.type=ss-libev"; changed=1; }\n'
    '\t\t\telif [ -n "$(first_type sslocal)" ]; then\n'
    '\t\t\t\tuci -q set "$NAME.$section.type=ss-rust"\n'
    '\t\t\t\tchanged=1'
)
if old_detect in content:
    content = content.replace(old_detect, new_detect)
    print("init: detection block patched")
else:
    print("WARNING: detection block NOT found")

# 2. UDP normalization
old = '\tif [ "$udp_relay_server_type" = "ss-rust" ]; then\n\t\ttype="ss"\n\tfi'
new = '\tif [ "$udp_relay_server_type" = "ss-rust" ] || [ "$udp_relay_server_type" = "ss-libev" ]; then\n\t\ttype="ss"\n\tfi'
if old in content:
    content = content.replace(old, new)
    print("init: UDP normalization patched")
else: print("WARNING: UDP normalization NOT found")

# 3. SOCKS normalization
old = '\tif [ "$local_server_type" = "ss-rust" ]; then\n\t\ttype="ss"\n\tfi'
new = '\tif [ "$local_server_type" = "ss-rust" ] || [ "$local_server_type" = "ss-libev" ]; then\n\t\ttype="ss"\n\tfi'
if old in content:
    content = content.replace(old, new)
    print("init: SOCKS normalization patched")
else: print("WARNING: SOCKS normalization NOT found")

# 4. TCP normalization
old = '\tif [ "$global_server_type" = "ss-rust" ]; then\n\t\ttype="ss"\n\tfi'
new = '\tif [ "$global_server_type" = "ss-rust" ] || [ "$global_server_type" = "ss-libev" ]; then\n\t\ttype="ss"\n\tfi'
if old in content:
    content = content.replace(old, new)
    print("init: TCP normalization patched")
else: print("WARNING: TCP normalization NOT found")

# 5. Server normalization
old = '\t\t\tif [ "$node_type" = "ss-rust" ]; then\n\t\t\t\ttype="ss"\n\t\t\tfi'
new = '\t\t\tif [ "$node_type" = "ss-rust" ] || [ "$node_type" = "ss-libev" ]; then\n\t\t\t\ttype="ss"\n\t\t\tfi'
if old in content:
    content = content.replace(old, new)
    print("init: Server normalization patched")
else: print("WARNING: Server normalization NOT found")

# 6. UDP binary: split ss-libev into own branch using ss-redir directly
old_udp_bin = (
    '\t\t\telif [ "$udp_relay_server_type" = "ss-rust" ]'
    ' || [ "$udp_relay_server_type" = "ss" ]; then\n'
    '\t\t\t\tss_program="$(first_type ${type}local)"'
)
new_udp_bin = (
    '\t\t\telif [ "$udp_relay_server_type" = "ss-libev" ]; then\n'
    '\t\t\t\tss_program="$(first_type ss-redir)"\n'
    '\t\t\telif [ "$udp_relay_server_type" = "ss-rust" ]'
    ' || [ "$udp_relay_server_type" = "ss" ]; then\n'
    '\t\t\t\tss_program="$(first_type ${type}local)"'
)
if old_udp_bin in content:
    content = content.replace(old_udp_bin, new_udp_bin)
    print("init: UDP binary split for ss-libev")
else: print("WARNING: UDP binary block NOT found")

# 7. TCP binary: use ss-redir when type is ss-libev
old_tcp = (
    '\t\telse\n'
    '\t\t\tgen_config_file $GLOBAL_SERVER $type 1 $tcp_port\n'
    '\t\t\tss_program="$(first_type sslocal)"'
)
new_tcp = (
    '\t\telse\n'
    '\t\t\tgen_config_file $GLOBAL_SERVER $type 1 $tcp_port\n'
    '\t\t\tif [ "$global_server_type" = "ss-libev" ]; then\n'
    '\t\t\t\tss_program="$(first_type ss-redir)"\n'
    '\t\t\telse\n'
    '\t\t\t\tss_program="$(first_type sslocal)"\n'
    '\t\t\tfi'
)
if old_tcp in content:
    content = content.replace(old_tcp, new_tcp)
    print("init: TCP binary patched for ss-libev")
else: print("WARNING: TCP binary block NOT found")

# 8. SOCKS binary: use ss-local when type is ss-libev
old_socks = (
    '\t\telse\n'
    '\t\t\tgen_config_file $LOCAL_SERVER $type 4 $local_port\n'
    '\t\t\tss_program="$(first_type sslocal)"'
)
new_socks = (
    '\t\telse\n'
    '\t\t\tgen_config_file $LOCAL_SERVER $type 4 $local_port\n'
    '\t\t\tif [ "$local_server_type" = "ss-libev" ]; then\n'
    '\t\t\t\tss_program="$(first_type ss-local)"\n'
    '\t\t\telse\n'
    '\t\t\t\tss_program="$(first_type sslocal)"\n'
    '\t\t\tfi'
)
if old_socks in content:
    content = content.replace(old_socks, new_socks)
    print("init: SOCKS binary patched for ss-libev")
else: print("WARNING: SOCKS binary block NOT found")

# 9. Server binary selection
old = (
    '\t\t\t\t\telif [ "$node_type" = "ss-rust" ]'
    ' || [ "$node_type" = "ss" ]; then'
)
new = (
    '\t\t\t\t\telif [ "$node_type" = "ss-rust" ]'
    ' || [ "$node_type" = "ss" ]'
    ' || [ "$node_type" = "ss-libev" ]; then'
)
if old in content:
    content = content.replace(old, new)
    print("init: Server binary selection patched")
else: print("WARNING: Server binary selection NOT found")

# 10. get_udp_relay_mode: add ss-libev with custom sslibev mode.
# This keeps the main-branch magic route: ss-redir runs with -u, ssr-rules
# does not create native UDP TPROXY rules, then start_rules adds nft REDIRECT.
old = '\tclash|tuic)'
new = '\tss-libev)\n\t\techo "sslibev"\n\t\t;;\n\tclash|tuic)'
if old in content:
	content = content.replace(old, new)
	print("init: get_udp_relay_mode: ss-libev -> sslibev")
else: print("WARNING: get_udp_relay_mode clash|tuic NOT found")

# 10b. Add sslibev case in main udp_mode switch.
old2 = '\tsplit)\n\t\tmode="udp"'
new2 = '\tsslibev)\n\t\tmode="tcp,udp"\n\t\ttcp_config_file=$TMP_PATH/tcp-udp-ssr-retcp.json\n\t\tredir_udp=0\n\t\tARG_UDP=""\n\t\tARG_UDP_RULES="-y"\n\t\t;;\n\tsplit)\n\t\tmode="udp"'
if old2 in content:
	content = content.replace(old2, new2)
	print("init: udp_mode sslibev case added (manual UDP REDIRECT)")
else: print("WARNING: udp_mode split NOT found")

# 10c. In start_rules(): after ssr-rules, add UDP REDIRECT for ss-libev.
old3 = '\t\treturn $?\n\t}'
new3 = '''\t\tlocal ret=$?
\t\tif [ "$(uci_get_by_name $GLOBAL_SERVER type)" = "ss-libev" ]; then
\t\t\tlocal ports="22,53,80,143,443,465,587,853,993,995,9418"
\t\t\tnft list chain inet ss_spec ss_spec_wan_fw 2>/dev/null | grep -q 'udp.*redirect' || nft add rule inet ss_spec ss_spec_wan_fw meta l4proto udp udp dport { $ports } counter redirect to :$local_port 2>/dev/null
\t\t\t# UDP server bypass (mirrors TCP bypass in wan_ac; ssr-rules guards this with [ -n "$server" ])
\t\t\t[ -n "$server" ] && nft add rule inet ss_spec ss_spec_prerouting iifname "br-lan" meta l4proto udp udp dport != 53 ip daddr "$server" return 2>/dev/null
\t\t\tnft list chain inet ss_spec ss_spec_prerouting 2>/dev/null | grep -q 'udp.*jump ss_spec_wan_ac' || nft add rule inet ss_spec ss_spec_prerouting iifname "br-lan" meta l4proto udp udp dport { $ports } jump ss_spec_wan_ac comment "_SS_SPEC_RULE_" 2>/dev/null
\t\t\t# also handle OUTPUT chain for router-local DNS queries
\t\t\tnft add rule inet ss_spec ss_spec_output meta l4proto udp udp dport { $ports } jump ss_spec_wan_ac comment "_SS_SPEC_RULE_" 2>/dev/null
\t\t\tnft list table inet ss_spec > /usr/share/nftables.d/ruleset-post/99-shadowsocksr.nft 2>/dev/null
\t\tfi
\t\treturn $ret
\t}'''
if old3 in content:
	content = content.replace(old3, new3)
	print("init: start_rules UDP REDIRECT for ss-libev added")
else: print("WARNING: start_rules return not found")

# 11. Start ss-libev ss-redir with UDP enabled, without touching ssr-redir.
old = (
    '\t\t\tln_start_bin $ss_program ${type}-redir -c $tcp_config_file\n'
    '\t\t\techolog "Main node:Shadowsocks-rust Started!"'
)
new = (
    '\t\t\tif [ "$global_server_type" = "ss-libev" ]; then\n'
    '\t\t\t\tln_start_bin $ss_program ${type}-redir -u -c $tcp_config_file\n'
    '\t\t\t\techolog "Main node:Shadowsocks Libev Started!"\n'
    '\t\t\telse\n'
    '\t\t\t\tln_start_bin $ss_program ${type}-redir -c $tcp_config_file\n'
    '\t\t\t\techolog "Main node:Shadowsocks-rust Started!"\n'
    '\t\t\tfi'
)
if old in content:
    content = content.replace(old, new)
    print("init: ss-libev TCP/UDP start command patched")
else: print("WARNING: ss-libev start command block NOT found")

# 12. Display ss-libev name for global SOCKS5 mode.
old = (
    '\t\t\tln_start_bin $ss_program ${type}-local -c $local_config_file\n'
    '\t\t\techolog "Global_Socks5:Shadowsocks-rust Started!"'
)
new = (
    '\t\t\tln_start_bin $ss_program ${type}-local -c $local_config_file\n'
    '\t\t\tif [ "$local_server_type" = "ss-libev" ]; then\n'
    '\t\t\t\techolog "Global_Socks5:Shadowsocks Libev Started!"\n'
    '\t\t\telse\n'
    '\t\t\t\techolog "Global_Socks5:Shadowsocks-rust Started!"\n'
    '\t\t\tfi'
)
if old in content:
    content = content.replace(old, new)
    print("init: SOCKS display name patched for ss-libev")
else: print("WARNING: SOCKS display name block NOT found")

with open(init_path, 'w') as f:
    f.write(content)
print("SSR Plus init script: done")

# Patch gen_config.lua: handle ss-libev type
gen_config_path = f'{base}/root/usr/share/shadowsocksr/gen_config.lua'
with open(gen_config_path, 'r') as f:
    content = f.read()

old = 'if server.type == "ss-rust" then'
new = 'if server.type == "ss-rust" or server.type == "ss-libev" then'
if old in content:
    content = content.replace(old, new, 1)
    print("gen_config.lua: ss-libev type mapping added")
elif new in content:
    print("gen_config.lua: ss-libev type mapping already present")
else:
    print("WARNING: gen_config.lua ss-rust type mapping NOT found")

with open(gen_config_path, 'w') as f:
    f.write(content)
PYEOF

# Suppress AUTORELEASE deprecation warnings
find feeds -name Makefile -exec sed -i -e 's/PKG_RELEASE:=$(AUTORELEASE)/PKG_RELEASE:=1/g' -e 's/PKG_RELEASE=$(AUTORELEASE)/PKG_RELEASE:=1/g' -e 's/PKG_RELEASE:=AUTORELEASE/PKG_RELEASE:=1/g' {} + 2>/dev/null || true
