# Configuration

How the inventory is laid out, the per-variant build schema, module/package
selection, network/system/statistics settings, mirrors, and where firmware
secrets live.

## Inventory model

One inventory host = one build **machine**; a machine's **variants** live in its
own `host_vars`.

| Location | Purpose |
|----------|---------|
| `inventory/hosts.yml` | the `builders` group: one host per machine, each with its `ansible_host` |
| `inventory/group_vars/all/main.yml` | committed project-owned baseline: `ssh_identities` + the connection-plugin interface, the `iac` account's uid/gid + docker group, the shared vault path |
| `inventory/group_vars/builders/main.yml` | machine-wide operator overrides, local-only (e.g. `create_admin_account`) |
| `inventory/host_vars/<machine>/main.yml` | that machine's `build_variants` list |
| `inventory/group_vars/builders/vault.yml` | shared connection secrets (one per fleet) |
| `inventory/knob_schema.yml` | committed validation expression per top-level operator knob |

The committed files are `inventory/hosts.yml.example`, the project-owned baseline
`group_vars/all/main.yml`, and the `group_vars/builders/*.example` +
`host_vars/example/` templates; the real files are gitignored.

## Knob validation

`inventory/knob_schema.yml` declares one validation expression per top-level
operator knob, and `playbooks/validate_knobs.yml` asserts every value against it
plus the structure of each `build_variants` entry (including the nested
`network`, `system`, and `statistics` blocks). `make lint` and `make build` run
it before any change, so a malformed knob fails with its name and the received
value instead of midway through a build. The schema must cover every top-level
key of `inventory/host_vars/example/main.yml`; the play fails when they drift
apart.

## Variant schema

Each entry in a machine's `build_variants` list describes one build. `name` is
required and must be unique within the machine; every other key is optional and
falls back to the role default.

