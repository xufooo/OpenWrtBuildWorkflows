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
# Modify default IP
sed -i 's/192.168.1.1/192.168.1.2/g' package/base-files/files/bin/config_generate

# Modify AdGuardHome default configuration
sed -i 's/\/var\/adguardhome/\/etc\/AdGuardHome/g' feeds/packages/net/adguardhome/files/adguardhome.config
sed -i 's/adguardhome.yaml/AdGuardHome.yaml/g' feeds/packages/net/adguardhome/files/adguardhome.init

# Fix mosdns conflict with luci-app-mosdns
cp feeds/small/luci-app-mosdns/Makefile feeds/packages/net/mosdns/Makefile 
