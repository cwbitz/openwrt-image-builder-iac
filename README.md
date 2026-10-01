# openwrt-builder-wrapper

Ansible IaC that builds customized OpenWrt firmware images with the **official
OpenWrt ImageBuilder** running in a Docker container.

> Chinese version: [README-zh.md](./README-zh.md)

## Tooling Split & Boundaries

| Layer | Tool | Responsibility |
|-------|------|----------------|
| Build host | **Docker** | runs the official `openwrt/imagebuilder` container |
| Firmware image | **Ansible** (role `imagebuilder`) | module resolution, package collection, uci-defaults overlay, container orchestration |
| Operator config | `host_vars/<variant>/main.yml` + `group_vars/builder/main.yml` | per-variant target/modules/packages; machine-wide connection identity |

## Architecture Overview

```
make host-bootstrap                           # once: probe ansible/admin/root, provision the service account
  └── ansible-playbook playbooks/bootstrap.yml
                probe (localhost) → create/repair 'ansible' (+ optional admin) → authorize keys → sudo

make build
  ├── ansible-playbook playbooks/build.yml   (hosts: builder = a LAN build host; connects as 'ansible')
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
- **Multi-variant, host-modelled config**: one variant = one inventory host =
  one (target, profile, settings) combination; every variant points at the SAME
  physical build machine. Per-variant build settings live in
  `host_vars/<variant>/` (matching the inventory name); machine-wide settings
  (SSH identity, service account, shared vault paths, variant isolation) live in
  `group_vars/builder/`. Only `example/` and `group_vars/builder/` are committed.
- **Variant isolation, parallel-safe**: `group_vars/builder/main.yml` derives a
  per-variant builder-side scratch/output directory and control-node artifact
  directory from `inventory_hostname`, and the container name carries the
  variant, so `make build` can build every variant in PARALLEL without clashes.
- **Secrets are isolated**: connection credentials belong to the machine and
  live in the shared vault (`inventory/group_vars/builder/vault.yml`); firmware
  secrets (root/PPPoE passwords) belong to a variant and live in each
  `host_vars/<variant>/vault.yml`. Both are referenced as `{{ vault_* }}`; the
  vault password stays outside the repo. Auto-generated connection secrets are
  written by `make host-bootstrap` into an always-encrypted **managed** vault
  (`inventory/group_vars/builder/vault_managed.yml`) as `<var>_auto`, so
  `vault.yml` stays operator-owned (plaintext vaults are supported until
  encrypted). An operator value always wins over its `_auto` fallback and an
  existing `_auto` value is never rotated.
- **`host-bootstrap` provisions the service account** (ported from netbird-iac):
  it probes `ansible -> admin -> root` and uses the first identity that works;
  when that is not `ansible` it (re)creates the `ansible` service account (an
  empty `vault_host_ansible_password` triggers a generated
  `vault_host_ansible_password_auto` unless a public key is supplied, passwordless
  sudo, and the `docker` group when present). Per-identity public keys
  (`vault_host_<id>_ssh_pubkey_file`) are authorized for their account.
- **Connection identity is explicit** (netbird-iac model, machine-wide): the
  identity map `host_ssh_identities` in `group_vars/builder/main.yml` resolves
  the Ansible connection vars from the shared vault (`vault_host_<id>_{user,
  password,ssh_privkey_file,ssh_pubkey_file}`) for every variant. Normal runs
  (`build`/`info`) connect as the `ansible` identity; only `make host-bootstrap`
  probes. SSH prefers a key (explicit path or the agent) then the password,
  capped at one prompt.
- **Docker is the only build-time dependency** beyond the control-node
  toolchain (`python` + `ansible-core` + `community.docker`).

## Directory Layout

```
openwrt-builder-wrapper/
├── ansible.cfg                        # canonical Ansible config (repo root == Ansible root)
├── inventory/
│   ├── hosts.yml.example              # build variants (same builder, many hosts)
│   ├── group_vars/
│   │   └── builder/                   # machine-wide shared config (committed)
│   │       ├── main.yml               # SSH identity, service account, shared vault, variant isolation
│   │       └── vault.yml.example      # shared connection secrets template
│   └── host_vars/
│       └── example/                   # variant template; real variants gitignored
│           ├── main.yml               # per-variant build config (target/profile/modules/packages)
│           └── vault.yml.example      # per-variant firmware secrets template
├── playbooks/
│   ├── bootstrap.yml                  # probe + provision the service account (make host-bootstrap)
│   ├── build.yml                      # build firmware (make build)
│   └── info.yml                       # query ImageBuilder info (make info)
├── roles/imagebuilder/
│   ├── defaults/main.yml              # module registry, package lists, defaults
│   ├── tasks/                         # preflight/modules/setup/packages/overlay/build/info
│   ├── files/overlay/<module>/...     # static uci-defaults overlay
│   └── templates/overlay/<module>/    # templated uci-defaults + build.sh.j2
├── requirements.yml                   # collections
├── artifacts/                         # fetched firmware (dir tracked; contents gitignored)
├── docs/runbooks.md
├── .tool-versions                     # pinned control-node toolchain (asdf/mise)
├── Makefile                           # unified orchestration
└── README.md / README-zh.md
```

## Quick Start

```bash
# 0) Control-node toolchain: asdf/mise pin python + ansible-core in
#    .tool-versions. Install them once:
mise install           # or: asdf install

