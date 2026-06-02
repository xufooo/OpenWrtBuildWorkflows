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
# proxy mechanism than ss-rust (TPROXY for both). This patch set adds
# full ss-libev support including TCP transparent proxy, UDP TPROXY,
# auto-detection, and persistence across reboots/table-reloads.
#
# Patches 1-5:   Type normalization - map ss-libev to internal "ss" type
# Patches 6-9:   Binary routing - use ss-redir/ss-local instead of ss-rust
# Patch 10:      UDP handling - TPROXY-based (reuses ss-rust native path)
# =============================================================================
init_path = f'{base}/root/etc/init.d/shadowsocksr'
with open(init_path, 'r') as f:
    content = f.read()

# PATCH 1: Auto-detect ss-libev binaries at boot
# Insert ss-redir+ss-local check BEFORE the existing sslocal->ss-rust fallback.
# Without this, nodes default to ss-rust even when ss-libev binaries exist.
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
# PATCH 10: UDP TPROXY for ss-libev (no extra rules needed)
#
# ss-libev's ss-redir -u supports TPROXY natively via IP_TRANSPARENT (see
# udprelay.c:528).  ssr-rules TPROXY=1 mode uses -s/-l for SERVER/LOCAL_PORT
# which matches ss-redir's unified TCP+UDP listener on port 1234.
#
# The existing ss-rust "native" path handles everything:
#   type="ss" -> get_udp_relay_mode returns "native" -> ARG_UDP="-u"
#   -> ssr-rules -u -> TPROXY=1 -> mangle TPROXY rules -> ss-redir port
#   -> ss-redir receives via IP_TRANSPARENT
#
# No ipt2socks needed. No REDIRECT rules needed. Zero code changes.
# =============================================================================
old = '\t[ "$type" = "ss-rust" ] && type="ss"'
new = '\tif [ "$type" = "ss-rust" ] || [ "$type" = "ss-libev" ]; then\n\t\ttype="ss"\n\tfi'
if old in content:
    content = content.replace(old, new)
    print("init: get_udp_relay_mode: ss-libev -> native ss TPROXY")
else:
    print("WARNING: get_udp_relay_mode ss-rust normalization NOT found")

# PATCH 11: Start ss-libev ss-redir with UDP enabled, without touching ssr-redir.
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
else:
    print("WARNING: ss-libev start command block NOT found")

# PATCH 12: Display ss-libev name for global SOCKS5 mode.
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
else:
    print("WARNING: SOCKS display name block NOT found")

# PATCH 13: Skip separate UDP relay start for ss-libev (ss-redir -u handles both).
old = (
    '\t\t\tln_start_bin $ss_program ${type}-redir -c $udp_config_file\n'
    '\t\t\techolog "UDP TPROXY Relay:$(get_name $type) Started!"'
)
new = (
    '\t\t\tif [ "$udp_relay_server_type" != "ss-libev" ]; then\n'
    '\t\t\t\tln_start_bin $ss_program ${type}-redir -c $udp_config_file\n'
    '\t\t\t\techolog "UDP TPROXY Relay:$(get_name $type) Started!"\n'
    '\t\t\tfi'
)
if old in content:
    content = content.replace(old, new)
    print("init: ss-libev skip separate UDP relay start")
else:
        print("WARNING: UDP relay start block NOT found")

# PATCH 14: Fix TPROXY UDP port for ss-libev (use TCP port, not tmp_udp_port 301).
# ss-rust runs sslocal on port 301 for UDP; ss-libev's ss-redir -u handles both on same port.
old = '\t\tlocal udp_local_port=$tmp_udp_port'
new = '\t\tif [ "$(uci_get_by_name $GLOBAL_SERVER type)" = "ss-libev" ]; then\n\t\t\tlocal udp_local_port=$local_port\n\t\telse\n\t\t\tlocal udp_local_port=$tmp_udp_port\n\t\tfi'
if old in content:
    content = content.replace(old, new)
    print("init: TPROXY UDP port fixed for ss-libev (shared port)")
else:
    print("WARNING: udp_local_port assignment NOT found")

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
