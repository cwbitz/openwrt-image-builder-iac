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
-o | --output-dir=...             指定构建产物的输出目录（默认：./artifacts）
-c | --custom-modules-path=...    指定自定义模块的物理路径（默认：./custom_modules）
-u | --use-mirror                 启用镜像加速下载（若未指定 -m / --mirror，默认使用 mirrors.tuna.tsinghua.edu.cn）
-m | --mirror=...                 指定自定义镜像加速域名，例如 mirrors.ustc.edu.cn（不要包含 http:// 或 https://）
```

### 环境变量配置说明

可通过以下两种方式配置模块变量（如 `BW_MAIN_LAN_IP`, `BW_ROOT_PASSWORD`, `BW_PPPOE_USERNAME` 等）：

1. **子模块目录 `.env` 文件**：在模块子目录下创建 `.env` 文件（参考各模块下的 `.env.example` 模板）。
2. **命令行直接赋值**：在运行 `run.sh` 脚本时直接传入环境变量，例如：
    ```bash
    BW_MAIN_LAN_IP='192.168.2.1' BW_ROOT_PASSWORD='secret' ./run.sh --image=...
    ```

> ⚠️ **命令行赋值请统一使用单引号**：单引号会**原样传递**值、不做任何展开；而**双引号会先被你的 shell 展开**——例如 `BW_ROOT_PASSWORD="pa$$w@rd"` 中的 `$$` 会被替换成 shell 进程 PID（变成 `pa<PID>w@rd`），写进固件的实际密码将与你预期的完全不同。**凡是含 `$`、`\`、反引号、双引号或空格的变量值都必须用单引号包裹**（其余值用单引号同样安全、无副作用）。

```bash
# ✅ 正确：单引号原样传递
BW_ROOT_PASSWORD='pa$$w@rd' BW_BYPASS_LAN_IP='192.168.2.3/24' ./run.sh ...

