# openwrt-builder-wrapper

基于 **官方 OpenWrt ImageBuilder**（Docker 容器）构建自定义 OpenWrt 固件的
Ansible IaC 项目。

> English version: [README.md](./README.md)

## 工具分工与边界

| 层 | 工具 | 职责 |
|----|------|------|
| 构建主机 | **Docker** | 运行官方 `openwrt/imagebuilder` 容器 |
| 固件镜像 | **Ansible**（role `imagebuilder`） | 模块解析、软件包收集、uci-defaults overlay 渲染、容器编排 |
| 运维配置 | `host_vars/<variant>/main.yml` + `group_vars/builder/main.yml` | 每个变体的构建目标/模块/软件包；机器级共享连接身份 |

## 架构概览

```
make host-bootstrap                           # 一次性：探测 ansible/admin/root 并创建服务账号
  └── ansible-playbook playbooks/bootstrap.yml
                探测（localhost）→ 创建/修复 'ansible'（可选 admin）→ 授权公钥 → sudo

make build
  ├── ansible-playbook playbooks/build.yml   （hosts: builder = 内网构建机；以 'ansible' 身份连接）
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
- **多变体按主机建模**：一个变体 = 一个 inventory 主机 = 一组（目标, Profile,
  设置）；所有变体指向**同一台物理构建机**（`ansible_host` 相同）。每个变体的
  构建配置放在 `host_vars/<variant>/`（目录名与 inventory 主机名一致）；机器级
  共享配置（SSH 身份、服务账号、共享 vault 路径、变体隔离）放在
  `group_vars/builder/`。仅 `example/` 与 `group_vars/builder/` 被提交。
- **变体隔离、并行安全**：`group_vars/builder/main.yml` 用 `inventory_hostname`
  为每个变体分配独立的构建机 scratch/输出目录与控制机产物目录，且容器名带变体
  标识，因此 `make build` 可**并行**构建全部变体而互不干扰。
- **密钥隔离**：连接凭据属于机器，放在共享 vault
  （`inventory/group_vars/builder/vault.yml`）；root 密码、PPPoE 密码等固件密钥
  属于变体，放在各自的 `host_vars/<variant>/vault.yml`，均以 `{{ vault_* }}`
  引用；vault 口令文件保存在仓库之外。自动生成的连接密钥由
  `make host-bootstrap` 写入**始终加密的托管 vault**
  （`inventory/group_vars/builder/vault_managed.yml`），命名为 `<var>_auto`，从而
  让 `vault.yml` 保持由运维维护（未加密的明文 vault 同样可用，直到你将其加密）。
  运维显式提供的值优先于对应 `_auto` 回退值，且已存在的 `_auto` 值永不轮换。
- **`host-bootstrap` 引导服务账号**（移植自 netbird-iac）：它按
  `ansible -> admin -> root` 探测并使用首个可用身份；若不是 `ansible`，则创建/修复
  `ansible` 服务账号（未提供公钥且 `vault_host_ansible_password` 为空时，生成
  `vault_host_ansible_password_auto`、免密 sudo，存在 `docker` 组时加入）。
  各身份的公钥（`vault_host_<id>_ssh_pubkey_file`）会被授权到对应账号。
- **连接身份显式化**（netbird-iac 模型，机器级）：`group_vars/builder/main.yml` 里的
  `host_ssh_identities` 映射把共享 vault 中的
  `vault_host_<id>_{user,password,ssh_privkey_file,ssh_pubkey_file}` 解析为 Ansible
  连接变量，供所有变体共享。日常运行（`build`/`info`）固定以 `ansible` 身份连接；
  只有 `make host-bootstrap` 会探测。SSH 先尝试密钥（显式路径或 agent）再尝试密码，
  且最多一次密码提示。
- **构建期除控制端工具链外只依赖 Docker**（`python` + `ansible-core` +
  `community.docker`）。

## 目录结构

```
openwrt-builder-wrapper/
├── ansible.cfg                        # 规范 Ansible 配置（仓库根即 Ansible 根）
├── inventory/
│   ├── hosts.yml.example              # 构建变体（同一台构建机，多个 variant 主机）
│   ├── group_vars/
│   │   └── builder/                   # 机器级共享配置（已提交）
│   │       ├── main.yml               # SSH 身份、服务账号、共享 vault 路径、变体隔离
│   │       └── vault.yml.example      # 共享连接密钥模板
│   └── host_vars/
│       └── example/                   # 变体模板；真实 variant 目录 gitignore
│           ├── main.yml               # 该变体的构建配置（目标/Profile/模块/软件包）
│           └── vault.yml.example      # 该变体的固件密钥模板
├── playbooks/
│   ├── bootstrap.yml                  # 探测 + 创建服务账号（make host-bootstrap）
│   ├── build.yml                      # 构建固件（make build）
│   └── info.yml                       # 查询 ImageBuilder 信息（make info）
├── roles/imagebuilder/
│   ├── defaults/main.yml              # 模块注册表、软件包列表、默认值
│   ├── tasks/                         # preflight/modules/setup/packages/overlay/build/info
│   ├── files/overlay/<module>/...     # 静态 uci-defaults overlay
│   └── templates/overlay/<module>/    # 模板化 uci-defaults + build.sh.j2
├── requirements.yml                   # collections
├── artifacts/                         # 回传的固件（目录被跟踪，内容 gitignore）
├── docs/runbooks.md
├── .tool-versions                     # 控制端工具链版本（asdf/mise）
├── Makefile                           # 统一编排
└── README.md / README-zh.md
```

## 快速开始

```bash
# 0) 控制端工具链：.tool-versions 固定 python + ansible-core，安装一次即可
mise install           # 或：asdf install

