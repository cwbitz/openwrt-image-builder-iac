# Runbooks

Operational procedures for building OpenWrt firmware with
`openwrt-builder-wrapper`. Read the repo-level
[README](../README.md) first for the architecture and layout.

## 1. Prerequisites

| Requirement | Notes |
|-------------|-------|
| Control node | Where you run `make`; hosts the repo and the Ansible toolchain |
| Build host | A SEPARATE LAN machine (by default) running Docker Engine; SSH-reachable from the control node as the connection user, who must be able to access the Docker daemon |
| sudo (or root) on the build host | Required on the first run for the `ansible` user preflight (skip with `provision_ansible_user: false`) |
| Docker Engine / Desktop | Must be running on the `builder` host |
| python >= 3.8 | Control node; runs `ansible-core` and the `community.docker` modules |
| `ansible-core` + `python` | Pinned in `.tool-versions` (`mise install` / `asdf install`) |
| `community.docker` | Installed into `ansible/collections` by `make ans-deps` |
| `openssl` | Control node; generates secret values (`make check-deps`) |
| `sshpass` | Control node; password SSH during the connection probe (`make check-deps`) |
| `passlib` | Control node; `password_hash` for the automation user (`make check-deps`) |
| vault password | Created once by `make ans-vault-init`; required to store/read generated secrets |
| docker Python SDK | On the **build host** (not the control node); checked by the role preflight |

`make ans-deps` checks and, where safe, installs the control-node prerequisites
(`openssl`, `sshpass`, `passlib`, the `docker` SDK for a local build host). The
Docker CLI, daemon and Python SDK are validated again at run time by the role's
preflight tasks (actionable failure when missing).

## 2. First-time setup

```bash
mise install
cp ansible/inventory/hosts.yml.example ansible/inventory/hosts.yml
# edit hosts.yml: set ansible_host for your LAN build host (ansible_user is
# chosen automatically by the connection probe)
cp -r ansible/inventory/host_vars/example ansible/inventory/host_vars/openwrt-ib-prod-1
# edit openwrt-ib-prod-1/main.yml; mv openwrt-ib-prod-1/vault.yml.example -> vault.yml
make ans-deps
make ans-vault-init
make ans-vault-edit HOST=openwrt-ib-prod-1   # encrypts a plaintext vault first
```

Configuration is **host-scoped** (single build host): `host_vars/<host>/main.yml`
+ `host_vars/<host>/vault.yml`, where `<host>` matches the inventory host name.
`hosts.yml` and every `host_vars/<host>/` directory are gitignored; only
`host_vars/example/` is committed. A `vault.yml` may stay plaintext (mode 0600)
until you encrypt it (`make ans-vault-encrypt HOST=<host>`); the preflight
handles both formats.

### ansible automation user

The preflight provisions an `ansible` account on the build host (mirroring
proxmox-iac `ensure_secrets` + `users`):

- A password is **always** generated into the host vault
  (`vault_host_ansible_password`); existing values are never rotated.
- When `vault_host_ansible_ssh_pubkey_file` is set, its key is installed and key
  login is preferred; the password remains a fallback. With no key the account
  is password-only.
- Passwordless sudo via `/etc/sudoers.d/ansible`; fixed UID
  (`host_ansible_uid`, default 1001).
- Added to the `docker` group when it exists (`host_ansible_docker_group`), so
  Docker commands run without an extra sudo.
- The **first run** must connect as `root` or a sudo-capable user; later runs
  connect as `ansible` automatically (connection probe below).
- Set `provision_ansible_user: false` in `host_vars/<host>/main.yml` to skip
  provisioning.

### Connection probe

`playbooks/connect.yml` is imported by `build.yml` and `info.yml`. Per host it
tries, in order:

1. `ansible` (the automation user),
2. the optional `admin` user (`vault_host_admin_user`),
3. `root`.

Each candidate is tried with a key first — explicit `-i` from the
`vault_host_*_ssh_pubkey_file` (path minus `.pub`), then the running SSH agent —
and then with a password (`vault_host_*_password`). Only configured credentials
are attempted. The selected profile is injected with `add_host`; a host with no
working credential fails the run loudly. `sshpass` is required on the control
node for password attempts (`make check-deps`).

