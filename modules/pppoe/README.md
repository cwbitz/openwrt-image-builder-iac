# PPPoE WAN Configuration

## 概述

此模块用于配置 OpenWrt 系统首次启动时 WAN 接口的 PPPoE 拨号设置，使用环境变量指定拨号凭据。

## 功能

- 将 WAN 接口网络协议修改为 PPPoE
- 配置 PPPoE 拨号用户名和密码
- 开机时自动应用 WAN 接口配置

## 配置参数

### 环境变量
- `BW_PPPOE_USERNAME` - ISP 提供的 PPPoE 拨号用户名
- `BW_PPPOE_PASSWORD` - ISP 提供的 PPPoE 拨号密码

## 配置示例

在 `.env` 或模块的 `.env.example` 文件中设置：
```bash
BW_PPPOE_USERNAME=your_username
BW_PPPOE_PASSWORD=your_password
```

或者在构建脚本执行时传入：
```bash
BW_PPPOE_USERNAME=your_username BW_PPPOE_PASSWORD=your_password ./run.sh ...
```

## 实现原理

1. 检查环境变量 `BW_PPPOE_USERNAME` 和 `BW_PPPOE_PASSWORD` 是否同时存在
2. 如果存在，使用 UCI 命令修改 `network.wan` 接口：
   - 设置 `proto` 为 `pppoe`
   - 设置 `username` 为指定用户名
   - 设置 `password` 为指定密码
3. 提交配置使其在首次启动时生效

## 配置文件

- `.env.example` - 环境变量配置示例文件
- `files/etc/uci-defaults/89-pppoe` - PPPoE 拨号 UCI 配置脚本

## 使用场景

适用于需要通过宽带拨号（PPPoE）接入互联网的场景：
- 光纤或 DSL 宽带接入
- 运营商需要账号密码认证的环境
- 路由器作为主路由直接进行拨号的部署

## 注意事项

- 请确保提供的宽带账号和密码正确无误
- 某些运营商或特殊网络环境可能需要额外的特定 UCI 参数设置（如 VLAN ID 等，本模块默认仅配置基本账号密码）
- 配置仅在系统首次启动时应用，若后续手动修改过网络配置，可能需要手动恢复
