# SPDX-License-Identifier: GPL-2.0-only
include $(TOPDIR)/rules.mk

PKG_NAME:=r4s-net-tune
PKG_VERSION:=1
PKG_RELEASE:=2
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/r4s-net-tune
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Conservative NanoPi R4S network tuning
  PKGARCH:=all
  DEPENDS:=@TARGET_rockchip +netifd +ethtool +flock
endef

define Package/r4s-net-tune/conffiles
/etc/config/r4s_net_tune
endef

define Build/Compile
endef

# Default postinst enables the init script. Its live start is a no-op once.
# A preinst marker works before default_postinst with both opkg and apk.
define Package/r4s-net-tune/preinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
umask 077
: > /var/run/r4s-net-tune.installing
endef

# Default prerm stops/restores while the helper still exists. Retain any
# deferred ring baseline in /run; never remove it from postrm.
define Package/r4s-net-tune/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
rm -f /var/run/r4s-net-tune.installing
exit 0
endef

define Package/r4s-net-tune/install
	$(INSTALL_DIR) $(1)/etc/config $(1)/etc/init.d $(1)/usr/libexec
	$(INSTALL_DIR) $(1)/etc/hotplug.d/net $(1)/etc/uci-defaults
	$(INSTALL_CONF) ./files/etc/config/r4s_net_tune $(1)/etc/config/r4s_net_tune
	$(INSTALL_BIN) ./files/etc/init.d/r4s-net-tune $(1)/etc/init.d/r4s-net-tune
	$(INSTALL_BIN) ./files/usr/libexec/r4s-net-tune $(1)/usr/libexec/r4s-net-tune
	$(INSTALL_BIN) ./files/etc/hotplug.d/net/90-r4s-net-tune $(1)/etc/hotplug.d/net/90-r4s-net-tune
	$(INSTALL_BIN) ./files/etc/uci-defaults/90-r4s-net-tune $(1)/etc/uci-defaults/90-r4s-net-tune
endef

$(eval $(call BuildPackage,r4s-net-tune))
