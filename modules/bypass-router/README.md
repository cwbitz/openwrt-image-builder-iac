# Bypass Router (旁路由) Configuration

## 概述

此模块用于将 OpenWrt 设备配置为**旁路由**（Bypass Router）：设备通过 LAN 口接入主路由所在网段，将网关与 DNS 指向主路由，适合科学上网、广告过滤、Docker 旁路网关等场景。

## 功能

- 设置旁路由自身的 LAN 静态 IP 地址
- 设置 LAN 网关（`network.lan.gateway`，通常为主路由的 LAN IP）
- 设置 LAN DNS（`network.lan.dns`，通常为主路由的 LAN IP 或公共 DNS，可多个）
- 可选：关闭 LAN 口 DHCP 服务（`network.lan.ignore='1'`），由主路由统一分配地址

## 配置参数

### 环境变量
- `BW_BYPASS_LAN_IP` - 旁路由自身 LAN 静态 IP，必须使用 CIDR 格式（如 `10.0.10.3/24`，默认空，为空则不修改）
- `BW_BYPASS_GATEWAY` - LAN 网关，通常为主路由的 LAN IP（默认空）
- `BW_BYPASS_DNS` - LAN DNS，可多个，用空格分隔（默认空）
- `BW_BYPASS_DISABLE_DHCP` - 设为 `1` 时关闭 LAN 口 DHCP（默认空）
