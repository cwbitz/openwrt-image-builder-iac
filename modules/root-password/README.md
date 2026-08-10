# Root Password Configuration

## 概述

此模块用于配置 OpenWrt 系统的 root 用户密码，提供安全的系统管理员账户访问控制。

## 功能

- 设置 root 用户登录密码
- 支持随机密码生成
- 增强系统安全性
- 防止未授权访问

## 环境变量配置

### 密码设置
- `BW_ROOT_PASSWORD` - root 用户密码
  - 设置为 `random` 时自动生成随机密码（此功能取决于外部构建或封装脚本的实现）
  - 设置为具体值时使用指定密码

## 配置示例

在 `.env` 或模块的 `.env` 文件中设置：
```bash
BW_ROOT_PASSWORD=your_secure_password
```

> ⚠️ **密码含 `$` / `\` / `"` / 反引号时**：请直接写入模块的 `.env` 文件（如 `BW_ROOT_PASSWORD=pa$$w@rd`），
> 或在命令行用**单引号**传值 `BW_ROOT_PASSWORD='pa$$w@rd' ./run.sh`。
> 若用双引号在命令行传值，shell 与 docker-compose 会展开 `$`，导致固件里的实际密码与预期不符。

或者在构建脚本执行时传入：
```bash
BW_ROOT_PASSWORD=your_secure_password ./run.sh ...
```

## 安全建议

### 密码要求
- 使用 8 位以上字符
- 包含大小写字母、数字和特殊符号
- 避免使用常见密码
- 定期更换密码

### 安全实践
- 优先使用 SSH 密钥认证
- 禁用密码登录（配置密钥后）
- 启用防火墙保护
- 限制 SSH 访问源 IP

## 配置文件

- `.env.example` - 环境变量配置示例
- `files/etc/uci-defaults/92-system` - 系统配置脚本，在首次启动时调用 `passwd` 命令设置 root 密码

## 使用场景

适用于需要安全系统访问的场景：
- 生产环境部署
- 远程管理需求
- 多用户环境
- 安全策略合规

## 注意事项

- 请务必记住设置的密码
- 建议配合 SSH 密钥使用
- 避免在不安全网络传输密码
- 定期检查系统安全日志
