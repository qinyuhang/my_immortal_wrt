#!/bin/sh
# 该脚本在系统首次启动时执行

# ==========================================
# 1. SD 卡自动扩容（两段式，使用 init 脚本跨重启）
# ==========================================

cat <<'EOF' >/etc/init.d/firstboot-resize
#!/bin/sh /etc/rc.common
START=05
STOP=90

start() {
	[ -f /etc/rootfs-resize ] && return 0

	type parted >/dev/null 2>&1 || return 0
	type resize2fs >/dev/null 2>&1 || return 0

	ROOT_BLK=$(readlink -f /sys/dev/block/$(awk '$9=="/dev/root"{print $3}' /proc/self/mountinfo))
	ROOT_DISK="/dev/$(basename ${ROOT_BLK%/*})"
	ROOT_PART="${ROOT_BLK##*[^0-9]}"
	ROOT_DEV="/dev/${ROOT_BLK##*/}"

	if [ ! -f /etc/rootpt-resize ]; then
		parted -f -s "${ROOT_DISK}" resizepart "${ROOT_PART}" 100% || return 1
		touch /etc/rootpt-resize
		sync
		reboot
		return 0
	fi

	if [ ! -f /etc/rootfs-resize ]; then
		resize2fs -f "${ROOT_DEV}" && touch /etc/rootfs-resize
		sync
		/etc/init.d/firstboot-resize disable >/dev/null 2>&1
		rm -f /etc/init.d/firstboot-resize
	fi
}
EOF

chmod +x /etc/init.d/firstboot-resize
/etc/init.d/firstboot-resize enable

# 加入系统升级保留列表（避免升级后丢失扩容状态）
cat <<'EOF' >>/etc/sysupgrade.conf
/etc/init.d/firstboot-resize
/etc/rootpt-resize
/etc/rootfs-resize
EOF

# ==========================================
# 2. 添加自定义软件源
# ==========================================
. /etc/openwrt_release
# RELEASE="$DISTRIB_RELEASE"
# ARCH="aarch64_cortex-a53"
# cat <<EOF >>/etc/opkg/customfeeds.conf

# # ImmortalWrt Packages 源
# src/gz immortalwrt_packages https://downloads.immortalwrt.org/releases/$RELEASE/packages/$ARCH/packages/
# EOF
# (
#   sleep 30
#   opkg update
# ) &

# ==========================================
# 3. 配置 R4S 网口指示灯（LAN=eth1, WAN=eth0）
# ==========================================
uci delete system.led_lan 2>/dev/null
uci delete system.led_wan 2>/dev/null

uci add system led
uci set system.@led[-1].name='LAN'
uci set system.@led[-1].sysfs='green:lan'
uci set system.@led[-1].trigger='netdev'
uci set system.@led[-1].dev='eth1'
uci set system.@led[-1].mode='link tx rx'

uci add system led
uci set system.@led[-1].name='WAN'
uci set system.@led[-1].sysfs='green:wan'
uci set system.@led[-1].trigger='netdev'
uci set system.@led[-1].dev='eth0'
uci set system.@led[-1].mode='link tx rx'

uci commit system

# ==========================================
# 4. 基础系统设置
# ==========================================
mkdir -p /etc/openclash/core

uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci set system.@system[0].hostname='R4S-OpenClash'
uci commit system

exit 0
