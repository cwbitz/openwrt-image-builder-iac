# Configuration

How the inventory is laid out, the per-variant build schema, module/package
selection, mirrors, and where firmware secrets live.

## Inventory model

One inventory host = one build **machine**; a machine's **variants** live in its
own `host_vars`.

| Location | Purpose |
|----------|---------|
| `inventory/hosts.yml` | the `builder` group: one host per machine, each with its `ansible_host` |
| `inventory/group_vars/all/main.yml` | committed project-owned baseline: `ssh_identities` + the connection-plugin interface, the `ansible` account's uid/gid + docker group, the shared vault path |
| `inventory/group_vars/builder/main.yml` | machine-wide operator overrides, local-only (e.g. `create_admin_account`) |
| `inventory/host_vars/<machine>/main.yml` | that machine's `build_variants` list |
| `inventory/host_vars/<machine>/vault.yml` | that machine's firmware secrets |
| `inventory/group_vars/builder/vault.yml` | shared connection secrets (one per fleet) |
| `inventory/knob_schema.yml` | committed validation expression per top-level operator knob |

The committed files are `inventory/hosts.yml.example`, the project-owned baseline
`group_vars/all/main.yml`, and the `group_vars/builder/*.example` +
`host_vars/example/` templates; the real files are gitignored.

## Knob validation

`inventory/knob_schema.yml` declares one validation expression per top-level
operator knob, and `playbooks/validate_knobs.yml` asserts every value against it
plus the structure of each `build_variants` entry. `make lint` and `make build`
run it before any change, so a malformed knob fails with its name and the
received value instead of midway through a build. The schema must cover every
top-level key of `inventory/host_vars/example/main.yml`; the play fails when they
drift apart.

## Variant schema

Each entry in a machine's `build_variants` list describes one build. `name` is
required and must be unique within the machine; every other key is optional and
falls back to the role default.