## 3. Build

```bash
make build
```

What happens (`roles/imagebuilder`):

0. **connect** — the probe selects the connection user per host (`ansible` →
   `admin` → `root`) and injects it.
1. **preflight** — provisions the `ansible` automation user (unless
   `provision_ansible_user` is false), then asserts `openwrt_image` is set, the
   Docker CLI/daemon are reachable and the docker Python SDK is present.
2. **modules** — resolves the active module set from the default +
   `openwrt_modules_adjust` / `openwrt_modules_override`; fails on unknown names.
3. **setup** — pulls the image if needed, reads `VERSION_PATH` / `TARGET` from
   the image environment, derives the container name and the base-package switch.
4. **packages** — collects packages from the active modules
   (`base` is version-aware), appends `openwrt_extra_packages`, deduplicates and
   fails on add/remove conflicts.
5. **overlay** — renders the active modules' uci-defaults into the builder's
   work directory (static files copied verbatim, templated files via Jinja),
   asserts no two modules target the same file, applies executable modes.
6. **build** — runs the `openwrt/imagebuilder` container, which initializes the
   ImageBuilder (with an optional mirror), calls `make info` and `make image`,
   and restores artifact ownership to the invoking user.
7. **fetch** (optional) — when `openwrt_fetch_artifacts` is true (default), pulls
   the artifacts from the builder into the control node's
   `openwrt_artifacts_dir` (`<repo>/artifacts`), preserving the
   `targets/<target>/<subtarget>/` layout.

The builder produces artifacts under
`~/.cache/openwrt-builder/artifacts/targets/<target>/<subtarget>/`; the control
node copy lands in `artifacts/targets/<target>/<subtarget>/`. Re-running with the
same inputs converges on the same output.

### Artifact retrieval

| Knob | Default | Effect |
|------|---------|--------|
| `openwrt_fetch_artifacts` | `true` | Pull built artifacts from the builder to the control node |
| `openwrt_artifacts_dir` | `<repo>/artifacts` | Control-node destination (contents gitignored; the directory is tracked) |
| `openwrt_output_dir` | `~/.cache/openwrt-builder/artifacts` | Builder-side output directory |

The `artifacts/` directory itself is committed (via `.gitkeep`); everything
inside it is gitignored. Disable retrieval for large builds or when the builder
is the control node and you do not need a second copy.

### Verify

```bash
ls -R artifacts
sha256sum -c artifacts/targets/*/*/sha256sums 2>/dev/null || true
```

### Rollback / cleanup

The build writes only to the builder's `~/.cache/openwrt-builder` and (when
fetching) the control node's `artifacts/`. Both are scratch/output locations:
`artifacts/` contents are gitignored and can be removed freely, and `make clean`
drops caches and collections. Nothing else on either host is modified.

## 4. Query image/profile info

```bash
make info
```

Runs `make info` inside the container without building; use it to discover the
target's profiles before setting `openwrt_profile`.

## 5. Mirrors

Two independent knobs, both off by default (official OpenWrt sources):

| Knob | Phase | Effect |
|------|-------|--------|
| `openwrt_use_mirror: true` (+ `openwrt_mirror`) | build | rewrites the `repositories(.conf)` host to the mirror; package repos. `openwrt_mirror` must include the mirror's OpenWrt prefix (e.g. `mirrors.tuna.tsinghua.edu.cn/openwrt`) |
| `openwrt_setup_use_mirror: true` (+ `openwrt_setup_mirror_url`) | setup | fetches the ImageBuilder tarball via `setup.sh` from the mirror (release and SNAPSHOT), falls back to the official source |

A domestic mirror that has not yet synced a new release can cause build
failures: turn the mirror off and use the official source.

## 6. SNAPSHOT images

SNAPSHOT tool packages are mirrored by only a few providers. Use
`openwrt_setup_use_mirror: true` (USTC by default) to speed up the ImageBuilder
tarball download, without changing the package repositories:

```bash
make build ANS_EXTRA='-e openwrt_setup_use_mirror=true'
```

The same knob also works for release images; combined with
`openwrt_use_mirror: true` it keeps every download off `downloads.openwrt.org`.

