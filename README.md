<div align="center">

# OpenWrt Builder Wrapper

[English](README.en.md) | 简体中文

基于官方 OpenWrt ImageBuilder 的模块化固件构建工具

命令行构建 + 模块化扩展，让固件定制更灵活

[![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](LICENSE)
</div>

---

## 特性一览

- **开箱即用**：基于官方 OpenWrt ImageBuilder，快速生成固件
- **模块化**：内置模块并支持 `custom_modules` 自定义扩展
- **命令行构建**：使用 `run.sh`，支持 Linux 和 macOS
- **容器化**：Docker 隔离构建环境，无需本机编译工具链
- **配置复用**：环境变量集中管理，可重复使用构建方案

---

## 快速使用

### Linux / macOS

```bash
# 查看帮助
./run.sh --help

# 示例：官方 OpenWrt ImageBuilder
./run.sh \
  --image=openwrt/imagebuilder:generic-arm64 \
  --profile=generic \
  --force-pull --force-recreate --use-mirror
```

### 常用参数

```bash
# Docker 容器与镜像拉取策略
-i | --image=...                  指定 openwrt/imagebuilder Docker 镜像（必需）
-P | --force-pull                 构建前强制从镜像源拉取/更新镜像
-R | --force-recreate             构建前强制删除已存在的同名构建容器
-I | --info                       查询镜像和 Profile 基础信息

# 设备配置
-p | --profile=...                指定构建的设备 Profile 属性（若省略则默认使用该目标的第一个 Profile）

# 模块与软件包控制
-O | --override-modules=...       完全自定义模块列表，覆盖默认模块集（例如 "base lan prefer-ipv6 extras"）
-a | --adjust-modules=...         在默认模块集基础上增减/调整模块（例如 "statistics -extras"）
-e | --extra-packages=...         指定传入 ImageBuilder 的显式 PACKAGES 软件包列表
-d | --disabled-services=...      指定构建固件时禁用的服务列表

# 目标固件自定义配置
-E | --extra-image-name=...       指定固件生成文件名的自定义后缀
-r | --rootfs-partsize=...        指定根分区大小（MB，若省略则使用设备默认值）

# 输出目录、自定义模块路径与镜像加速配置
-o | --output-dir=...             指定构建产物的输出目录（默认：./bin）
-c | --custom-modules-path=...    指定自定义模块的物理路径（默认：./custom_modules）
-u | --use-mirror                 启用镜像加速下载（若未指定 -m / --mirror，默认使用 mirrors.tuna.tsinghua.edu.cn）
-m | --mirror=...                 指定自定义镜像加速域名，例如 mirrors.ustc.edu.cn（不要包含 http:// 或 https://）
```

### 环境变量配置说明

可通过以下两种方式配置模块变量（如 `BW_LAN_IP`, `BW_ROOT_PASSWORD`, `BW_PPPOE_USERNAME` 等）：

1. **子模块目录 `.env` 文件**：在模块子目录下创建 `.env` 文件（参考各模块下的 `.env.example` 模板）。
2. **命令行直接赋值**：在运行 `run.sh` 脚本时直接传入环境变量，例如：
   ```bash
   BW_LAN_IP=192.168.2.1 BW_ROOT_PASSWORD=secret ./run.sh --image=...
   ```

#### 优先级规则（Precedence Rules）

当相同名称的变量或控制选项在多个地方定义时，其生效优先级如下（从高到低）：
1. **CLI 命令行参数**：如 `--profile`、`--extra-packages`、`--force-pull` 等。命令行直接传入的值始终最高，会覆盖其他所有来源。
2. **外部环境变量 / 运行前直接赋值**：如在宿主机终端中通过 `export BW_LAN_IP=...` 注入，或者在命令前临时指定的变量 `BW_LAN_IP=... ./run.sh ...`（包含所有 `BW_` 开头的控制变量及子模块自定义环境变量）。
3. **子模块专属的配置**：即 `modules/<name>/.env` 文件中的配置。
4. **项目根目录下的全局配置**：即根目录 `.env` 文件中的配置。

### 核心控制环境变量示例

```bash
# 在默认模块集 (base system root-password pppoe lan disable-ipv6 extras) 基础上增减模块（如 -extras 剔除 extras）
BW_ADJUST_MODULES="statistics -extras"

# 完全自定义模块列表（若指定则忽略默认模块集和 ADJUST_MODULES）
BW_OVERRIDE_MODULES="base lan pppoe extras"

# 显式覆盖/追加给 ImageBuilder 的软件包列表（使用前缀 - 可移除默认软件包）
BW_EXTRA_PACKAGES="luci-app-openclash -dnsmasq"

# 自定义构建镜像扩展属性
BW_EXTRA_IMAGE_NAME="custom"
BW_DISABLED_SERVICES="dnsmasq"
BW_ROOTFS_PARTSIZE="256"
```

默认输出目录为 `./bin`，可通过 `--output-dir` 修改。

---

## 模块系统

默认启用的模块集：

`base system root-password pppoe lan disable-ipv6 extras`

当前内置的所有可选模块：

`base disable-ipv6 extras lan pppoe prefer-ipv6 python root-password ssh-permission statistics system`

模块目录：

- `modules/`：内置模块
- `custom_modules/`：自定义模块

详细的目录与模块结构请参考下文的 [开发与构建](#开发与构建) 部分。

说明：

- `base`：提供 OpenWrt 系统的基础软件包集合，包括 LuCI Web 管理界面、系统工具和必要的系统组件。
- `disable-ipv6`：在固件启动后禁用 LAN/WAN 接口的 IPv6、Router Advertisement（RA）和 DHCPv6 等 IPv6 服务。
- `extras`：安装常用的网络诊断和系统管理工具（如 tcpdump、curl 等），提供完整的系统管理和故障排查能力。
- `lan`：配置 LAN 网络接口的 IP 地址，支持通过环境变量自定义局域网地址段。
- `pppoe`：用于在系统首次开机时自动配置 WAN 接口的 PPPoE 拨号账号与密码。
- `prefer-ipv6`：优化 IPv6 优先级与首选配置。
- `python`：为 OpenWrt 系统添加 Python 3 轻量级运行环境支持。
- `root-password`：配置系统 root 用户登录密码（支持自定义或随机密码生成）。
- `ssh-permission`：自动修正并配置 SSH 授权密钥文件（authorized_keys）的权限，确保 SSH 公钥认证正常工作。
- `statistics`：提供系统性能监控、温度监控采集以及可视化界面的数据统计功能。
- `system`：配置系统基础设置（如将时区设置为中国时区、调整系统日志级别等）。

高级特性：

- 支持模块专属 `.env` 文件或命令行直接赋值环境变量
- `files/etc/uci-defaults` 中的文件支持 `$VARNAME` 替换
- 若不同模块生成同名目标文件，构建将失败以避免覆盖

---

## 注意事项

- 本项目仅支持官方 OpenWrt ImageBuilder 镜像
- 采用 CLI 命令行构建流程

---

## 常见问题

- 构建速度慢/网速受限？建议启用 `--use-mirror` 或指定 `--mirror=mirrors.ustc.edu.cn`
- 没有安装 Docker？请先安装 Docker Desktop（macOS）或 Docker Engine（Linux）
- 构建结果在哪？默认在 `./bin`（可用 `--output-dir` 修改）
- 找不到 Docker？请确认 Docker 已安装并启动，并重启终端
- 没有 Docker 权限？将用户加入 docker 组：`sudo usermod -aG docker $USER`，然后重新登录
- 中文路径问题？建议放在英文路径下，避免路径编码问题

---

## 开发与构建

项目与模块结构：

```
.
├─ build.sh             # 容器内实际构建脚本
├─ run.sh               # 构建脚本
├─ .env                 # 可选：全局环境变量文件（可参考 .env.example）
├─ .env.example         # 全局环境变量模板与注释说明
├─ modules/             # 内置模块目录
│  └─ [module-name]/    # 模块结构示例
│     ├─ packages       # 依赖包列表或可执行脚本
│     ├─ files/         # 将打包到固件的文件
│     ├─ post-script.sh # 可选：后处理逻辑脚本
│     ├─ .env           # 可选：模块专属环境变量文件（可参考 .env.example）
│     ├─ .env.example   # 可选：模块环境变量模板与注释说明
│     └─ README.md      # 可选：模块说明
├─ custom_modules/      # 自定义模块目录
└─ LICENSE              # MIT 许可证
```

本项目主要依赖 Docker

## 许可证

本项目基于 MIT 协议发布，详见 `LICENSE`
