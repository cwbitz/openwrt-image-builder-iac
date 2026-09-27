# openwrt-builder-wrapper

基于 **官方 OpenWrt ImageBuilder**（Docker 容器）构建自定义 OpenWrt 固件的
Ansible IaC 项目。

> English version: [README.md](./README.md)

## 工具分工与边界

| 层 | 工具 | 职责 |
|----|------|------|
| 构建主机 | **Docker** | 运行官方 `openwrt/imagebuilder` 容器 |
| 固件镜像 | **Ansible**（role `imagebuilder`） | 模块解析、软件包收集、uci-defaults overlay 渲染、容器编排 |
| 运维配置 | `host_vars/<host>/main.yml` + `vault.yml` | 构建目标、模块、软件包、密钥 |

## 架构概览

```
make build
  ├── ansible-playbook ansible/playbooks/build.yml   （hosts: builder = 内网构建机）
  │     └── roles/imagebuilder
  │           preflight → modules → setup → packages → overlay → build
  │                                                       └── community.docker.docker_container(
  │                                                             openwrt/imagebuilder)
  └──（可选）将构建产物回传到控制机的 artifacts/
```

核心设计：

- **单 playbook + 单 role**：`build.yml`（以及 `info.yml`）作用于 `builder`
  主机；role 的任务切片通过 tags 选择
  （`--tags preflight|modules|setup|packages|overlay|build`）。
- **模块由 role 统一管理**：默认模块集
  （`base system root-password pppoe main-router disable-ipv6 extras`）可通过
  `openwrt_modules_adjust` 增删，或用 `openwrt_modules_override` 完全替换。
  每个模块提供软件包和/或 uci-defaults 文件。
- **uci-defaults 使用 Jinja 模板**：原先构建期的 `$VARNAME` 替换改为 Ansible
  `template` 模块；静态文件按原样拷贝。渲染产物汇总到 `.build/files/`。
- **配置按主机作用域**：构建机是单台机器，因此配置放在 `host_vars/<host>/`
  （目录名与 inventory 主机名一致），而非 group_vars；仅 `example/` 目录被提交。
- **密钥隔离**：root 密码、PPPoE 密码与连接凭据存放在主机 vault
  （`host_vars/<host>/vault.yml`），以 `{{ vault_* }}` 引用；vault 口令文件保存在
  仓库之外。preflight 会把自动化用户密码生成到该 vault（未加密的明文 vault 同样可用，
  直到你将其加密）。
- **preflight 引导自动化用户**（参考 proxmox-iac）：在构建机上确保存在 `ansible`
  账号——始终生成密码（写入 vault），可选安装公钥（优先生效，密码作为回退），
  授予免密 sudo，并在存在 `docker` 组时加入该组（`provision_ansible_user` 默认开启）。
- **最小权限连接探测**：每次运行都会探测构建机，按 `ansible` → 可选 `admin` →
  `root` 的顺序尝试（先密钥后密码，仅尝试已配置的凭据），并把选中结果按主机注入；
  inventory 不再设置连接用户。
- **构建期除控制端工具链外只依赖 Docker**（`python` + `ansible-core` +
  `community.docker`）。

## 目录结构

```
openwrt-builder-wrapper/
├── ansible/
│   ├── inventory/
│   │   ├── hosts.yml.example            # 构建主机（内网单机）
│   │   └── host_vars/
│   │       └── example/                 # 已提交模板；真实主机目录 gitignore
│   │           ├── main.yml             # 运维配置入口（构建配置）
│   │           └── vault.yml.example    # 密钥模板（密码/公私钥路径）
│   ├── playbooks/
│   │   ├── build.yml                    # 构建固件（make build）
│   │   └── info.yml                     # 查询 ImageBuilder 信息（make info）
│   ├── roles/imagebuilder/
│   │   ├── defaults/main.yml            # 模块注册表、软件包列表、默认值
│   │   ├── tasks/                       # preflight/modules/setup/packages/overlay/build/info
│   │   ├── files/overlay/<module>/...   # 静态 uci-defaults overlay
│   │   └── templates/overlay/<module>/  # 模板化 uci-defaults + build.sh.j2
│   ├── requirements.yml                 # collections
│   └── ansible.cfg
├── artifacts/                           # 回传的固件（目录被跟踪，内容 gitignore）
├── docs/runbooks.md
├── .tool-versions                       # 控制端工具链版本（asdf/mise）
├── Makefile                             # 统一编排
└── README.md / README-zh.md
```

## 快速开始

```bash
# 0) 控制端工具链：.tool-versions 固定 python + ansible-core，安装一次即可
mise install           # 或：asdf install

# 1) 从模板生成 inventory 与按主机配置（目录名须与 inventory 主机名一致）
cp ansible/inventory/hosts.yml.example ansible/inventory/hosts.yml
cp -r ansible/inventory/host_vars/example ansible/inventory/host_vars/openwrt-ib-prod-1
#    -> 编辑 openwrt-ib-prod-1/main.yml（构建目标、模块），并将
#       vault.yml.example 重命名为 vault.yml

# 2) 密钥：创建 vault 口令（可选：加密 vault）
make ans-deps           # 安装 collections + openssl/sshpass/passlib + docker SDK
make ans-vault-init     # 一次性：生成 vault 口令（务必另行备份）
make ans-vault-edit HOST=openwrt-ib-prod-1   # 填入公钥/私钥路径与固件密钥

# 3) preflight 会在构建机上创建 'ansible' 自动化用户（首次运行需以 root 或具备 sudo
#    的用户连接）；每次运行都会探测并按 ansible → admin → root 的顺序选择连接用户。
make build
```

