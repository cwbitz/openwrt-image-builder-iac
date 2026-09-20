# openwrt-builder-wrapper

Ansible IaC that builds customized OpenWrt firmware images with the **official
OpenWrt ImageBuilder** running in a Docker container.

> Chinese version: [README-zh.md](./README-zh.md)

## Tooling Split & Boundaries

| Layer | Tool | Responsibility |
|-------|------|----------------|
| Build host | **Docker** | runs the official `openwrt/imagebuilder` container |
| Firmware image | **Ansible** (role `imagebuilder`) | module resolution, package collection, uci-defaults overlay, container orchestration |
| Operator config | `host_vars/<host>/main.yml` + `vault.yml` | build target, modules, packages, secrets |

## Architecture Overview

```
make build
  ├── ansible-playbook ansible/playbooks/build.yml   (hosts: builder = a LAN build host)
  │     └── roles/imagebuilder
  │           preflight → modules → setup → packages → overlay → build
  │                                                       └── community.docker.docker_container(
  │                                                             openwrt/imagebuilder)
  └── (optional) fetch artifacts back to the control node's artifacts/
```

Core design decisions:

- **One playbook + one role**: `build.yml` (and `info.yml`) target the `builder`
  host; the role's slices are selected with tags
  (`--tags preflight|modules|setup|packages|overlay|build`).
- **Modules are role-managed**: a default module set
  (`base system root-password pppoe main-router disable-ipv6 extras`) that can be
  adjusted (`openwrt_modules_adjust`) or fully replaced
  (`openwrt_modules_override`). Each module contributes packages and/or
  uci-defaults files.
- **uci-defaults are Jinja templates**: the old build-time `$VARNAME`
  substitution is replaced by Ansible's `template` module; static files are
  copied verbatim. Rendered output is assembled under `.build/files/`.
- **Host-scoped config**: the build host is a single machine, so settings live in
  `host_vars/<host>/` (matching the inventory name) instead of group vars. Only
  the `example/` folder is committed.
- **Secrets are isolated**: the root password, PPPoE password and connection
  credentials live in the host vault (`host_vars/<host>/vault.yml`) and are
  referenced as `{{ vault_* }}`; the vault password stays outside the repo. The
  preflight generates the automation-user password there (plaintext vaults are
  supported until encrypted).
- **Preflight bootstraps the automation user** (mirroring proxmox-iac): an
  `ansible` account is always given a generated password (into the vault), an
  optional public key is installed (key login preferred, password fallback), and
  passwordless sudo is granted; the user is added to the `docker` group when it
  exists (`provision_ansible_user`, on by default).
- **Least-privilege connection probe**: every run probes the build host and
  connects as `ansible` first, then an optional `admin` user, then `root`
  (key before password, only configured credentials). The chosen profile is
  injected per host; the inventory sets no connection user.
- **Docker is the only build-time dependency** beyond the control-node
  toolchain (`python` + `ansible-core` + `community.docker`).

## Directory Layout

```
openwrt-builder-wrapper/
├── ansible/
│   ├── inventory/
│   │   ├── hosts.yml.example            # builder host (one LAN machine)
│   │   └── host_vars/
│   │       └── example/                 # committed template; real hosts gitignored
│   │           ├── main.yml             # operator entry point (build config)
│   │           └── vault.yml.example    # secrets template (passwords/keys)
│   ├── playbooks/
│   │   ├── build.yml                    # build firmware (make build)
│   │   └── info.yml                     # query ImageBuilder info (make info)
│   ├── roles/imagebuilder/
│   │   ├── defaults/main.yml            # module registry, package lists, defaults
│   │   ├── tasks/                       # preflight/modules/setup/packages/overlay/build/info
│   │   ├── files/overlay/<module>/...   # static uci-defaults overlay
│   │   └── templates/overlay/<module>/  # templated uci-defaults + build.sh.j2
│   ├── requirements.yml                 # collections
│   └── ansible.cfg
├── artifacts/                           # fetched firmware (dir tracked; contents gitignored)
├── docs/runbooks.md
├── .tool-versions                       # pinned control-node toolchain (asdf/mise)
├── Makefile                             # unified orchestration
└── README.md / README-zh.md
```

## Quick Start

```bash
# 0) Control-node toolchain: asdf/mise pin python + ansible-core in
#    .tool-versions. Install them once:
mise install           # or: asdf install

# 1) Inventory + host-scoped config (copy the committed examples; the host
#    directory name must match the inventory host name)
cp ansible/inventory/hosts.yml.example ansible/inventory/hosts.yml
cp -r ansible/inventory/host_vars/example ansible/inventory/host_vars/openwrt-ib-prod-1
#    -> edit openwrt-ib-prod-1/main.yml (build target, modules) and rename
#       vault.yml.example -> vault.yml

# 2) Secrets: create the vault password and (optionally) encrypt the vault
make ans-deps           # collections + openssl/sshpass/passlib + docker SDK
make ans-vault-init     # one-time: vault password (back it up)
make ans-vault-edit HOST=openwrt-ib-prod-1   # fill key path + firmware secrets

# 3) The preflight provisions the 'ansible' automation user on the build host
#    (first run connects as root or a sudo-capable user); each run probes and
#    connects as 'ansible' first, then admin, then root.
make build
```

