include $(TOPDIR)/rules.mk

PKG_NAME:=r4s-accel
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/r4s-accel
  SECTION:=net
  CATEGORY:=Network
  TITLE:=R4S selective native flowtable admission
  DEPENDS:=+lua +libuci-lua +conntrack +nftables +kmod-nft-offload +luci-base
  PKGARCH:=all
endef

define Package/r4s-accel/conffiles
/etc/config/r4s_accel
endef

define Build/Compile
endef

define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
	$(CP) ./LICENSE $(PKG_BUILD_DIR)/LICENSE
endef

define Package/r4s-accel/install
	$(INSTALL_DIR) $(1)
	$(CP) ./files/* $(1)/
	chmod 0755 $(1)/etc/init.d/r4s-accel $(1)/etc/hotplug.d/iface/95-r4s-accel $(1)/usr/libexec/r4s-accel
endef

$(eval $(call BuildPackage,r4s-accel))
