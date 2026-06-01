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

# =============================================================================
# PATCH SET: Enable ss-libev (shadowsocks-libev) as a native node type in SSR Plus
#
# Background: SSR Plus originally only supports ss-rust for shadowsocks.
# ss-libev uses different binaries (ss-redir, ss-local) and a different UDP
# proxy mechanism (REDIRECT) than ss-rust (TPROXY). This patch set adds
# full ss-libev support including TCP transparent proxy, UDP REDIRECT,
# auto-detection, and persistence across reboots/table-reloads.
#
# Patches 1-5:   Type normalization - map ss-libev to internal "ss" type
# Patches 6-9:   Binary routing - use ss-redir/ss-local instead of ss-rust
# Patches 10-10c: UDP handling - REDIRECT-based UDP proxy with persistence
# =============================================================================
init_path = f'{base}/root/etc/init.d/shadowsocksr'
with open(init_path, 'r') as f:
    content = f.read()

# PATCH 1: Auto-detect ss-libev binaries at boot
# Insert ss-redir+ss-local check BEFORE the existing sslocal->ss-rust fallback.
# Without this, nodes default to ss-rust even when ss-libev binaries exist.
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

# PATCH 2-5: Type normalization (ss-libev -> "ss")
# SSR Plus internally normalizes ss-rust->"ss" for binary routing. Extend
# each normalization point to also handle ss-libev->"ss", so ss-libev
# nodes flow through the same code paths as ss-rust for TCP/SOCKS.
old = '\tif [ "$udp_relay_server_type" = "ss-rust" ]; then\n\t\ttype="ss"\n\tfi'
new = '\tif [ "$udp_relay_server_type" = "ss-rust" ] || [ "$udp_relay_server_type" = "ss-libev" ]; then\n\t\ttype="ss"\n\tfi'
if old in content:
    content = content.replace(old, new)
    print("init: UDP normalization patched")
else: print("WARNING: UDP normalization NOT found")


old = '\tif [ "$local_server_type" = "ss-rust" ]; then\n\t\ttype="ss"\n\tfi'
new = '\tif [ "$local_server_type" = "ss-rust" ] || [ "$local_server_type" = "ss-libev" ]; then\n\t\ttype="ss"\n\tfi'
if old in content:
    content = content.replace(old, new)
    print("init: SOCKS normalization patched")
else: print("WARNING: SOCKS normalization NOT found")


old = '\tif [ "$global_server_type" = "ss-rust" ]; then\n\t\ttype="ss"\n\tfi'
new = '\tif [ "$global_server_type" = "ss-rust" ] || [ "$global_server_type" = "ss-libev" ]; then\n\t\ttype="ss"\n\tfi'
if old in content:
    content = content.replace(old, new)
    print("init: TCP normalization patched")
else: print("WARNING: TCP normalization NOT found")


old = '\t\t\tif [ "$node_type" = "ss-rust" ]; then\n\t\t\t\ttype="ss"\n\t\t\tfi'
new = '\t\t\tif [ "$node_type" = "ss-rust" ] || [ "$node_type" = "ss-libev" ]; then\n\t\t\t\ttype="ss"\n\t\t\tfi'
if old in content:
    content = content.replace(old, new)
    print("init: Server normalization patched")
else: print("WARNING: Server normalization NOT found")

# PATCH 6: UDP relay binary - use ss-redir for ss-libev
# ss-libev UDP relay uses ss-redir directly (not sslocal-based like ss-rust).
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

# PATCH 7: TCP transparent proxy binary - use ss-redir for ss-libev
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

# PATCH 8: SOCKS proxy binary - use ss-local for ss-libev
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

# PATCH 9: Server-side binary selection includes ss-libev
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

# =============================================================================
# PATCHES 10-10c: UDP transparent proxy for ss-libev
#
# CRITICAL: ss-libev uses REDIRECT for UDP, NOT TPROXY like ss-rust.
# ss-rust needs ipt2socks + separate UDP listener for TPROXY. ss-libev
# handles UDP natively via ss-redir -u - we just REDIRECT UDP packets to
# the same ss-redir port (1234) that handles TCP. ssr-rules only knows
# TPROXY, so we bypass its UDP handling and add REDIRECT rules manually.
#
# Patch 10:  get_udp_relay_mode() returns "sslibev" (custom mode)
# Patch 10b: sslibev case - redir_udp=0, ARG_UDP="", ARG_UDP_RULES="-y"
#            (no TPROXY setup, no UDP block rules from ssr-rules)
# Patch 10c: After ssr-rules, add nft REDIRECT for UDP + update persist
#            file so rules survive reboots and table reloads
# =============================================================================
	print("init: udp_mode sslibev case added (no TPROXY, REDIRECT handled separately)")
