# 禁用 IPv6

## 概述

该模块用于在 OpenWrt 固件启动后尽量关闭 IPv6 功能，适用于不需要 IPv6、希望完全禁用 IPv6 的场景。

## 作用

- 关闭 LAN/WAN 接口上的 IPv6 配置
- 禁用 Router Advertisement（RA）和 DHCPv6 服务
- 通过内核参数强制关闭 IPv6 协议栈

## 适用场景

- 仅使用 IPv4 的网络环境
- 需要避免 IPv6 相关兼容性问题
- 需要对网络行为进行更严格控制的场景

## 配置文件

- `files/etc/sysctl.d/99-disable-ipv6.conf` - 内核参数配置，禁用所有接口的 IPv6
- `files/etc/uci-defaults/99-disable-ipv6` - UCI 默认配置脚本，修改网络和 DHCP 设置以关闭 IPv6

## 说明

- 启用此模块后，系统将尽量不再使用 IPv6
- 这会影响依赖 IPv6 的服务和部分 IPv6-only 网络环境
- 如果你需要保留 IPv6，请不要启用此模块