# ❌ 错误：双引号会让 shell 展开 $、命令替换与反斜杠
BW_ROOT_PASSWORD="pa$$w@rd" ./run.sh ...
```

> 在 `.env` 文件中则无需引号（脚本按文本原样读取），同样安全。

#### 优先级规则（Precedence Rules）

当相同名称的变量或控制选项在多个地方定义时，其生效优先级如下（从高到低）：
1. **CLI 命令行参数**：如 `--profile`、`--extra-packages`、`--force-pull` 等。命令行直接传入的值始终最高，会覆盖其他所有来源。
2. **外部环境变量 / 运行前直接赋值**：如在宿主机终端中通过 `export BW_MAIN_LAN_IP=...` 注入，或者在命令前临时指定的变量 `BW_MAIN_LAN_IP=... ./run.sh ...`（包含所有 `BW_` 开头的控制变量及子模块自定义环境变量）。
3. **子模块专属的配置**：即 `modules/<name>/.env` 文件中的配置。
4. **项目根目录下的全局配置**：即根目录 `.env` 文件中的配置。

> ⚠️ **注意**：模块目录下的 `.env.example` **仅用于变量发现**（告知脚本该模块支持哪些变量名），脚本**不会读取其中的值**，因此它不属于上述优先级链中的"值来源"。详见 [自定义模块开发规范](#自定义模块开发规范)。

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

默认输出目录为 `./artifacts`，可通过 `--output-dir` 修改。

构建产物的目录结构为 `artifacts/targets/<target>/<subtarget>/`，其中包含生成的固件镜像（如 `*-sysupgrade.bin`、`*-factory.bin`）、`profiles.json`、`sha256sums` 等文件。

---

## 模块系统

所有模块及其支持的环境变量映射一览表如下，供编写 `./run.sh` 命令时查阅（✔ 表示默认启用，✘ 表示默认关闭、需通过模块控制参数手动启用）：

| 模块 | 默认启用 | 模块说明 | 支持的环境变量（默认值） |
|------|:---:|----------|--------------------------|
| `ap` | ✘ | 配置无线接入点（AP）：LAN 网关/DNS 指向主路由，可选关闭 DHCP | `BW_AP_LAN_IP`（CIDR 格式，如 `192.168.2.3/24`）、`BW_AP_GATEWAY`、`BW_AP_DNS`、`BW_AP_DISABLE_DHCP` |
| `base` | ✔ | 提供 OpenWrt 系统基础软件包（LuCI Web 界面、`-dnsmasq`/`dnsmasq-full`、`-wpad-basic-mbedtls`/`wpad-mbedtls`、中文语言包等），并根据 OpenWrt 版本自动适配包列表 | 无 |
| `bypass-router` | ✘ | 将设备配置为旁路由：LAN 网关/DNS 指向主路由，可选关闭 LAN DHCP | `BW_BYPASS_LAN_IP`（CIDR 格式，如 `192.168.2.2/24`）、`BW_BYPASS_GATEWAY`、`BW_BYPASS_DNS`、`BW_BYPASS_DISABLE_DHCP` |
| `disable-ipv6` | ✔ | 禁用 LAN/WAN 接口的 IPv6、RA（Router Advertisement）与 DHCPv6 | 无 |
| `extras` | ✔ | 安装常用网络诊断与系统管理工具（tcpdump、curl、vim-full、conntrack 等） | 无 |
| `main-router` | ✔ | 配置主路由 LAN 网络接口的 IP 地址 | `BW_MAIN_LAN_IP`（CIDR 格式，如 `192.168.2.1/24`） |
| `pppoe` | ✔ | 首次开机自动配置 WAN 接口的 PPPoE 拨号账号与密码 | `BW_PPPOE_USERNAME`、`BW_PPPOE_PASSWORD`（需同时设置，默认空） |
| `prefer-ipv6` | ✘ | 优化 IPv6 优先级与首选配置 | 无 |
| `python` | ✘ | 为 OpenWrt 添加 Python 3 轻量级运行环境（`python3-light`） | 无 |
| `root-password` | ✔ | 配置系统 root 登录密码，支持随机生成 | `BW_ROOT_PASSWORD`（默认空；含 `$` 等特殊字符建议写入模块 .env） |
| `ssh-permission` | ✘ | 修正并配置 SSH `authorized_keys` 文件权限（600） | 无 |
| `statistics` | ✘ | 提供 collectd 系统性能/温度监控采集及 LuCI 统计图表界面 | 无 |
| `system` | ✔ | 配置系统基础设置：时区（`Asia/Shanghai` / `CST-8`）与日志级别 | 无 |

默认启用模块：`base disable-ipv6 extras main-router pppoe root-password system`

- 可在默认集基础上增减模块：`-a | --adjust-modules`，例如 `statistics -extras`。
- 可完全自定义模块列表（忽略默认集）：`-O | --override-modules`，例如 `base main-router pppoe extras`。
- 上表中标记为 ✘ 的模块（`ap`、`bypass-router`、`prefer-ipv6`、`python`、`ssh-permission`、`statistics`）可通过上述两种方式启用。

> 各环境变量的注入方式与优先级请参见上文 [环境变量配置说明](#环境变量配置说明)。

模块目录：

- `modules/`：内置模块
- `custom_modules/`：自定义模块

详细的目录与模块结构请参考下文的 [开发与构建](#开发与构建) 部分。

高级特性：

- 支持模块专属 `.env` 文件或命令行直接赋值环境变量（`.env.example` 仅声明变量名，不作为默认值来源）
- `files/etc/uci-defaults` 中的文件支持 `$VARNAME` 替换
- 若不同模块生成同名目标文件，构建将失败以避免覆盖

---

## 注意事项

- 本项目仅支持官方 OpenWrt ImageBuilder 镜像
- 采用 CLI 命令行构建流程

---

## 常见问题

- 构建速度慢/网速受限？建议启用 `--use-mirror` 或指定 `--mirror=mirrors.ustc.edu.cn`
- 启用镜像源后构建失败？若指定的国内镜像源（如清华源/中科大源）尚未完全同步官方发布的新版本仓库，会导致包管理器报错或构建失败。此时建议**不要启用镜像源**（去掉 `-u | --use-mirror` 参数）直接使用官方源，或等国内镜像源同步完毕后再试。
- 没有安装 Docker？请先安装 Docker Desktop（macOS）或 Docker Engine（Linux）
- 构建结果在哪？默认在 `./artifacts`，固件位于 `artifacts/targets/<target>/<subtarget>/`（可用 `--output-dir` 修改）
- 找不到 Docker？请确认 Docker 已安装并启动，并重启终端
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
├─ artifacts/           # 构建产物输出目录（默认，可用 --output-dir 修改）
├─ modules/             # 内置模块目录
│  └─ [module-name]/    # 模块结构示例
│     ├─ packages       # 依赖包列表或可执行脚本
│     ├─ files/         # 将打包到固件的文件
│     ├─ post-script.sh # 可选：后处理逻辑脚本
│     ├─ .env           # 可选：模块专属环境变量文件（可参考 .env.example）
│     ├─ .env.example   # 可选：声明模块支持的变量名（仅用于变量发现，不读取其中的值）
│     └─ README.md      # 可选：模块说明
├─ custom_modules/      # 自定义模块目录
└─ LICENSE              # MIT 许可证
```

