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

# add fullcone nat
mkdir -p package/network/config/firewall/patches
wget -O package/network/config/firewall/patches/fullconenat.patch https://raw.githubusercontent.com/LGA1150/fullconenat-fw3-patch/e66be7fbac970f5b05aff6ddf1499e717534c1af/fullconenat.patch
wget -O- https://raw.githubusercontent.com/LGA1150/fullconenat-fw3-patch/e66be7fbac970f5b05aff6ddf1499e717534c1af/Makefile.patch | patch -p1
pushd feeds/luci
wget -O- https://raw.githubusercontent.com/LGA1150/fullconenat-fw3-patch/e66be7fbac970f5b05aff6ddf1499e717534c1af/luci.patch | patch -p1
popd
