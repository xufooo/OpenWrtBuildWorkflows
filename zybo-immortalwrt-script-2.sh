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

# Replace official mosdns with sbwml's fork (Makefile + full patches incl. adblock_set)
# sbwml/luci-app-mosdns v5 branch > mosdns/ has 7 patches vs smpackage's 3
rm -rf feeds/packages/net/mosdns
git clone --depth 1 -b v5 https://github.com/sbwml/luci-app-mosdns.git /tmp/sbwml-mosdns-clone 2>/dev/null
cp -r /tmp/sbwml-mosdns-clone/mosdns feeds/packages/net/mosdns
rm -rf /tmp/sbwml-mosdns-clone

# Use ImmortalWrt luci's adguardhome (lowercase, matching init), drop small-package's (uppercase mismatch)
rm -rf feeds/smpackage/luci-app-adguardhome

rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang


# Fix smartdns LuCI: Promise.all wrapper makes array always truthy -> always shows RUNNING
grep -q 'Promise.all([getServiceStatus()])' feeds/luci/applications/luci-app-smartdns/htdocs/luci-static/resources/view/smartdns/smartdns.js && sed -i 's/return Promise.all([getServiceStatus()]);/return getServiceStatus();/' feeds/luci/applications/luci-app-smartdns/htdocs/luci-static/resources/view/smartdns/smartdns.js || echo 'smartdns LuCI: Promise.all already fixed upstream, skip'