# 1) Scaffold one config dir per build variant (the dir name must match the
#    inventory host name). Variant names are inventory host names, e.g.
#    ib-main / ib-side / ib-ap.
make host-init HOST=ib-main
#    -> edit ib-main/main.yml (build target, profile, modules, packages)
#       and ib-main/vault.yml (that variant's firmware secrets: root/PPPoE)
#    -> repeat for other variants: make host-init HOST=ib-side

# 2) Secrets: connection secrets go in the shared vault (once per builder);
#    firmware secrets go in each variant's vault.
make install           # collections + openssl/sshpass/passlib + docker SDK
make vault-init     # one-time: vault password (back it up)
make vault-edit VAULT_FILE=inventory/group_vars/builder/vault.yml  # SSH identity
make vault-edit VARIANT=ib-main   # that variant's firmware secrets

# 3) Bootstrap the build host once: probe ansible -> admin -> root and provision
#    the 'ansible' service account (generated password, keys, NOPASSWD sudo).
make host-bootstrap EXTRA='--limit ib-main'   # one host (same machine)

# 4) Build every variant in parallel (connects as the shared 'ansible' identity)
make build
make build EXTRA='--limit ib-side'   # or just one variant
```

The builder produces each variant's image on the build host (under
`~/.cache/openwrt-builder/artifacts/<variant>/`), and when
`openwrt_fetch_artifacts` is enabled (the default) the role pulls it back into
the control node's `artifacts/<variant>/targets/<target>/<subtarget>/` (firmware
images, `profiles.json`, `sha256sums`, ...). Use `make info` to inspect the
ImageBuilder image and profile information without building.

> By default the **control node** (where you run `make`) and the **build host**
> (the managed machine running Docker) are **two separate machines on the LAN**.
> In `inventory/hosts.yml`, give every variant the same `ansible_host` pointing
> at your builder (start from `hosts.yml.example`); the connection identity comes
> from `group_vars/builder/main.yml`. Building on the control node itself is also
> possible (`ansible_connection: local`).

## Building multiple firmwares (variants)

A "variant" is one (target, profile, settings) combination, modelled as one
inventory host; all variants point at the same physical builder. This makes the
configuration declarative and version-controlled, lets one `make build` build
every variant in parallel (Ansible runs hosts in a group concurrently), and
keeps variants isolated through per-variant scratch/output/artifact directories
and a variant-scoped container name.

| Location | Purpose |
|----------|---------|
| `inventory/hosts.yml` | one line per variant, all sharing `ansible_host` (the builder) |
| `inventory/group_vars/builder/main.yml` | machine-wide: SSH identity, service account, shared vault paths, variant isolation |
| `inventory/host_vars/<variant>/main.yml` | that variant's build config (`openwrt_image`, `openwrt_profile`, modules, packages, LAN IP, ...) |
| `inventory/host_vars/<variant>/vault.yml` | that variant's firmware secrets (root/PPPoE) |
| `inventory/group_vars/builder/vault.yml` | shared connection secrets (one per builder) |

Notes:

- Give each variant a different `openwrt_profile` (or target) and a distinct
  `openwrt_extra_image_name` so artifact filenames stay distinguishable; the
  artifact directories are already isolated per variant.
- `make build` builds all variants in parallel; on a constrained builder set
  `ANSIBLE_FORKS=1`, or target one variant with `EXTRA='--limit <variant>'`.
- `make host-bootstrap` runs once only: it handles just the first `builder` host
  (`bootstrap.yml` uses `groups['builder'][0]`), and the credentials are shared.

## Makefile Targets

| Command | Purpose |
|---------|---------|
| `make host-init HOST=<name>` | Scaffold `inventory/` + `host_vars/<name>/` from the example |
| `make host-bootstrap` | Probe ansible → admin → root and provision the service account |
| `make build` | Build a customized firmware image (ImageBuilder container) |
| `make info` | Query image/profile information (no build) |
| `make install` | Install control-node prerequisites + collections |
| `make lint` | `ansible-playbook --syntax-check` + `ansible-lint` |
| `make vault-init` | One-time: generate the vault password |
| `make vault-edit` / `vault-view` | Edit / view a vault file (`VAULT_FILE=...` or `VARIANT=...`) |
| `make agent-load` | Start/reuse the Keychain ssh-agent and load the vault keys |
| `make agent-check` | Ensure the Keychain ssh-agent has identities loaded |
| `make agent-setup` | Append Keychain agent startup to `~/.bashrc` (idempotent) |
| `make keychain-verify` | Verify the pinned Keychain asset SHA256 (no install) |
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

- **Another variant**: `make host-init HOST=<variant>`, add the host to
  `inventory/hosts.yml` (same `ansible_host` as the builder), and edit
  `host_vars/<variant>/main.yml` (`openwrt_image` / `openwrt_profile`, ...); no
  role change.
- **Another target/profile**: change `openwrt_image` (and optionally
  `openwrt_profile`) in `host_vars/<variant>/main.yml`; nothing else changes.
- **A custom module**: add `roles/imagebuilder/files/overlay/<name>/...` (static)
  or `templates/overlay/<name>/...` (templated) plus its packages in
  `defaults/main.yml` (`openwrt_module_packages`), and list `<name>` in
  `openwrt_known_modules`.
- **A remote Docker builder**: edit `hosts.yml` to target the host over SSH.

## Notes & FAQ

- **Slow downloads**: enable `openwrt_use_mirror: true` (build-phase package
  repositories; include the mirror's OpenWrt prefix, e.g.
  `mirrors.tuna.tsinghua.edu.cn/openwrt`) and/or
  `openwrt_setup_use_mirror: true` (setup.sh ImageBuilder tarball). See
  `docs/runbooks.md`.
- **Mirror sync lag**: a domestic mirror that has not synced a new release can
  make the build fail; turn the mirror off and use the official source.
- **Special characters in secrets**: values are Jinja-templated and shell-quoted
  automatically; put them in the vault rather than on the command line.
- **First run / automation user**: run `make host-bootstrap` once. It probes
  `ansible → admin → root` and, when it does not connect as `ansible`, creates
  the `ansible` service account. With no `vault_host_ansible_ssh_pubkey_file`,
  an empty `vault_host_ansible_password` makes it generate
  `vault_host_ansible_password_auto` in the managed vault (NOPASSWD sudo; added
  to the `docker` group when present), so the first run must reach the host as
  root or a sudo-capable (admin) user. If your only usable account is `root`,
  set `vault_host_root_password` (or a root private key) in the vault.
- **Which key does the control node use?** Each identity may set a private key
  path in the vault (`vault_host_<id>_ssh_privkey_file`); when unset, SSH
  falls back to your running ssh-agent, then to the vault password. The private
  key is never stored as a value in the vault — only its path.
- **ssh-agent + Keychain**: `build`/`info`/`host-bootstrap` start (or reuse) a
  pinned **Keychain 3** agent and load every configured `vault_host_<id>_ssh_privkey_file`
  into it (`make agent-load`). The probe order is `ansible → admin → root`.
  When a key's file permissions are too open (e.g. the WSL `/mnt/c` mount), it is
  loaded via stdin (`ssh-add - < key`), which reads the key content directly and
  bypasses the permission check. Run `make agent-setup` once to initialize the
  agent in every new shell.
- **Where do the images go?** Each variant is built on the builder under
  `openwrt_output_dir` (`~/.cache/openwrt-builder/artifacts/<variant>` by
  default), then fetched to the control node's
  `artifacts/<variant>/targets/<target>/<subtarget>/` when
  `openwrt_fetch_artifacts` is true (the default). Set
  `openwrt_fetch_artifacts: false` to keep them only on the builder. The
  isolation paths are defined in `group_vars/builder/main.yml`; override
  `openwrt_artifacts_dir` / `openwrt_output_dir` per variant if needed.

## License

MIT — see [LICENSE](./LICENSE).
