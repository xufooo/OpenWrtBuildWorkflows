#!/bin/bash
# Copyright (c) 2022-2023 Curious <https://www.curious.host>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
# 
# https://github.com/Curious-r/OpenWrtBuildWorkflows
#-------------------------------------------------------------------------------------------------------
#
# shadowsocks-libev v3.3.6: switched from autotools to CMake build system
# v3.3.6 uses CMakeLists.txt; the old autotools.mk approach cannot work.

cd feeds/smpackage/shadowsocks-libev

# 1. Bump version and release
sed -i 's/PKG_VERSION:=.*/PKG_VERSION:=3.3.6/' Makefile
sed -i 's/PKG_RELEASE:=.*/PKG_RELEASE:=1/' Makefile

# 2. Update hash (verified: GitHub release v3.3.6, 321KB)
if grep -q 'PKG_HASH:=' Makefile; then
  sed -i 's/PKG_HASH:=.*/PKG_HASH:=ee83b43b36d6a51cfbee72254b6088d4b625feadf06cc2f0bcb810c8236438a5/' Makefile
else
  sed -i '/PKG_SOURCE_URL/a PKG_HASH:=ee83b43b36d6a51cfbee72254b6088d4b625feadf06cc2f0bcb810c8236438a5' Makefile
fi

# 3. Switch from autotools.mk to cmake.mk
sed -i 's|include \$(INCLUDE_DIR)/autotools.mk|include \$(INCLUDE_DIR)/cmake.mk|' Makefile

# 4. Strip old autotools CONFIGURE_ARGS (--with-xxx format incompatible with cmake)
#    and add proper CMAKE_OPTIONS
sed -i '/^CONFIGURE_ARGS/d' Makefile

# 5. Add cmake build options (dependencies auto-detected via pkg-config)
sed -i '/include \$(INCLUDE_DIR)\/cmake\.mk/a CMAKE_OPTIONS += -DWITH_STATIC=ON -DWITH_EMBEDDED_SRC=ON' Makefile

# 6. Remove old patches (v3.3.6 has native mbedTLS 3.6+ support)
rm -rf patches/ 2>/dev/null || true

cd ../../..

# Suppress AUTORELEASE warnings in third-party feeds
find feeds -name Makefile -exec sed -i -e 's/PKG_RELEASE:=$(AUTORELEASE)/PKG_RELEASE:=1/g' -e 's/PKG_RELEASE:=AUTORELEASE/PKG_RELEASE:=1/g' {} + 2>/dev/null || true
