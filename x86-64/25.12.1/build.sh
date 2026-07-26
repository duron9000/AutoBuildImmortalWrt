#!/bin/bash
set -Eeuo pipefail

# Log file for debugging
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
echo "编译固件大小为: $PROFILE MB"
echo "Include Docker: $INCLUDE_DOCKER"

echo "Create pppoe-settings"
mkdir -p  /home/build/immortalwrt/files/etc/config

# 创建pppoe配置文件 yml传入环境变量ENABLE_PPPOE等 写入配置文件 供99-custom.sh读取
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

echo "cat pppoe-settings"
cat /home/build/immortalwrt/files/etc/config/pppoe-settings

# 25.12 已由 opkg/IPK 切换到 apk/APK。
# 不再拉取 wukongdaily/store 的 run/IPK 离线包，也不覆盖 feeds/packages/lang/golang。
# ImmortalWrt 25.12.1 ImageBuilder 已固定官方 packages/luci/routing/telephony/video feeds，
# PassWall、HomeProxy、OpenClash、Docker 和 Go 依赖均直接使用官方 feed 版本。

# 只生成 generic-squashfs-combined-efi.img.gz。
# ImageBuilder 默认会同时创建 ext4、BIOS、qcow2、vdi、vmdk、vhdx 等格式；
# ROOTFS_PARTSIZE=2048 时每种磁盘格式都会重复写入 2 GiB，耗时和空间开销很大。
set_kconfig() {
  local symbol="$1"
  local value="$2"

  sed -i \
    -e "/^CONFIG_${symbol}=/d" \
    -e "/^# CONFIG_${symbol} is not set$/d" \
    .config

  if [ "$value" = "y" ]; then
    echo "CONFIG_${symbol}=y" >> .config
  else
    echo "# CONFIG_${symbol} is not set" >> .config
  fi
}

set_kconfig TARGET_ROOTFS_SQUASHFS y
set_kconfig TARGET_ROOTFS_EXT4FS n
set_kconfig TARGET_ROOTFS_TARGZ n
set_kconfig GRUB_IMAGES n
set_kconfig GRUB_EFI_IMAGES y
set_kconfig ISO_IMAGES n
set_kconfig QCOW2_IMAGES n
set_kconfig VDI_IMAGES n
set_kconfig VMDK_IMAGES n
set_kconfig VHDX_IMAGES n
set_kconfig TARGET_IMAGES_GZIP y

# iStore 不在 ImmortalWrt 官方 feed 中，使用 LinkEase 官方 APK 仓库和签名公钥。
ISTORE_APK_BASE="https://istore.istoreos.com/repo-apk"
ISTORE_APK_KEY="$ISTORE_APK_BASE/istore-apk.pem"
ISTORE_APK_REPOSITORIES="
$ISTORE_APK_BASE/all/nas_luci/packages.adb
$ISTORE_APK_BASE/all/store/packages.adb
$ISTORE_APK_BASE/all/meta/packages.adb
$ISTORE_APK_BASE/x86_64/nas/packages.adb
"

mkdir -p keys
wget -q "$ISTORE_APK_KEY" -O keys/istore.pem
while IFS= read -r repository; do
  [ -n "$repository" ] || continue
  grep -Fqx "$repository" repositories ||
    echo "$repository" >> repositories
done <<EOF
$ISTORE_APK_REPOSITORIES
EOF

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建固件..."

# ============= imm仓库内的插件==============
# 定义所需安装的包列表 下列插件你都可以自行删减
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon"
PACKAGES="$PACKAGES luci-app-argon-config"
PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"
# 25.12.1 使用 apk 对应的 LuCI 软件包管理器
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
# 使用官方 ImmortalWrt 25.12.1 feeds 内置版本，避免重复第三方源
PACKAGES="$PACKAGES luci-i18n-passwall-zh-cn"
PACKAGES="$PACKAGES luci-app-openclash"
PACKAGES="$PACKAGES luci-i18n-homeproxy-zh-cn"
PACKAGES="$PACKAGES openssh-sftp-server"
PACKAGES="$PACKAGES luci-i18n-samba4-zh-cn"
# iStore 及其后台任务依赖，来自 LinkEase 官方 APK 仓库
PACKAGES="$PACKAGES luci-app-store"
PACKAGES="$PACKAGES luci-lib-taskd"
PACKAGES="$PACKAGES luci-lib-xterm"
PACKAGES="$PACKAGES taskd"
# Intel 网卡驱动：
# I210/I211 -> igb，I217/I218/I219 -> e1000e，I225/I226 -> igc
PACKAGES="$PACKAGES kmod-igb"
PACKAGES="$PACKAGES kmod-e1000e"
PACKAGES="$PACKAGES kmod-igc"
# 文件管理器
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn"
# 静态文件服务器dufs(推荐)
PACKAGES="$PACKAGES luci-i18n-dufs-zh-cn"
# OpenClash 依赖 dnsmasq-full；显式剔除冲突的精简 dnsmasq
PACKAGES="$PACKAGES -dnsmasq dnsmasq-full"

# 判断是否需要编译 Docker 插件
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "Adding package: luci-i18n-dockerman-zh-cn"
fi

# 若构建openclash 则添加内核
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash，添加 openclash core"
    mkdir -p files/etc/openclash/core
    # Download clash_meta
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64.tar.gz"
    wget -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    # Download GeoIP and GeoSite
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
else
    echo "⚪️ 未选择 luci-app-openclash"
fi

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

if ! make image PROFILE="generic" PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE="$PROFILE"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