构建产物先在构建机上生成（默认位于 `~/.cache/openwrt-builder/artifacts`）；当
`openwrt_fetch_artifacts` 开启（默认开启）时，role 会将产物回传到控制机项目根目录的
`artifacts/targets/<target>/<subtarget>/`（固件镜像、`profiles.json`、`sha256sums`
等）。使用 `make info` 可只查询 ImageBuilder 镜像与 Profile 信息、不构建。

> 默认情况下，**控制机**（运行 `make` 的机器）与**构建机**（被控的 Docker 主机）是
> 内网中**两台独立设备**。请修改 `ansible/inventory/hosts.yml` 的 `ansible_host`
> （必要时设置 `ansible_user`）指向你的构建机。也可使用
> `ansible_connection: local` 直接在控制机构建。

## Makefile 目标

| 命令 | 用途 |
|------|------|
| `make build` | 构建自定义固件镜像（ImageBuilder 容器） |
| `make info` | 查询镜像/Profile 信息（不构建） |
| `make ans-deps` | 安装控制端依赖 + collections |
| `make ans-lint` | `ansible-playbook --syntax-check` + `ansible-lint` |
| `make ans-vault-init` | 一次性：生成 vault 口令 |
| `make ans-vault-edit` / `ans-vault-view` | 编辑 / 查看 vault 文件（`FILE=...`） |
| `make clean` | 清理缓存、collections 与构建临时目录 |

## 模块一览

默认启用模块：`base system root-password pppoe main-router disable-ipv6 extras`。

| 模块 | 默认启用 | 说明 | 支持的变量 |
|------|:---:|------|------------|
| `ap` | ✘ | 无线接入点：LAN 网关/DNS 指向主路由，可选关闭 DHCP | `openwrt_ap_lan_ip`、`openwrt_ap_gateway`、`openwrt_ap_dns`、`openwrt_ap_disable_dhcp` |
| `base` | ✔ | 基础软件包（LuCI、`dnsmasq-full`、`wpad-mbedtls`、中文语言包），按版本自动适配 | — |
| `bypass-router` | ✘ | 旁路由：LAN 网关/DNS 指向主路由，可选关闭 DHCP | `openwrt_bypass_lan_ip`、`openwrt_bypass_gateway`、`openwrt_bypass_dns`、`openwrt_bypass_disable_dhcp` |
| `disable-ipv6` | ✔ | 禁用 LAN/WAN 的 IPv6、RA 与 DHCPv6 | — |
| `extras` | ✔ | 常用网络诊断与系统工具（`curl`、`vim-full`、`tcpdump`、`conntrack` 等） | — |
| `main-router` | ✔ | 设置主路由 LAN IP | `openwrt_main_lan_ip` |
| `pppoe` | ✔ | 配置 WAN PPPoE 账号与密码 | `openwrt_pppoe_username`、`openwrt_pppoe_password` |
| `prefer-ipv6` | ✘ | IPv6 优先级与 RA 配置优化 | — |
| `python` | ✘ | Python 3 轻量运行环境（`python3-light`） | — |
| `root-password` | ✔ | 设置 root 登录密码 | `openwrt_root_password` |
| `ssh-permission` | ✘ | 修正 `authorized_keys` 权限（600） | — |
| `statistics` | ✘ | collectd 采集 + LuCI 统计图表 | — |
| `system` | ✔ | 时区（`Asia/Shanghai` / `CST-8`）与日志级别 | — |

通过 `openwrt_modules_adjust` 增删模块（`-` 前缀表示移除），或用
`openwrt_modules_override` 完全替换模块集。可通过 `openwrt_extra_packages`
追加软件包（`-` 前缀表示移除）。

## 扩展路径

- **更换目标/Profile**：修改 `host_vars/<host>/main.yml` 中的 `openwrt_image`（可选
  `openwrt_profile`），无需改动其它内容。
- **新增自定义模块**：添加 `roles/imagebuilder/files/overlay/<name>/...`（静态）
  或 `templates/overlay/<name>/...`（模板），并在 `defaults/main.yml` 的
  `openwrt_module_packages` 中加入其软件包、在 `openwrt_known_modules` 中登记。
- **远程构建主机**：修改 `hosts.yml` 以 SSH 方式指向该主机。

## 注意事项

- **构建慢/网速受限**：启用 `openwrt_use_mirror: true`（构建阶段软件源镜像，需带
  OpenWrt 前缀，如 `mirrors.tuna.tsinghua.edu.cn/openwrt`）与/或
  `openwrt_setup_use_mirror: true`（setup.sh 工具链下载）。详见 `docs/runbooks.md`。
- **镜像同步滞后**：国内镜像尚未同步新版本时可能导致构建失败，此时关闭镜像源改用
  官方源。
- **密钥特殊字符**：变量由 Jinja 模板化并自动做 shell 引用；请写入 vault，不要放在
  命令行上。
- **首次运行 / 自动化用户**：preflight 会创建 `ansible` 用户（始终生成密码并写入
  vault；若设置了 `vault_host_ansible_ssh_pubkey_file` 则优先密钥登录；免密 sudo；
  存在 `docker` 组时加入），因此连接用户需具备 sudo。若连接用户仅有 docker 组权限，
  可设置 `provision_ansible_user: false` 跳过。
- **构建产物位置**：先在构建机的 `openwrt_output_dir`
  （默认 `~/.cache/openwrt-builder/artifacts`）生成，再回传到控制机的
  `artifacts/targets/<target>/<subtarget>/`。将 `openwrt_fetch_artifacts` 设为
  `false` 可只保留在构建机；也可用 `openwrt_artifacts_dir` / `openwrt_output_dir`
  自定义路径。

## 许可证

MIT，详见 [LICENSE](./LICENSE)。
