
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
# fix v2dat build error
#sed -i '/PKG_BUILD_DIR/a\PKG_USE_MIPS16:=0' feeds/packages/utils/v2dat/Makefile
# fix v24.10.0 has no shadowsocks-libev
#git clone -b openwrt-23.05 https://github.com/immortalwrt/packages.git pack
#cp -r pack/net/shadowsocks-libev package/feeds/packages/shadowsocks-libev   
#wget -P package/feeds/packages/shadowsocks-libev/patch/ https://raw.githubusercontent.com/zxlhhyccc/packages-2/3f33259b94c0faf32a363817476ef62d00e71910/net/shadowsocks-libev/patches/101-fix-mbedtls3.6-build.patch
git clone https://github.com/msdos03/openwrt-package-shadowsocks-libev package/feeds/packages/shadowsocks-libev
