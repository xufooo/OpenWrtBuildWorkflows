#!/bin/bash
# Copyright (c) 2022-2023 Curious <https://www.curious.host>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
# 
# https://github.com/Curious-r/OpenWrtBuildWorkflows
#-------------------------------------------------------------------------------------------------------
#
# shadowsocks-libev: patch smpackage's existing Makefile to use v3.3.6

# smpackage already provides shadowsocks-libev. Patch its Makefile in place
# instead of replacing it, to preserve compatibility with the build system.
cd feeds/smpackage/shadowsocks-libev

# Bump version to v3.3.6
sed -i 's/PKG_VERSION:=.*/PKG_VERSION:=3.3.6/' Makefile
sed -i 's/PKG_RELEASE:=.*/PKG_RELEASE:=1/' Makefile

# Update hash to actual v3.3.6 release tarball (confirmed: GitHub release exists)
sed -i 's/PKG_HASH:=.*/PKG_HASH:=ee83b43b36d6a51cfbee72254b6088d4b625feadf06cc2f0bcb810c8236438a5/' Makefile

# Remove any patches (v3.3.6 has native mbedTLS 3.6+ support, no patches needed)
rm -rf patches/ 2>/dev/null || true

# Add autoreconf if not already present (v3.3.6 tarball may need it)
if ! grep -q 'PKG_FIXUP' Makefile; then
  sed -i '/^include \$(INCLUDE_DIR)\/package\.mk/i PKG_FIXUP:=autoreconf' Makefile
fi

cd ../../..

# Suppress AUTORELEASE warnings in third-party feeds
find feeds -name Makefile -exec sed -i -e 's/PKG_RELEASE:=$(AUTORELEASE)/PKG_RELEASE:=1/g' -e 's/PKG_RELEASE:=AUTORELEASE/PKG_RELEASE:=1/g' {} + 2>/dev/null || true
