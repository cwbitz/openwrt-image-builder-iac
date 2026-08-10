# Access Point (AP) Configuration

## 概述

此模块用于将 OpenWrt 设备配置为**无线接入点**（Access Point / AP）：设备通过 LAN 口接入主路由，网关与 DNS 指向主路由，可选关闭 DHCP。

## 功能

- 设置 AP 自身的 LAN 静态 IP 地址
- 设置 LAN 网关（`network.lan.gateway`，通常为主路由的 LAN IP）
- 设置 LAN DNS（`network.lan.dns`，通常为主路由的 LAN IP 或公共 DNS，可多个）
- 可选：关闭 LAN 口 DHCP 服务（`network.lan.ignore='1'`）

## 配置参数

### 环境变量
- `BW_AP_LAN_IP` - AP 自身 LAN 静态 IP（默认空，为空则不修改）
- `BW_AP_GATEWAY` - LAN 网关，通常为主路由的 LAN IP（默认空）
- `BW_AP_DNS` - LAN DNS，可多个，用空格分隔（默认空）
- `BW_AP_DISABLE_DHCP` - 设为 `1` 时关闭 LAN 口 DHCP（默认空）

## 配置示例

在 `.env` 或模块的 `.env` 文件中设置：
```bash
BW_AP_LAN_IP=192.168.1.100
BW_AP_GATEWAY=192.168.1.1
BW_AP_DNS="192.168.1.1 223.5.5.5"
BW_AP_DISABLE_DHCP=1
```

或者在构建脚本执行时传入：
```bash
BW_AP_GATEWAY=192.168.1.1 \
BW_AP_DNS="192.168.1.1 223.5.5.5" \
BW_AP_DISABLE_DHCP=1 \
./run.sh -i openwrt/imagebuilder:... -a ap ...
```

## 启用模块

该模块默认不启用，需通过 `-a | --adjust-modules` 添加：
```bash
./run.sh -i openwrt/imagebuilder:... -a "ap" -p <profile> ...
```

## 实现原理

1. 读取环境变量中的 `BW_AP_*` 配置（构建时替换进脚本）
2. 首次开机时使用 UCI 命令更新 `network.lan` 相关参数（`ipaddr` / `gateway` / `dns`）
3. 可选关闭 LAN 口 DHCP（`network.lan.ignore='1'`）
4. `uci commit` 提交配置使其生效

## 配置文件

- `.env.example` - 环境变量模板（仅用于变量发现，值不会从此文件读取）
- `files/etc/uci-defaults/90-ap` - UCI 默认配置脚本

## 使用场景

- 把旧路由 / 新设备改造成纯无线 AP 扩展主网络

## 注意事项

- AP 自身的 LAN IP 必须与主路由在同一网段，且不可与其它设备冲突
- 网关与 DNS 通常情况下都填主路由的 LAN IP
- 若关闭 DHCP，请确保主路由已开启 DHCP服务
- 变量为空时对应配置不会被修改，空值处理详见根目录 README 的[自定义模块开发规范](../README.md#自定义模块开发规范)