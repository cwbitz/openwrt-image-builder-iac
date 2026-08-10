# Main Router Configuration

## 概述

此模块用于配置 OpenWrt 系统的局域网（LAN）静态 IP 地址，作为主路由使用。

## 配置参数

### 环境变量
- `BW_MAIN_LAN_IP` - 主路由 LAN 静态 IP，必须使用 CIDR 格式（如 `192.168.2.1/24`）

## 使用场景

适用于主路由模式，仅修改默认的 LAN 网段以避免冲突或适配特定网络规划。
