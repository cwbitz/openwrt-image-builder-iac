# 优先使用 IPv6 配置

## 概述

此模块用于配置 OpenWrt 系统，通过调整 DHCP 和路由通告（Router Advertisement）设置，引导局域网内的客户端优先使用 IPv6 网络。

## 功能

- 启用局域网（LAN）上的 IPv6 路由通告（RA）服务
- 配置 DHCPv6 和 RA 生命周期行为
- 引导局域网客户端优先通过 IPv6 路由
- 首次开机时自动应用推荐的局域网 IPv6 设置
- 解决 LAN 接口启动过快，而 WAN 接口尚未获取到 IPv6 前缀授权（PD）导致 odhcpd 服务挂起、IPv6 分配异常的问题

## 配置文件

- `files/etc/uci-defaults/99-ipv6` - 首次开机时的 IPv6 基础 UCI 配置脚本
- `files/etc/hotplug.d/iface/99-odhcpd` - Hotplug 热插拔脚本，在 WAN 获取到 IPv6 地址后自动重载 LAN，避免 odhcpd 挂起并确保客户端能正常获取到 IPv6 前缀

## 实现原理

1. **UCI 初始化配置 (`99-ipv6`)**：
   - 清除默认的本地单播地址前缀 (`ula_prefix`)
   - 重新初始化并重置 `dhcp.lan` 设置
   - 配置 LAN 接口为 `ra='server'`（通告服务端模式），且开启 `ra_useleasetime='1'`
   - 设置首选生命周期为 `preferred_lifetime='8h'`

2. **热插拔监听 (`99-odhcpd`)**：
   - 监听 `wan` 接口的状态变化（支持 `ifup` / `ifupdate` 动作）
   - 获取到 WAN 的有效 IPv6 地址后，临时关闭 UPnP（若存在），通过 `ifup lan` 重新拉起局域网接口以刷新 odhcpd 服务，最后恢复 UPnP

## 适用场景

- 启用了 IPv6 的网络环境
- 宽带拨号或 WAN 链路能够正常获取到 IPv6 前缀授权（PD）的场景
- 希望优先使用 IPv6 替代 IPv4 进行网络访问的环境

## 注意事项

- 必须有上游网络（ISP）的 IPv6 支持，否则局域网无法分发公网 IPv6 地址
- 配置在系统首次启动时应用，但 Hotplug 脚本会持续在后续的 WAN 接口状态变化中生效
- 配合能够获取 IPv6 委派前缀的 WAN 链路效果最佳
