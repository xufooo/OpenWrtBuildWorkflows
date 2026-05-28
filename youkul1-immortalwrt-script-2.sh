#!/bin/bash
# Copyright (c) 2022-2023 Curious <https://www.curious.host>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
# 
# https://github.com/Curious-r/OpenWrtBuildWorkflows
#-------------------------------------------------------------------------------------------------------
#
# smpackage already provides shadowsocks-libev v3.3.6 with cmake.mk.
# Only addition: stub config package so SSR Plus can detect libev.

cd feeds/smpackage/shadowsocks-libev

# Add a minimal shadowsocks-libev-config package (SSR Plus depends on it)
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

# Suppress AUTORELEASE warnings in third-party feeds
find feeds -name Makefile -exec sed -i -e 's/PKG_RELEASE:=$(AUTORELEASE)/PKG_RELEASE:=1/g' -e 's/PKG_RELEASE:=AUTORELEASE/PKG_RELEASE:=1/g' {} + 2>/dev/null || true