# 1) 为每个变体生成配置目录（目录名须与 inventory 主机名一致）
#    变体名即 inventory 主机名，例如 ib-main / ib-side / ib-ap。
make host-init HOST=ib-main
#    -> 编辑 ib-main/main.yml（构建目标、Profile、模块、软件包）
#       以及 ib-main/vault.yml（该变体的固件密钥：root/PPPoE 密码）
#    -> 对其它变体重复：make host-init HOST=ib-side 等

# 2) 密钥：连接密钥放共享 vault（每台构建机一次），固件密钥放各变体 vault
make install           # 安装 collections + openssl/sshpass/passlib + docker SDK
make vault-init     # 一次性：生成 vault 口令（务必另行备份）
make vault-edit VAULT_FILE=inventory/group_vars/builder/vault.yml  # SSH 连接身份
make vault-edit VARIANT=ib-main   # 该变体的固件密钥

# 3) 引导构建机（一次性）：按 ansible -> admin -> root 探测并创建 'ansible' 服务账号
make host-bootstrap EXTRA='--limit ib-main'   # 只对首个变体（同一台机器）执行

# 4) 构建全部变体（并行；以共享 vault 中的 'ansible' 身份连接）
make build
make build EXTRA='--limit ib-side'   # 或只构建某个变体
```

构建产物先在构建机上生成（每个变体独占
`~/.cache/openwrt-builder/artifacts/<variant>/`）；当 `openwrt_fetch_artifacts`
开启（默认开启）时，role 会将产物回传到控制机的
`artifacts/<variant>/targets/<target>/<subtarget>/`（固件镜像、`profiles.json`、
`sha256sums` 等）。使用 `make info` 可只查询 ImageBuilder 镜像与 Profile 信息、不构建。

> 默认情况下，**控制机**（运行 `make` 的机器）与**构建机**（被控的 Docker 主机）是
> 内网中**两台独立设备**。请在 `inventory/hosts.yml` 中为每个变体填入相同的
> `ansible_host` 指向你的构建机（使用 `hosts.yml.example` 作为模板）；连接身份来自
> `group_vars/builder/main.yml`。也可使用 `ansible_connection: local` 直接在控制机构建。

## 构建多个固件（多变体）

"多变体"把每个（目标, Profile, 设置）组合表示为一个 inventory 主机，所有主机指向
同一台物理构建机。这样：

- 配置声明式、可版本化：每个变体一个 `host_vars/<variant>/main.yml`；
- 一条 `make build` 即可并行构建全部变体（Ansible 默认并行执行同组主机）；
- 变体之间通过独立的 scratch/输出/产物目录与带变体标识的容器名完全隔离。

| 位置 | 作用 |
|------|------|
| `inventory/hosts.yml` | 每个变体一行，`ansible_host` 全部指向同一台构建机 |
| `inventory/group_vars/builder/main.yml` | 机器级共享：SSH 身份、服务账号、共享 vault 路径、变体隔离 |
| `inventory/host_vars/<variant>/main.yml` | 该变体的构建配置（`openwrt_image`、`openwrt_profile`、模块、软件包、LAN IP 等） |
| `inventory/host_vars/<variant>/vault.yml` | 该变体的固件密钥（root/PPPoE 密码） |
| `inventory/group_vars/builder/vault.yml` | 共享连接密钥（每台构建机一份） |

要点：

- 每个变体应设置不同的 `openwrt_profile`（或目标）与 `openwrt_extra_image_name`，
  便于区分产物文件名；产物目录本身已按变体隔离。
- `make build` 默认并行构建全部变体；构建机资源有限时可设 `ANSIBLE_FORKS=1`
  或对单个变体使用 `EXTRA='--limit <variant>'`。
- `make host-bootstrap` 只需执行一次：它只处理首个 `builder` 主机
  （`bootstrap.yml` 使用 `groups['builder'][0]`），且连接凭据是共享的。

## Makefile 目标

| 命令 | 用途 |
|------|------|
| `make host-init HOST=<name>` | 从模板生成 `inventory/` 与 `host_vars/<name>/` |
| `make host-bootstrap` | 探测 ansible → admin → root 并创建服务账号（经 `check-deps` 自动安装 `sshpass`，经 `agent-load` 自动安装 `keychain`） |
| `make build` | 构建自定义固件镜像（ImageBuilder 容器） |
| `make info` | 查询镜像/Profile 信息（不构建） |
| `make install` | 安装控制端依赖 + collections |
| `make lint` | `ansible-playbook --syntax-check` + `ansible-lint` |
| `make vault-init` | 一次性：生成 vault 口令 |
| `make vault-edit` / `vault-view` | 编辑 / 查看 vault 文件（`VAULT_FILE=...` 或 `VARIANT=...`） |
| `make agent-load` | 启动/复用 Keychain ssh-agent 并加载 vault 中的密钥 |
| `make agent-check` | 确认 Keychain ssh-agent 已加载身份 |
| `make agent-setup` | 将 Keychain agent 启动写入 `~/.bashrc`（幂等） |
| `make keychain-verify` | 校验固定版本 Keychain 资产的 SHA256（不安装） |
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

- **新增一个变体**：`make host-init HOST=<variant>`，在 `inventory/hosts.yml` 添加该
  主机（`ansible_host` 指向同一台构建机），再编辑其 `host_vars/<variant>/main.yml`
  （`openwrt_image` / `openwrt_profile` 等），无需改动角色。
- **更换目标/Profile**：修改对应变体的 `host_vars/<variant>/main.yml` 中的
  `openwrt_image`（可选 `openwrt_profile`），无需改动其它内容。
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
- **首次运行 / 自动化用户**：先执行一次 `make host-bootstrap`。它按
  `ansible → admin → root` 探测；若不是以 `ansible` 连接，则创建 `ansible` 服务账号
  （未设置 `vault_host_ansible_ssh_pubkey_file` 且 `vault_host_ansible_password` 为空
  时，生成 `vault_host_ansible_password_auto` 写入托管 vault；免密 sudo；存在 `docker`
  组时加入）。因此首次运行需能以 root 或具备 sudo 的 admin 用户连接；
  若唯一可用账号是 `root`，请在 vault 中设置 `vault_host_root_password`（或 root 私钥）。
- **控制机用哪个私钥？** 各身份可在 vault 中设置私钥路径
  （`vault_host_<id>_ssh_privkey_file`）；未设置时回退到本机 ssh-agent，再回退到
  vault 密码。vault 中只存路径，绝不存私钥内容。
- **ssh-agent + Keychain**：`build`/`info`/`host-bootstrap` 会启动（或复用）固定版本的
  **Keychain 3** agent，并把所有已配置的 `vault_host_<id>_ssh_privkey_file` 加载进去
  （`make agent-load`）；探测顺序为 `ansible → admin → root`。当私钥文件权限过宽
  （如 WSL `/mnt/c` 挂载）时，改用 stdin 加载（`ssh-add - < key`），直接读取私钥内容、
  绕过权限检查。可执行一次 `make agent-setup` 让每个新 shell 自动初始化 agent。
- **构建产物位置**：每个变体先在构建机的 `openwrt_output_dir`
  （默认 `~/.cache/openwrt-builder/artifacts/<variant>`）生成，再回传到控制机的
  `artifacts/<variant>/targets/<target>/<subtarget>/`。将 `openwrt_fetch_artifacts`
  设为 `false` 可只保留在构建机；隔离路径定义在
  `group_vars/builder/main.yml`，也可在变体级别覆盖
  `openwrt_artifacts_dir` / `openwrt_output_dir`。

## 许可证

MIT，详见 [LICENSE](./LICENSE)。
