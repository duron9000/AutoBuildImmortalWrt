# ImmortalWrt x86-64 25.12.1 兼容说明

## 网卡驱动

此构建显式加入常见 Intel 有线网卡驱动：

- `kmod-igb`：I210/I211 等
- `kmod-e1000e`：I217/I218/I219 等
- `kmod-igc`：I225/I226 等 2.5GbE 网卡

“I215”不是常见的 Intel 控制器型号；如果实际硬件是 I225/I226，则由 `kmod-igc` 支持。

## 25.12 与旧版本的主要差异

- 25.12 已从 `opkg`/`.ipk` 切换到 `apk`/`.apk`。
- 不再拉取或解包 `wukongdaily/store` 中面向旧版本的 `.run`/`.ipk` 文件。
- 不再将旧的 `x86-64/imm.config` 覆盖到 25.12.1 ImageBuilder，避免把 `opkg` 和旧 Kconfig 项带入新版本。
- 使用 ImmortalWrt 25.12.1 ImageBuilder 固定的官方 `packages`、`luci`、`routing`、`telephony`、`video` feeds。
- 不执行以下旧 Go 覆盖逻辑：

  ```sh
  rm -rf feeds/packages/lang/golang
  git clone https://github.com/sbwml/packages_lang_golang -b 23.x feeds/packages/lang/golang
  ```

  官方 25.12.1 feed 已提供新的 Go 构建基础，重复覆盖会引入版本和依赖冲突。ImageBuilder 本身也不是源码 feeds 编译流程。

## 软件包来源

PassWall、HomeProxy、OpenClash、Docker、软件包管理器及其依赖均使用 ImmortalWrt 25.12.1 官方 feeds 中的版本。这样可以让 APK 依赖解析、签名和目标架构保持一致，避免同时混用旧 IPK 仓库。
