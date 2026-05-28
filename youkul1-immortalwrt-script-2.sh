#!/bin/bash
# Copyright (c) 2022-2023 Curious <https://www.curious.host>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
# 
# https://github.com/Curious-r/OpenWrtBuildWorkflows
#-------------------------------------------------------------------------------------------------------
#
# shadowsocks-libev: use upstream v3.3.6 with native mbedTLS 3.6+ support
# (no patches needed - upstream fixed private_ field access)

# Get the OpenWrt packaging files (Makefile, init, config) from ImmortalWrt packages
git clone --depth 1 -b openwrt-23.05 https://github.com/immortalwrt/packages.git /tmp/imm-packages
cp -r /tmp/imm-packages/net/shadowsocks-libev package/feeds/packages/shadowsocks-libev
rm -rf /tmp/imm-packages

# Update Makefile to use upstream v3.3.6
cd package/feeds/packages/shadowsocks-libev
sed -i 's/PKG_VERSION:=3.3.5/PKG_VERSION:=3.3.6/' Makefile
sed -i 's/PKG_RELEASE:=11/PKG_RELEASE:=1/' Makefile
sed -i 's|PKG_SOURCE_URL:=https://github.com/shadowsocks/shadowsocks-libev/releases/download/v\$(PKG_VERSION)|PKG_SOURCE_URL:=https://github.com/shadowsocks/shadowsocks-libev/releases/download/v\$(PKG_VERSION)|' Makefile
sed -i 's/PKG_HASH:=cfc8eded35360f4b67e18dc447b0c00cddb29cc57a3cec48b135e5fb87433488/PKG_HASH:=361cb5479a72a32f1defe904a6ab9151dc417e749e7ae5ae97ede295adaa65f4/' Makefile
# Remove old patches (not needed for v3.3.6)
rm -rf patches/

# Suppress AUTORELEASE warnings in third-party feeds
find ../../feeds/smpackage -name Makefile -exec sed -i 's/PKG_RELEASE:=AUTORELEASE/PKG_RELEASE:=1/g' {} + 2>/dev/null || true
