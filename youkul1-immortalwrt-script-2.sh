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
# 2. Create sslocal -> ss-redir symlink (SSR Plus init script hardcodes sslocal binary)
# 3. Patch SSR Plus Kconfig to add Shadowsocks_Libev_Client option

# --- shadowsocks-libev: add config stub + sslocal symlink ---
cd feeds/smpackage/shadowsocks-libev

# Add stub config package
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

# Add sslocal -> ss-redir symlink to ss-redir install step
sed -i '/Package\/shadowsocks-libev-ss-redir\/install/{n;/\$(INSTALL_BIN)/a\\t\$(LN) ss-redir \$(1)/usr/bin/sslocal
}' Makefile

cd ../../..

# --- SSR Plus: add Shadowsocks_Libev_Client to Kconfig ---
cd feeds/smpackage/luci-app-ssr-plus

# Add to PKG_CONFIG_DEPENDS
sed -i '/INCLUDE_Shadowsocks_NONE_Client/i\\tCONFIG_PACKAGE_\$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client \\' Makefile

# Add to LUCI_DEPENDS
sed -i '/INCLUDE_Shadowsocks_Rust_Client:shadowsocks-rust-sslocal/i\\t+PACKAGE_\$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client:shadowsocks-libev-ss-local \\\n\t+PACKAGE_\$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client:shadowsocks-libev-ss-redir \\' Makefile

# Add Kconfig option before Shadowsocks_Rust_Client
sed -i '/config PACKAGE_\$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client/i\\tconfig PACKAGE_\$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client\n\t\tbool "Shadowsocks Libev"\n\t\tdefault n\n' Makefile

cd ../../..

# Suppress AUTORELEASE warnings
find feeds -name Makefile -exec sed -i -e 's/PKG_RELEASE:=\$(AUTORELEASE)/PKG_RELEASE:=1/g' -e 's/PKG_RELEASE:=AUTORELEASE/PKG_RELEASE:=1/g' {} + 2>/dev/null || true
