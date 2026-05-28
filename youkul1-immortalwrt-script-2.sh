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
# 2. Patch SSR Plus Makefile to restore Shadowsocks_Libev_Client (Python for reliability)

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

# --- SSR Plus: add Shadowsocks_Libev_Client using Python ---
python3 << 'PYEOF'
import sys

with open('feeds/smpackage/luci-app-ssr-plus/Makefile', 'r') as f:
    content = f.read()

# 1. PKG_CONFIG_DEPENDS: insert before NONE_Client
content = content.replace(
    'CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_NONE_Client \\',
    'CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client \\\n\tCONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_NONE_Client \\'
)

# 2. LUCI_DEPENDS: insert before Rust_Client:sslocal
content = content.replace(
    '+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client:shadowsocks-rust-sslocal \\',
    '+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client:shadowsocks-libev-ss-local \\\n\t+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client:shadowsocks-libev-ss-redir \\\n\t+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client:shadowsocks-rust-sslocal \\'
)

# 3. Kconfig: insert before Shadowsocks_Rust_Client in Shadowsocks Client choice
content = content.replace(
    '\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client',
    '\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client\n\t\tbool "Shadowsocks Libev"\n\t\tdefault n\n\n\tconfig PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client'
)

with open('feeds/smpackage/luci-app-ssr-plus/Makefile', 'w') as f:
    f.write(content)

print("SSR Plus Makefile patched successfully")
PYEOF

# Suppress AUTORELEASE warnings
find feeds -name Makefile -exec sed -i -e 's/PKG_RELEASE:=\$(AUTORELEASE)/PKG_RELEASE:=1/g' -e 's/PKG_RELEASE:=AUTORELEASE/PKG_RELEASE:=1/g' {} + 2>/dev/null || true