## 7. Secrets

- Root password and PPPoE password live in the host vault
  (`ansible/inventory/host_vars/<host>/vault.yml`) as
  `vault_openwrt_root_password` / `vault_openwrt_pppoe_password`, referenced from
  `main.yml` as `{{ vault_* }}`. Connection credentials
  (`vault_host_ansible_ssh_pubkey_file`, `vault_host_admin_*`,
  `vault_host_root_*`) live there too.
- The vault password file (`~/.config/projects/openwrt-builder-wrapper/ansible_vault_password`)
  is created by `make ans-vault-init` and **never** committed; back it up.
  `make ans-vault-encrypt HOST=<host>` encrypts a plaintext vault; without a
  vault password a plaintext vault keeps working (secrets are gitignored).
- Values are Jinja-templated and shell-quoted automatically, so special
  characters (`$`, `'`, `\`, `"`) are safe. Leave a secret empty to skip its
  module.
- **The built image carries the secrets it was built with.** Treat artifact
  files as sensitive.

## 8. Adding a module

1. Add overlay files under `ansible/roles/imagebuilder/files/overlay/<name>/...`
   (static) or `templates/overlay/<name>/...` (Jinja, for variables).
2. Add its packages to `openwrt_module_packages` in
   `ansible/roles/imagebuilder/defaults/main.yml` (if any).
3. Add `<name>` to `openwrt_known_modules`.
4. Reference any operator variables in `host_vars/example/main.yml`
   (with empty role defaults so the templates always resolve).
5. Run `make ans-lint`, then build with the module active.

## 9. Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| Probe: "no working SSH credential" | Configure one of the vault entries: `vault_host_ansible_ssh_pubkey_file` / `vault_host_ansible_password` (generated), `vault_host_admin_*`, or `vault_host_root_*`; or load a key into the SSH agent |
| preflight: "vault password file is not configured" | Run `make ans-vault-init`, then invoke through `make build` (exports `ANSIBLE_VAULT_PASSWORD_FILE`) |
| preflight: "host_ansible_ssh_pubkey_file is unset" (warning) | Not fatal: the automation user is password-only. Set `vault_host_ansible_ssh_pubkey_file` to prefer key login |
| preflight user tasks fail (sudo/become) | The connection user needs sudo or root on the first run; alternatively set `provision_ansible_user: false` |
| preflight fails: "Docker CLI not found" | Install Docker and ensure it is on PATH on the builder host |
| preflight fails: "Cannot reach the Docker daemon" | Start Docker; ensure the connection user can access the socket (the `ansible` user is added to the `docker` group when it exists) |
| preflight fails: "Docker Python SDK" | Install `docker` for the build host's Python: `<python> -m pip install docker` |
| `Module ... does not expose VERSION_PATH/TARGET` | Use an official `openwrt/imagebuilder` tag |
| `Destination directory ... does not exist` | Should not occur; the overlay step creates directories. Report a bug. |
| `Packages are both added and removed` | Remove the `-pkg`/`pkg` conflict in `openwrt_extra_packages` or module package lists |
| `Duplicate overlay target files across modules` | Two active modules ship the same file path; rename or disable one |
| Build fails after enabling a mirror | Mirror sync lag; disable `openwrt_use_mirror`. For 25.12+ (APK) the mirror path must include the OpenWrt prefix (e.g. `mirrors.tuna.tsinghua.edu.cn/openwrt`, `mirrors.ustc.edu.cn/openwrt`) |
| Build hangs at "Building package index..." (25.12+, APK) | A near-infinite container `nofile` limit makes fakeroot's `faked` spin closing fds up to `RLIMIT_NOFILE`. The role pins `openwrt_container_ulimits` (`nofile:65536:65536`); keep it bounded |
| Artifacts owned by root | The in-container `chown` needs `HOST_UID`/`HOST_GID`; they come from `gather_facts` |
| Artifacts not in the control node's `artifacts/` | Check `openwrt_fetch_artifacts` (default true); artifacts are also kept on the builder at `openwrt_output_dir` |
| Cannot reach the builder over SSH | Fix `ansible_host` in `hosts.yml`; credentials come from the vault via the probe (do not set `ansible_user`) |