else: print("WARNING: udp_mode split NOT found")



old3 = '\t\treturn $?\n\t}'
new3 = '\t\tlocal ret=$?\n\t\tif [ "$(uci_get_by_name $GLOBAL_SERVER type)" = "ss-libev" ]; then\n\t\t\tlocal ports="22,53,80,143,443,465,587,853,993,995,9418"\n\t\t\tnft list chain inet ss_spec ss_spec_wan_fw 2>/dev/null | grep -q 'udp.*redirect' || nft add rule inet ss_spec ss_spec_wan_fw meta l4proto udp udp dport { $ports } counter redirect to :$local_port 2>/dev/null\n\t\t\t# UDP server bypass (mirrors TCP bypass in wan_ac; ssr-rules guards this with [ -n "$server" ])\n\t\t\t[ -n "$server" ] && nft add rule inet ss_spec ss_spec_prerouting iifname "br-lan" meta l4proto udp udp dport != 53 ip daddr "$server" return 2>/dev/null\n\t\t\tnft list chain inet ss_spec ss_spec_prerouting 2>/dev/null | grep -q 'udp.*jump ss_spec_wan_ac' || nft add rule inet ss_spec ss_spec_prerouting iifname "br-lan" meta l4proto udp udp dport { $ports } jump ss_spec_wan_ac comment "_SS_SPEC_RULE_" 2>/dev/null\n\t\t# also handle OUTPUT chain for router-local DNS queries\n\t\tnft add rule inet ss_spec ss_spec_output meta l4proto udp udp dport { $ports } jump ss_spec_wan_ac comment "_SS_SPEC_RULE_" 2>/dev/null\n\t\t\tnft list table inet ss_spec > /usr/share/nftables.d/ruleset-post/99-shadowsocksr.nft 2>/dev/null\n\t\tfi\n\t\treturn $ret\n\t}'
if old3 in content:
	content = content.replace(old3, new3)
	print("init: start_rules UDP REDIRECT for ss-libev added")
else: print("WARNING: start_rules return not found")

with open(init_path, 'w') as f:
    f.write(content)
print("SSR Plus init script: done")
PYEOF


# Patch gen_config.lua: handle ss-libev type
sed -i 's/if server.type == "ss-rust" then/if server.type == "ss-rust" or server.type == "ss-libev" then/' feeds/smpackage/luci-app-ssr-plus/root/usr/share/shadowsocksr/gen_config.lua
echo "gen_config.lua: ss-libev type mapping added"


# Patch init script display: distinguish ss-libev from ss-rust
sed -i '/echolog "Main node:Shadowsocks-rust Started!"/c\                        if [ "$global_server_type" = "ss-libev" ]; then\n                                echolog "Main node:Shadowsocks Libev Started!"\n                        else\n                                echolog "Main node:Shadowsocks-rust Started!"\n                        fi' feeds/smpackage/luci-app-ssr-plus/root/etc/init.d/shadowsocksr

sed -i '/echolog "Global_Socks5:Shadowsocks-rust Started!"/c\                if [ "$local_server_type" = "ss-libev" ]; then\n                                echolog "Global_Socks5:Shadowsocks Libev Started!"\n                        else\n                                echolog "Global_Socks5:Shadowsocks-rust Started!"\n                        fi' feeds/smpackage/luci-app-ssr-plus/root/etc/init.d/shadowsocksr
echo "init: display name patched (ss-libev)"

# Add -u flag to TCP binary launch for ss-libev UDP support
sed -i '/ln_start_bin \$ss_program \${type}-redir -c \$tcp_config_file/s/-c/-u -c/' feeds/smpackage/luci-app-ssr-plus/root/etc/init.d/shadowsocksr
echo "init: -u flag added for ss-libev"


# Suppress AUTORELEASE deprecation warnings
find feeds -name Makefile -exec sed -i -e 's/PKG_RELEASE:=$(AUTORELEASE)/PKG_RELEASE:=1/g' -e 's/PKG_RELEASE=$(AUTORELEASE)/PKG_RELEASE:=1/g' -e 's/PKG_RELEASE:=AUTORELEASE/PKG_RELEASE:=1/g' {} + 2>/dev/null || true
