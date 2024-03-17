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
cp -r ../wnr2000v4/luci-app-sfe package
