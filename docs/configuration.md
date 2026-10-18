# Configuration

How the inventory is laid out, the per-variant build schema, module/package
selection, mirrors, and where firmware secrets live.

## Inventory model

One inventory host = one build **machine**; a machine's **variants** live in its
own `host_vars`.

| Location | Purpose |
|----------|---------|
| `inventory/hosts.yml` | the `builder` group: one host per machine, each with its `ansible_host` |
| `inventory/group_vars/all/main.yml` | committed project-owned baseline: `host_ssh_identities` + the connection-plugin interface, the `ansible` account's uid/gid + docker group, the shared vault path |
| `inventory/group_vars/builder/main.yml` | machine-wide operator overrides, local-only (e.g. `host_admin_enabled`) |
| `inventory/host_vars/<machine>/main.yml` | that machine's `openwrt_variants` list |
| `inventory/host_vars/<machine>/vault.yml` | that machine's firmware secrets |
| `inventory/group_vars/builder/vault.yml` | shared connection secrets (one per fleet) |

The committed files are `inventory/hosts.yml.example`, the project-owned baseline
`group_vars/all/main.yml`, and the `group_vars/builder/*.example` +
`host_vars/builder.example/` templates; the real files are gitignored.

## Variant schema

Each entry in a machine's `openwrt_variants` list describes one build. `name` is
required and must be unique within the machine; every other key is optional and
falls back to the role default.

| Key | Meaning |
|-----|---------|
| `name` | Variant name; forms the build id `<machine>-<variant>` |
| `openwrt_image` | **[REQUIRED]** official ImageBuilder image, e.g. `openwrt/imagebuilder:x86-64-25.12.5` |
| `openwrt_profile` | Build profile (empty ⇒ the target's first profile; `make info` lists them) |
| `openwrt_force_pull` | Force a fresh pull of the ImageBuilder image |
| `openwrt_modules_adjust` | Add/remove from the default module set (`-` removes) |
| `openwrt_modules_override` | Replace the module set entirely (names only) |
| `openwrt_extra_packages` | Extra packages appended to the resolved list (`-` removes) |
| `openwrt_extra_image_name` | Suffix appended to the output filename (keep it distinct per variant) |
| `openwrt_disabled_services` | `DISABLED_SERVICES` passed to ImageBuilder |
| `openwrt_rootfs_partsize` | Root partition size in MB (empty ⇒ target default) |
| `openwrt_fetch_artifacts` | Pull built artifacts back to the control node (default `true`) |
| `openwrt_use_mirror` / `openwrt_mirror` | Rewrite package repositories to a mirror (build phase) |
| `openwrt_setup_use_mirror` | Fetch the ImageBuilder tarball from the setup mirror |
| `openwrt_main_lan_ip`, `openwrt_pppoe_username`, `openwrt_pppoe_password`, `openwrt_root_password`, `openwrt_ap_*`, `openwrt_bypass_*` | Module variables (see below) |

## Modules

Default enabled set: `base system root-password pppoe main-router disable-ipv6 extras`.
Enable/disable with `openwrt_modules_adjust` (prefix `-` to remove) or replace the
set with `openwrt_modules_override`. Each module contributes packages and/or
uci-defaults files.

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

## Packages

`openwrt_extra_packages` appends packages (removed with a `-` prefix) to the list
collected from the active modules. `base` is version-aware; the rest come from the
static per-module lists in `roles/imagebuilder/vars/main.yml`
(`openwrt_module_packages`). Adding/removing the same package is a hard error.

## Mirrors

Two independent knobs, both off by default (official OpenWrt sources):

| Knob | Phase | Effect |
|------|-------|--------|
| `openwrt_use_mirror: true` (+ `openwrt_mirror`) | build | rewrites the `repositories(.conf)` host to the mirror (package repos). `openwrt_mirror` must include the mirror's OpenWrt prefix, e.g. `mirrors.tuna.tsinghua.edu.cn/openwrt` |
| `openwrt_setup_use_mirror: true` (+ `openwrt_setup_mirror_url`) | setup | fetches the ImageBuilder tarball via `setup.sh` from the mirror (release and SNAPSHOT), falling back to the official source |

A domestic mirror that has not synced a new release can make a build fail; turn
the mirror off and use the official source. `openwrt_setup_use_mirror` also works
for release images and is the recommended speed-up for SNAPSHOT images.

## Firmware secrets

Per-machine firmware secrets live in `host_vars/<machine>/vault.yml`. Each secret
is a **dict keyed by variant name**, and the matching variant entry reads its own
sub-key, e.g.:

```yaml
# host_vars/<machine>/vault.yml
vault_openwrt_root_password:
  main: CHANGE_ME_main_root_password
  side: CHANGE_ME_side_root_password
vault_openwrt_pppoe_password:
  main: CHANGE_ME_main_pppoe_password
  side: CHANGE_ME_side_pppoe_password
```

```yaml
# host_vars/<machine>/main.yml (excerpt)
openwrt_variants:
  - name: main
    openwrt_root_password: "{{ (vault_openwrt_root_password | default({})).main | default('', true) }}"
    openwrt_pppoe_password: "{{ (vault_openwrt_pppoe_password | default({})).main | default('', true) }}"
  - name: side
    openwrt_root_password: "{{ (vault_openwrt_root_password | default({})).side | default('', true) }}"
    openwrt_pppoe_password: "{{ (vault_openwrt_pppoe_password | default({})).side | default('', true) }}"
```

A variant whose sub-key is empty or absent skips the corresponding module. Edit the
vault with `make vault-edit HOST=<machine>` (it encrypts a plaintext vault first).

## Growth path

- **Another machine**: `make host-init HOST=<machine> HOST_IP=<addr>` and list its
  variants in `host_vars/<machine>/main.yml`.
- **Another variant on a machine**: append an entry to `openwrt_variants` in that
  machine's `main.yml`; no role change.
- **Another target/profile**: change the variant's `openwrt_image` (and optionally
  `openwrt_profile`); nothing else changes.
- **A custom module**: add `roles/imagebuilder/files/overlay/<name>/...` (static) or
  `templates/overlay/<name>/...` (templated) plus its packages in
  `vars/main.yml` (`openwrt_module_packages`), and list `<name>` in
  `openwrt_known_modules`.