| Key | Meaning |
|-----|---------|
| `name` | Variant name; forms the build id `<machine>-<variant>` |
| `imagebuilder_image` | **[REQUIRED]** official ImageBuilder image (`openwrt/imagebuilder:<tag>`) |
| `target_profile` | Build profile (empty ⇒ the target's first profile; `make info` lists them) |
| `force_pull` | Force a fresh pull of the ImageBuilder image |
| `packages` | Exact package list passed to ImageBuilder (`-pkg` removes a package) |
| `custom_overlay` | Control-node directory copied over the image rootfs after modules (see [Custom overlay](#custom-overlay)) |
| `network` | LAN first-boot configuration (see [Network](#network)) |
| `system` / `disable-ipv6` / `statistics` / `administration` | Module mappings; each has an `enabled` flag (see [Modules](#modules)) |
| `extra_firmware_name` | Tag inserted into the output filename after the version; ImageBuilder adds the separators (keep it distinct per variant) |
| `disabled_services` | Space-separated init.d service names to disable in the image |
| `rootfs_partsize` | Root filesystem partition size in MB, 64–32768 (empty ⇒ target default) |
| `use_mirror` / `mirror` | Use `mirror` for package repos and the setup tarball (release images) |

`imagebuilder_image` tags follow `<target>-<subtarget>[-<version>]` or
`<arch>[-<version>]` (see hub.docker.com/r/openwrt/imagebuilder/tags). The
example carries a placeholder that preflight refuses until it is replaced.

No firmware secrets are baked into the image: set the WAN (PPPoE/DHCP) and the
root password after first boot.

## Modules

A module is enabled by its own `enabled` flag (default `false`); there is no
separate module list. A module contributes first-boot overlay files; packages
are explicit in `packages` unless the module manages them (`statistics` does).

| Module | Description | Variant keys |
|--------|-------------|--------------|
| `system` | Hostname, timezone, and zonename | `enabled`, `hostname`, `timezone`, `zonename` |
| `disable-ipv6` | Disable IPv6, RA, and DHCPv6 on LAN/WAN | `enabled` |
| `statistics` | collectd + LuCI statistics configuration | `enabled`, `interfaces`, `sensors`, `irq`, `rrd_timespans` |
| `administration` | Initial root password, SSH listen interface/port, `authorized_keys` permissions | `enabled`, `root_password`, `ssh.interface`, `ssh.port` |

`network` is **not** a module: when a variant's `network` block is non-empty,
the role renders it independently of the module flags.

## Packages

`packages` is the operator's list passed to ImageBuilder. Prefix a name with `-`
to remove it from the base image (for example `-dnsmasq` + `dnsmasq-full`).
Duplicate entries are deduplicated; adding and removing the same package is a
hard error.

The `statistics` module owns its packages: it removes any
`luci-app-statistics` / `collectd-mod-*` entries from this list and adds the
set matching the enabled features. Listing them here is harmless.

The previous base set is in `inventory/host_vars/example/main.yml` and can be
copied per variant. The LuCI package-manager translation is explicit too:
`luci-i18n-package-manager-zh-cn` on 24.10+ (APK), `luci-i18n-opkg-zh-cn` on
older releases.

To resize a rootfs on the device, include `e2fsprogs` (`resize2fs`), `parted`,
and `fdisk` in `packages`.

### Ansible management

To let Ansible manage the built router with Python-based modules, include these
packages:

| Package | Purpose |
|---------|---------|
| `python3` | Full Python 3 + standard library (pulls `python3-light`, `python3-openssl`, `python3-urllib`, `python3-email`, `python3-logging`, `python3-ctypes`, ...) — the target interpreter for Ansible modules |
| `ca-bundle` | CA certificates for HTTPS/TLS verification (`get_url`, `uri`, feed downloads) |
| `openssh-sftp-server` | SFTP subsystem for Ansible's file transfer |
| `rsync` | `synchronize` module |

Optional, depending on the modules you use: `python3-cryptography` (crypto
modules), `git` (git module), `unzip`/`tar` (unarchive), `python3-pip` (pip
module). If flash is tight, `python3-light` plus the specific `python3-*`
subpackages (`python3-openssl`, `python3-urllib`, `python3-email`,
`python3-logging`) is a smaller alternative to the full `python3`.

`curl`, `vim-full`, `diffutils`, `bind-dig`, `nping`, `conntrack`, and `tcpdump`
are diagnostics; they are useful but not required by Ansible.

## Network

The `network` block configures LAN only; WAN (DHCP/PPPoE) is configured after
first boot. It replaces the former `main-router` / `bypass-router` / `ap` /
`pppoe` modules.

```yaml
network:
  lan_ip: 192.0.2.1/24
  gateway: ""
  dns: []
  dhcp: true
```

| Key | Meaning |
|-----|---------|
| `lan_ip` | LAN static address (CIDR); empty ⇒ unchanged |
| `gateway` | LAN gateway; empty ⇒ unchanged (main router) |
| `dns` | LAN DNS list; empty ⇒ unchanged |
| `dhcp` | `false` disables the LAN DHCP server (AP/bypass); `true` leaves it on |

- **Main router**: set `lan_ip`, keep `gateway`/`dns` empty and `dhcp: true`.
- **AP / bypass router**: set `lan_ip`, `gateway`, `dns`, and `dhcp: false`.

## System

The `system` module sets the hostname, timezone, and zonename. The hostname
default is empty (keep the base image hostname); the timezone/zonename defaults
are `CST-8` / `Asia/Shanghai`.

```yaml
system:
  enabled: true
  hostname: "openwrt-main"
  timezone: "CST-8"
  zonename: "Asia/Shanghai"
```

When enabled, the module renders `etc/uci-defaults/91-system`. The log levels
(`conloglevel` / `cronloglevel`) are intentionally not part of the build: the
image keeps the base image's defaults and they can be adjusted after boot.

## Statistics

The `statistics` module configures collectd/LuCI statistics; the interface list
is no longer hardcoded.

```yaml
statistics:
  enabled: true
  interfaces: [br-lan, eth1]
  sensors: true
  irq: true
  rrd_timespans: [2hour, 1day, 1week, 1month, 1year]
```

| Key | Default | Meaning |
|-----|---------|---------|
| `enabled` | `false` | Enable the module |
| `interfaces` | `[]` | Interfaces collected by the interface plugin; empty disables it |
| `sensors` | `false` | Enable hardware sensors (`collectd-mod-sensors`) |
| `irq` | `false` | Enable IRQ statistics (`collectd-mod-irq`) |
| `rrd_timespans` | `[2hour, 1day, 1week, 1month, 1year]` | RRD history spans |

The `statistics` module installs its packages (and removes any duplicate
entries from `packages`): `luci-app-statistics` is always added, plus
`collectd-mod-sensors` when `sensors` is true and `collectd-mod-irq` when `irq`
is true.

RRD stands for **Round Robin Database**: a fixed-size circular time-series store
that RRDtool writes and LuCI graphs. RRD data writes to flash; enable it only if
you need the graphs.

## Custom overlay

For anything not covered by a module, set `custom_overlay` to a directory on the
control node. The role copies it over the image rootfs **after** the module
overlays, so it can add files or override module files:

```yaml
custom_overlay: "{{ inventory_dir }}/custom/{{ inventory_hostname }}/{{ build_variant.name }}"
```

Layout (per machine and variant; `inventory/custom/` is gitignored):

```text
inventory/custom/<machine>/<variant>/
├── etc/uci-defaults/90-custom     # chmod +x; runs on first boot
└── etc/config/...                 # plain files copied verbatim
```

Example `etc/uci-defaults/90-custom`:

```sh
#!/bin/sh
uci set system.@system[0].hostname='custom-router'
uci set network.lan.domain='example.lan'
uci commit system
uci commit network
```

The role preserves file modes, so `chmod +x` the uci-defaults script. Use a
separate directory per variant when the values differ. Custom files may contain
secrets; keep `inventory/custom/` out of version control.

For a reusable feature, add a module to the role instead (`module_names` +
`files/overlay/<name>` or `templates/overlay/<name>`); `custom_overlay` is for
operator-specific one-offs.

## Administration

The `administration` module renders the LuCI Administration settings:

```yaml
administration:
  enabled: true
  root_password: ""     # empty = keep the system default; setting it bakes a secret
  ssh:
    interface: ""       # empty = listen on all; e.g. "lan"
    port: ""            # empty = default 22; e.g. "22"
```

- `root_password`: optional **initial** root password; the first-boot script
  sets it once, and you change it after login. Setting it bakes that initial
  password into the image; leave it empty to keep the system default.
- `ssh.interface`: binds dropbear to that interface (`_direct=1` +
  `DirectInterface`); empty keeps the system default.
- `ssh.port`: sets `dropbear.Port`; empty keeps the default (22).

## Mirrors

One knob, off by default (official OpenWrt sources). `mirror` is a complete base
URL — scheme, host and the mirror's OpenWrt path — e.g.
`https://mirrors.tuna.tsinghua.edu.cn/openwrt`.

| Knob | Effect |
|------|--------|
| `use_mirror: true` (+ `mirror`) | rewrites the package repositories to `mirror` and fetches the ImageBuilder tarball from it; the setup tarball falls back to the official source |

`use_mirror` applies to release images only. SNAPSHOT images always use the
official `downloads.openwrt.org` source: no mirror carries `snapshots/`, so
`mirror` is ignored for them. A domestic mirror that has not synced a new
release can make a release build fail; turn the mirror off and use the official
source.

## Host security (SSH hardening)

`roles/sshd` optionally closes password login on the build machine and disables
root SSH, applied as a drop-in under `/etc/ssh/sshd_config.d/` — the running
`sshd_config` is never edited. It is OFF by default and runs at the end of
`make build` / `make deploy` (tag `sshd`).

| Knob | Default | Effect |
|------|---------|--------|
| `sshd_hardening_enabled` | `false` | Apply the hardening drop-in |
| `sshd_permit_root_login` | `"no"` | `no` disables root SSH; `prohibit-password` keeps root reachable by key |

It only proceeds when a key-only login survives it: the `iac` account's
public key (`host_iac_ssh_pubkey_file`) or, for a root-administered
host, root's key with `sshd_permit_root_login: prohibit-password`. The role
verifies the effective configuration (`sshd -T`), proves a key-only login from
the control node and rolls the drop-in back if either check fails.

## Firmware secrets

No firmware secrets are baked into the image. The WAN (PPPoE/DHCP) and root
passwords are set after first boot (or by a separate provisioning mechanism), so
the built artifact contains no credentials. There is no per-machine firmware
vault; connection credentials live in `group_vars/builders/vault.yml`.

## Growth path

- **Another machine**: `make host-init HOST=<machine> HOST_IP=<addr>` and list its
  variants in `host_vars/<machine>/main.yml`.
- **Another variant on a machine**: append an entry to `build_variants` in that
  machine's `main.yml`; no role change.
- **Another target/profile**: change the variant's `imagebuilder_image` (and optionally
  `target_profile`); nothing else changes.
- **A custom module**: add `roles/imagebuilder/files/overlay/<name>/...` (static)
  or `templates/overlay/<name>/...` (templated), add `<name>` to `module_names`
  in `roles/imagebuilder/vars/main.yml`, and add an `<name>:` mapping with
  `enabled` plus its variant keys. Its packages stay explicit in `packages`.
