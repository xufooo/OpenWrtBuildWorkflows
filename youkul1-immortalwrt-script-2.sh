#!/bin/bash
# Copyright (c) 2022-2023 Curious <https://www.curious.host>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
# 
# https://github.com/Curious-r/OpenWrtBuildWorkflows
#-------------------------------------------------------------------------------------------------------
#
# 1. Add stub shadowsocks-libev-config package + sslocal symlink
# 2. Patch SSR Plus: Makefile Kconfig + client-config.lua type dropdown

# --- shadowsocks-libev: config stub + sslocal symlink ---
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

sed -i '/Package\/shadowsocks-libev-ss-redir\/install/{n;/\$(INSTALL_BIN)/a\\t\$(LN) ss-redir \$(1)/usr/bin/sslocal
}' Makefile

cd ../../..

# --- SSR Plus: patch Makefile + client-config.lua ---
python3 << 'PYEOF'
import sys, os

# === Patch SSR Plus Makefile (Kconfig) ===
base = 'feeds/smpackage/luci-app-ssr-plus'
with open(f'{base}/Makefile', 'r') as f:
    content = f.read()

content = content.replace(
    'CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_NONE_Client \\',
    'CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client \\\n\tCONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_NONE_Client \\'
)

content = content.replace(
    '+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client:shadowsocks-rust-sslocal \\',
    '+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client:shadowsocks-libev-ss-local \\\n\t+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client:shadowsocks-libev-ss-redir \\\n\t+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client:shadowsocks-rust-sslocal \\'
)

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

# Add ss-libev to type dropdown (after ss-rust)
content = content.replace(
    '\to:value("ss-rust", translate("ShadowSocks"))',
    '\to:value("ss-rust", translate("ShadowSocks"))\n\to:value("ss-libev", translate("ShadowSocks Libev"))'
)

# Add ss-libev to all depends chains that have both "ss" and "ss-rust"
# Pattern: o:depends("type", "ss-rust") → add ss-libev right after
content = content.replace(
    'o:depends("type", "ss-rust")',
    'o:depends("type", "ss-rust")\n\to:depends("type", "ss-libev")'
)

with open(f'{base}/luasrc/model/cbi/shadowsocksr/client-config.lua', 'w') as f:
    f.write(content)
print("SSR Plus client-config.lua: done")
PYEOF

# Suppress AUTORELEASE warnings
find feeds -name Makefile -exec sed -i -e 's/PKG_RELEASE:=\$(AUTORELEASE)/PKG_RELEASE:=1/g' -e 's/PKG_RELEASE:=AUTORELEASE/PKG_RELEASE:=1/g' {} + 2>/dev/null || true