The builder produces the image on the build host (under
`~/.cache/openwrt-builder/artifacts`), and when `openwrt_fetch_artifacts` is
enabled (the default) the role pulls it back into the control node's
`artifacts/targets/<target>/<subtarget>/` (firmware images, `profiles.json`,
`sha256sums`, ...). Use `make info` to inspect the ImageBuilder image and profile
information without building.

> By default the **control node** (where you run `make`) and the **build host**
> (the managed machine running Docker) are **two separate machines on the LAN**.
> Edit `ansible/inventory/hosts.yml` (`ansible_host`, and `ansible_user` if
> needed) to point at your builder. Building on the control node itself is also
> possible (`ansible_connection: local`).

## Makefile Targets

| Command | Purpose |
|---------|---------|
| `make build` | Build a customized firmware image (ImageBuilder container) |
| `make info` | Query image/profile information (no build) |
| `make ans-deps` | Install control-node prerequisites + collections |
| `make ans-lint` | `ansible-playbook --syntax-check` + `ansible-lint` |
| `make ans-vault-init` | One-time: generate the vault password |
| `make ans-vault-edit` / `ans-vault-view` | Edit / view a vault file (`FILE=...`) |
| `make clean` | Remove caches, collections and build scratch |

## Modules

Default enabled set: `base system root-password pppoe main-router disable-ipv6 extras`.

| Module | Default | Description | Variables |
|--------|:---:|-------------|-----------|
| `ap` | ✘ | Wireless access point: LAN gateway/DNS point at the main router, optional DHCP off | `openwrt_ap_lan_ip`, `openwrt_ap_gateway`, `openwrt_ap_dns`, `openwrt_ap_disable_dhcp` |
| `base` | ✔ | Base packages (LuCI, `dnsmasq-full`, `wpad-mbedtls`, Chinese i18n), version-aware | — |
| `bypass-router` | ✘ | Bypass router: LAN gateway/DNS point at the main router, optional DHCP off | `openwrt_bypass_lan_ip`, `openwrt_bypass_gateway`, `openwrt_bypass_dns`, `openwrt_bypass_disable_dhcp` |
| `disable-ipv6` | ✔ | Disable IPv6 / RA / DHCPv6 on LAN and WAN | — |
| `extras` | ✔ | Common diagnostics (`curl`, `vim-full`, `tcpdump`, `conntrack`, ...) | — |
| `main-router` | ✔ | Set the main router LAN IP | `openwrt_main_lan_ip` |
| `pppoe` | ✔ | Configure WAN PPPoE credentials | `openwrt_pppoe_username`, `openwrt_pppoe_password` |
| `prefer-ipv6` | ✘ | IPv6 preference / RA tuning | — |
| `python` | ✘ | Lightweight Python 3 runtime (`python3-light`) | — |
| `root-password` | ✔ | Set the root login password | `openwrt_root_password` |
| `ssh-permission` | ✘ | Fix `authorized_keys` permissions (600) | — |
| `statistics` | ✘ | collectd + LuCI statistics | — |
| `system` | ✔ | Timezone (`Asia/Shanghai` / `CST-8`) and log levels | — |

Enable/disable modules with `openwrt_modules_adjust` (prefix `-` to remove) or
replace the set entirely with `openwrt_modules_override`. Extra packages can be
appended (or removed with a `-` prefix) via `openwrt_extra_packages`.

## Growth Path

- **Another target/profile**: change `openwrt_image` (and optionally
  `openwrt_profile`) in `host_vars/<host>/main.yml`; nothing else changes.
- **A custom module**: add `roles/imagebuilder/files/overlay/<name>/...` (static)
  or `templates/overlay/<name>/...` (templated) plus its packages in
  `defaults/main.yml` (`openwrt_module_packages`), and list `<name>` in
  `openwrt_known_modules`.
- **A remote Docker builder**: edit `hosts.yml` to target the host over SSH.

## Notes & FAQ

- **Slow downloads**: enable `openwrt_use_mirror: true` (build-phase package
  repositories) and/or `openwrt_setup_use_mirror: true` (setup.sh tool packages,
  SNAPSHOT only). See `docs/runbooks.md`.
- **Mirror sync lag**: a domestic mirror that has not synced a new release can
  make the build fail; turn the mirror off and use the official source.
- **Special characters in secrets**: values are Jinja-templated and shell-quoted
  automatically; put them in the vault rather than on the command line.
- **First run / automation user**: the preflight creates the `ansible` user
  (a generated password is always stored in the vault; an optional key from
  `vault_host_ansible_ssh_pubkey_file` is preferred; NOPASSWD sudo; added to the
  `docker` group when present), so the connection user needs sudo. Set
  `provision_ansible_user: false` to skip it (e.g. when the connection user only
  has Docker group access).
- **Where do the images go?** Built on the builder under `openwrt_output_dir`
  (`~/.cache/openwrt-builder/artifacts` by default), then fetched to the control
  node's `artifacts/targets/<target>/<subtarget>/` when
  `openwrt_fetch_artifacts` is true (the default). Set
  `openwrt_fetch_artifacts: false` to keep them only on the builder, or override
  `openwrt_artifacts_dir` / `openwrt_output_dir`.

## License

MIT — see [LICENSE](./LICENSE).
