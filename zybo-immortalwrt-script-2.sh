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

# Fix mosdns conflict with luci-app-mosdns (small-package vs official feed)
cp feeds/smpackage/mosdns/Makefile feeds/packages/net/mosdns/Makefile

# Use ImmortalWrt luci's adguardhome (lowercase, matching init), drop small-package's (uppercase mismatch)
rm -rf feeds/smpackage/luci-app-adguardhome

rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang

# Fix mosdns init: mosdns v5 dropped adblock_set, must use domain_set
sed -i 's/"adblock_set"/"domain_set"/g' feeds/smpackage/luci-app-mosdns/root/etc/init.d/mosdns

# Fix smartdns LuCI: Promise.all wrapper makes array always truthy -> always shows RUNNING
sed -i 's/return Promise.all(\[getServiceStatus()\]);/return getServiceStatus();/' feeds/luci/applications/luci-app-smartdns/htdocs/luci-static/resources/view/smartdns/smartdns.js
