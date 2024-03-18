#!/bin/bash
# Copyright (c) 2022-2023 Curious <https://www.curious.host>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
# 
# https://github.com/Curious-r/OpenWrtBuildWorkflows
# Description: Automatically check OpenWrt source code update and build it. No additional keys are required.
#-------------------------------------------------------------------------------------------------------
#
#
# Patching is generally recommended.
# # Here's a template for patching:
#touch example.patch
#cat>example.patch<<EOF
#patch content
#EOF
#git apply example.patch
# sfe patch
wget https://github.com/lede-project/source/commit/b87b4734c6e56fa45ec612350e2aa480ed2d8dd6.patch
sed -i "s/hack-4.4/patches-4.4/g" b87b4734c6e56fa45ec612350e2aa480ed2d8dd6.patch
touch target/linux/generic/config-4.9
patch -p1 < b87b4734c6e56fa45ec612350e2aa480ed2d8dd6.patch

# luci-app-sfe
cp -r wnr2000v4/luci-app-sfe package

# m4 compile error patch
#wget https://raw.githubusercontent.com/keyfour/openwrt/2722d51c5cf6a296b8ecf7ae09e46690403a6c3d/tools/m4/patches/011-fix-sigstksz.patch
#mv 011-fix-sigstksz.patch tools/m4/patches

# mklib compile error patch
#wget https://scm.linefinity.com/common/openwrt/commit/a1ee0ebbd8e9927a65c5d1e0db497dd118d559a6.patch
#patch -p1 < a1ee0ebbd8e9927a65c5d1e0db497dd118d559a6.patch

# cmake compile error patch
#touch limits.patch
#cat>limits.patch<<EOF
#--- a/Source/cmStandardIncludes.h
#+++ b/Source/cmStandardIncludes.h
#@@ -27,2 +27,3 @@
# #include <vector>
#+#include <limits>
#EOF
#mv limits.patch tools/cmake/patches