本项目主要依赖 Docker

## 自定义模块开发规范

自定义模块放在 `custom_modules/` 目录（或通过 `-c | --custom-modules-path` 指定其它目录），每个模块对应一个子目录：

```
custom_modules/my-module/
├─ packages              # 软件包列表（也可以是可执行脚本，其 stdout 输出软件包列表）
├─ files/                # 需要打包进固件的文件树（会全部合入固件的 FILES 目录）
│  └─ etc/uci-defaults/  # 首次开机自动执行的初始化脚本（建议用 2 位数字前缀控制执行顺序）
├─ post-script.sh        # 可选：构建期间在容器内执行的后处理脚本
├─ .env                  # 可选：模块专属变量值（优先级仅次于命令行）
└─ .env.example          # 强烈建议提供：声明模块支持的变量名（用于变量发现）
```

### 基本要求

- 模块名使用全小写字母与连字符（如 `my-module`）。
- **不要与 `modules/` 内置模块重名**：同名模块会被同时处理，导致软件包重复、文件路径冲突，构建直接失败。
- 软件包冲突保护：同一软件包不能同时以 `+pkg` 与 `-pkg` 形式出现在最终包列表中，否则构建报错退出。

### `packages` 文件

- 可以是一行空格分隔的包名列表。
- 也可以是**可执行脚本**：脚本的 `stdout` 输出内容会被当作包列表（先尝试执行解析，失败则按纯文本读取）。
- 支持 `-包名` 前缀表示"从默认包列表中移除该包"；最终列表中的正负冲突会被 `check_package_conflicts` 检测并报错。

### `files/` 变量替换（`$VARNAME`）

模块 `files/` 下**文本文件**中的 `$VARNAME` 占位符会在构建期间被替换为实际值：

- **变量发现**：仅替换在模块 `.env` 或 `.env.example` 中**声明过的变量名**，未声明的 `$FOO` 会原样保留。因此——
  - 想在脚本中使用变量，就**必须把变量名写进 `.env.example`**（否则变量名永远无法被发现）；
  - 不想被替换的占位符，就不要写进 `.env.example`。
- **空值处理**：若某变量在命令行、模块 `.env`、全局 `.env` 中均未提供值，它会被替换成**空字符串**，而非保留 `$VARNAME` 原文：
  ```sh
  # ✅ 推荐：空值时安全跳过
  if [ -n "$MY_VALUE" ]; then
      # 仅在提供了值时才执行
      ...
  fi
  # ❌ 不推荐：空值时会留下一行空配置
  uci set network.lan.ipaddr='$MY_VALUE'
  ```
- **转义规则**：
  - **shell 脚本**（以 `.sh` 结尾或位于 `etc/uci-defaults/` 目录下）：值中的 `\`、`$`、反引号、双引号会被自动转义，确保固件运行时还原为字面值（例如密码 `pa$$w@rd` 不会被 shell 误展开成 `pa`）。
  - **普通文本文件**：不进行任何字符转义，值直接用于 awk 字符串拼接，保证字面值传输。
- **文件类型检测**：仅处理被 `is_text_file` 判定为文本的文件（如 `.conf`、`.json`、脚本等），二进制文件直接跳过。

### `post-script.sh`

- 以 `source` 方式在构建容器内、文件合并之前执行，可修改构建环境或预置文件。
- 注意它运行在容器内：`TMPDIR` 已被脚本设置为构建工作区目录（`/builder/tmp`），大文件临时操作无需担心 tmpfs 溢出。

### 变量优先级（重要）

```
命令行环境变量 / run.sh 前赋值  >  模块下 .env  >  全局 .env
```

`.env.example` **不在**这条优先级链中——它只提供变量名，永远不提供值。详见上文 [环境变量配置说明](#环境变量配置说明)。

### 新增模块的检查清单

1. 在 `custom_modules/<my-module>/` 下创建 `packages`、`files/`（必要时 `post-script.sh`）。
2. 创建 `.env.example`，**完整列出** `files/` 中所有将被替换的变量名。
3. 每个用到变量的 uci-defaults 脚本都用 `if [ -n "$VARNAME" ]` 做空值保护。
4. 用 `-a | --adjust-modules` 或 `-O | --override-modules` 启用模块，重建并检查 `.manifest` / 解包 `rootfs` 验证结果。

## 许可证

本项目基于 MIT 协议发布，详见 `LICENSE`