| Key | Meaning |
|-----|---------|
| `name` | Variant name; forms the build id `<machine>-<variant>` |
| `imagebuilder_image` | **[REQUIRED]** official ImageBuilder image, e.g. `openwrt/imagebuilder:x86-64-25.12.5` |
| `target_profile` | Build profile (empty ⇒ the target's first profile; `make info` lists them) |
| `force_pull` | Force a fresh pull of the ImageBuilder image |
| `modules_adjust` | Add/remove from the default module set (`-` removes) |
| `modules_override` | Replace the module set entirely (names only) |
| `extra_packages` | Extra packages appended to the resolved list (`-` removes) |
| `extra_image_name` | Suffix appended to the output filename (keep it distinct per variant) |
| `disabled_services` | `DISABLED_SERVICES` passed to ImageBuilder |
| `rootfs_partsize` | Root partition size in MB (empty ⇒ target default) |
| `fetch_artifacts` | Pull built artifacts back to the control node (default `true`) |
| `use_mirror` / `mirror` | Rewrite package repositories to a mirror (build phase) |
| `setup_use_mirror` | Fetch the ImageBuilder tarball from the setup mirror |
| `lan_ip` / `gateway` / `dns` / `disable_dhcp` / `pppoe_username` | Module variables shared by the role's templates (see below) |

`pppoe_password` / `root_password` are **not** variant keys: they come from the
machine vault, joined by variant name (see [Firmware secrets](#firmware-secrets)).

## Modules

Default enabled set: `base system root-password pppoe main-router disable-ipv6 extras`.
Enable/disable with `modules_adjust` (prefix `-` to remove) or replace the
set with `modules_override`. Each module contributes packages and/or
uci-defaults files.

| Module | Default | Description | Variables |
|--------|:---:|-------------|-----------|
| `ap` | ✘ | Wireless access point: LAN gateway/DNS point at the main router, optional DHCP off | `lan_ip`, `gateway`, `dns`, `disable_dhcp` |
| `base` | ✔ | Base packages (LuCI, `dnsmasq-full`, `wpad-mbedtls`, Chinese i18n), version-aware | — |
| `bypass-router` | ✘ | Bypass router: LAN gateway/DNS point at the main router, optional DHCP off | `lan_ip`, `gateway`, `dns`, `disable_dhcp` |
| `disable-ipv6` | ✔ | Disable IPv6 / RA / DHCPv6 on LAN and WAN | — |
| `extras` | ✔ | Common diagnostics (`curl`, `vim-full`, `tcpdump`, `conntrack`, ...) | — |
| `main-router` | ✔ | Set the main router LAN IP | `lan_ip` |
| `pppoe` | ✔ | Configure WAN PPPoE credentials | `pppoe_username`; `pppoe_password` from the vault |
| `prefer-ipv6` | ✘ | IPv6 preference / RA tuning | — |
| `python` | ✘ | Lightweight Python 3 runtime (`python3-light`) | — |
| `root-password` | ✔ | Set the root login password | `root_password` from the vault |
| `ssh-permission` | ✘ | Fix `authorized_keys` permissions (600) | — |
| `statistics` | ✘ | collectd + LuCI statistics | — |
| `system` | ✔ | Timezone (`Asia/Shanghai` / `CST-8`) and log levels | — |

## Packages

`extra_packages` appends packages (removed with a `-` prefix) to the list
collected from the active modules. `base` is version-aware; the rest come from the
static per-module lists in `roles/imagebuilder/vars/main.yml`
(`module_packages`). Adding/removing the same package is a hard error.

## Mirrors

Two independent knobs, both off by default (official OpenWrt sources):

| Knob | Phase | Effect |
|------|-------|--------|
| `use_mirror: true` (+ `mirror`) | build | rewrites the `repositories(.conf)` host to the mirror (package repos). `mirror` must include the mirror's OpenWrt prefix, e.g. `mirrors.tuna.tsinghua.edu.cn/openwrt` |
| `setup_use_mirror: true` (+ `setup_mirror_url`) | setup | fetches the ImageBuilder tarball via `setup.sh` from the mirror (release and SNAPSHOT), falling back to the official source |

A domestic mirror that has not synced a new release can make a build fail; turn
the mirror off and use the official source. `setup_use_mirror` also works
for release images and is the recommended speed-up for SNAPSHOT images.

## Host security (SSH hardening)

`roles/sshd` optionally closes password login on the build machine and disables
root SSH, applied as a drop-in under `/etc/ssh/sshd_config.d/` — the running
`sshd_config` is never edited. It is OFF by default and runs at the end of
`make build` / `make deploy` (tag `sshd`).

| Knob | Default | Effect |
|------|---------|--------|
| `sshd_hardening_enabled` | `false` | Apply the hardening drop-in |
| `sshd_permit_root_login` | `"no"` | `no` disables root SSH; `prohibit-password` keeps root reachable by key |

It only proceeds when a key-only login survives it: the `ansible` account's
public key (`host_ansible_ssh_pubkey_file`) or, for a root-administered
host, root's key with `sshd_permit_root_login: prohibit-password`. The role
verifies the effective configuration (`sshd -T`), proves a key-only login from
the control node and rolls the drop-in back if either check fails.

## Firmware secrets

Per-machine firmware secrets live in `host_vars/<machine>/vault.yml`. Each secret
is a **dict keyed by variant name**; the role looks the current variant up by its
`name`, so `host_vars/<machine>/main.yml` carries no wiring and cannot hold an
inline plaintext secret:

```yaml
# host_vars/<machine>/vault.yml
vault_openwrt_root_password:
  main: CHANGE_ME_main_root_password
  ap: CHANGE_ME_ap_root_password
vault_openwrt_pppoe_password:
  main: CHANGE_ME_main_pppoe_password
  ap: CHANGE_ME_ap_pppoe_password
```

The committed bridge in `inventory/group_vars/all/main.yml` maps those vault keys
onto the role's generic `firmware_secrets` input, and the role joins each variant
by name:

```yaml
# inventory/group_vars/all/main.yml (excerpt)
firmware_secrets:
  root_password: "{{ vault_openwrt_root_password | default({}) }}"
  pppoe_password: "{{ vault_openwrt_pppoe_password | default({}) }}"
```

A variant whose sub-key is empty or absent skips the corresponding module, so one
vault can serve a PPPoE router and an AP on the same machine. `make lint` checks
that every example variant has a sub-key in both dicts (and that no sub-key names
a missing variant). Edit the vault with `make vault-edit HOST=<machine>` (it
encrypts a plaintext vault first).

## Growth path

- **Another machine**: `make host-init HOST=<machine> HOST_IP=<addr>` and list its
  variants in `host_vars/<machine>/main.yml`.
- **Another variant on a machine**: append an entry to `build_variants` in that
  machine's `main.yml`; no role change.
- **Another target/profile**: change the variant's `imagebuilder_image` (and optionally
  `target_profile`); nothing else changes.
- **A custom module**: add `roles/imagebuilder/files/overlay/<name>/...` (static) or
  `templates/overlay/<name>/...` (templated) plus its packages in
  `vars/main.yml` (`module_packages`), and list `<name>` in
  `known_modules`.
