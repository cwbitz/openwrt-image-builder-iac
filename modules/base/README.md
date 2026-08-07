# Base Packages

## 概述

此模块提供 OpenWrt 系统的基础软件包集合，包含 Web 管理界面、系统工具和必要的系统组件。

## 功能

- 安装基础系统组件和实用工具（SFTP、Rsync 等）
- 配置 LuCI Web 管理界面与 WPA/WPA2/WPA3 完整无线加密支持 (`wpad-mbedtls`)
- 使用完整的 DNS/DHCP 服务 (`dnsmasq-full`) 替代精简版
- 提供中文语言支持
- 根据 OpenWrt 版本动态调整包列表

## 包含的软件包

### 核心组件
- `luci` - LuCI Web 管理界面
- `-dnsmasq` / `dnsmasq-full` - 卸载精简版并安装功能完整的 DNS/DHCP 服务
- `-wpad-basic-mbedtls` / `wpad-mbedtls` - 卸载基础版并安装完整版无线加密组件
- `openssl-util` - OpenSSL 实用工具
- `openssh-sftp-server` - SSH SFTP 文件传输服务支持
- `rsync` - 远程数据同步工具

### 中文界面支持
- `luci-i18n-base-zh-cn` - 基础界面中文翻译
- `luci-i18n-firewall-zh-cn` - 防火墙界面中文翻译

### 版本相关包
- OpenWrt 24.10 及以后版本（包括 SNAPSHOT）：`luci-i18n-package-manager-zh-cn`
- 旧稳定版本（24.10 之前）：`luci-i18n-opkg-zh-cn`

## 版本适配

模块会根据 `VERSION_PATH` 环境变量（解析 target 版本）自动检测 OpenWrt 版本并应用适配的软件包。

## 配置文件

- `packages` - 动态生成软件包列表的脚本

## 使用场景

作为所有 OpenWrt 系统的基础模块，提供完整的 Web 管理界面和基本系统功能。适用于需要图形化管理界面的 OpenWrt 部署。
