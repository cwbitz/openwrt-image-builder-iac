# Runbooks

Operational procedures for building OpenWrt firmware with
`openwrt-builder-wrapper`. Read the repo-level
[README](../README.md) first for the architecture and layout.

## 1. Prerequisites

| Requirement | Notes |
|-------------|-------|
| Control node | Where you run `make`; hosts the repo and the Ansible toolchain |
| Build host | A SEPARATE LAN machine (by default) running Docker Engine; SSH-reachable from the control node as the connection user, who must be able to access the Docker daemon |
| sudo (or root) on the build host | Required on the first `make host-bootstrap` run to create the `ansible` service account |
| Docker Engine / Desktop | Must be running on the `builder` host |
| python >= 3.8 | Control node; runs `ansible-core` and the `community.docker` modules |
| `ansible-core` + `python` | Pinned in `.tool-versions` (`mise install` / `asdf install`) |
| `community.docker` | Installed into `collections/` by `make install` |
| `openssl` | Control node; generates secret values (`make check-deps`) |
| `sshpass` | Control node; password SSH during `make host-bootstrap` (`make check-deps`) |
| `passlib` | Control node; `password_hash` for the automation user (`make check-deps`) |
| Keychain 3 | Control node; pinned ssh-agent (`make agent-load` auto-downloads + verifies SHA256) |
| vault password | Created once by `make vault-init`; required to store/read generated secrets |
| docker Python SDK | On the **build host** (not the control node); checked by the role preflight |

`make install` checks and, where safe, installs the control-node prerequisites
(`openssl`, `sshpass`, `passlib`, the `docker` SDK for a local build host). The
Docker CLI, daemon and Python SDK are validated again at run time by the role's
preflight tasks (actionable failure when missing). Keychain 3 is fetched from its
pinned GitHub release and SHA256-verified by `make keychain-check`/`keychain-verify`.

## 2. First-time setup

```bash
mise install
# One variant per (target, profile, settings); all variants share one builder.
make host-init HOST=ib-main               # scaffolds inventory/ + host_vars/<variant>/
make host-init HOST=ib-side               # repeat for each variant
# edit inventory/hosts.yml (all variants share ansible_host = the builder)
# and each host_vars/<variant>/main.yml (build config) + vault.yml (firmware secrets)
make install
make vault-init
make vault-edit VAULT_FILE=inventory/group_vars/builder/vault.yml  # shared SSH identity
make vault-edit VARIANT=ib-main          # that variant's firmware secrets
make host-bootstrap EXTRA='--limit ib-main'   # once; probe ansible -> admin -> root
```

Configuration is split by scope:

- **Machine-wide** (shared by all variants): `inventory/group_vars/builder/main.yml`
  (SSH identity, service account, shared vault paths, per-variant isolation) and
  `inventory/group_vars/builder/vault.yml` (operator-owned connection secrets) +
  `inventory/group_vars/builder/vault_managed.yml` (automation-owned, created on
  first `host-bootstrap`).
- **Per variant**: `host_vars/<variant>/main.yml` (build config) and
  `host_vars/<variant>/vault.yml` (firmware secrets), where `<variant>` matches
  the inventory host name.

Vault files are auto-loaded by the inventory. `hosts.yml` and every
`host_vars/<variant>/` directory are gitignored; only `host_vars/example/` and
`group_vars/builder/` (except the real `vault*.yml`) are committed. An operator
`vault.yml` may stay plaintext (mode 0600) until you encrypt it
(`make vault-encrypt VARIANT=<variant>` or `VAULT_FILE=...`); `host-bootstrap`
handles both formats, while the managed `vault_managed.yml` is always encrypted
and never hand-edited.

### SSH identities and `host-bootstrap`

The connection identity is explicit (netbird-iac model, machine-wide), defined
by the `host_ssh_identities` map in `group_vars/builder/main.yml` (shared by
every variant):

- `root` (become off), `admin` (optional, become on) and `ansible` (the service
  account, become off — the build runs via the `docker` group). Each resolves
  `user`/`password`/`privkey`/`pubkey` from `vault_host_<id>_*`.
- Normal runs (`build.yml` / `info.yml`) always connect as `ansible` (the
  inventory sets no user).
- `make host-bootstrap` probes `ansible -> admin -> root` over SSH and uses the
  first identity that works. When that is not `ansible`, it (re)creates the
  `ansible` service account; when it already is `ansible`, it only applies the
  optional pubkey/sudo state. This self-heals a rotated/deleted credential.
- Per-identity public keys: when `vault_host_<id>_ssh_pubkey_file` is set (a
  control-node path), it is authorized for the matching account. Unset -> ignored
  (keys are never auto-generated). Only paths, never raw key strings.
- Service-account auth is key **or** password: with no
  `vault_host_ansible_ssh_pubkey_file`, an empty `vault_host_ansible_password`
  in `vault.yml` triggers generation into the encrypted managed vault
  (`vault_managed.yml`) as `vault_host_ansible_password_auto`; a non-empty
  `vault.yml` value always wins and an existing `_auto` value is never rotated.
- Passwordless sudo via `/etc/sudoers.d/90-openwrt-builder-<user>`; fixed uid/gid
  (`host_ansible_uid` / `host_ansible_gid`, default `6000:6000`). The
  project-wide scheme reserves 5000-5999 for the shared data identity and
  6000-6499 for service/automation accounts.
- Added to the `docker` group when it exists (`host_ansible_docker_group`), so
  Docker commands run without an extra sudo.
- SSH prefers a key (explicit `vault_host_<id>_ssh_privkey_file`, else the
  running SSH agent), then the password, capped at one prompt
  (`host_ssh_common_args`). `sshpass` is required on the control node for password
  attempts (`make check-deps`).
- `build`/`info`/`host-bootstrap` depend on `agent-load`, which starts (or
  reuses) a pinned **Keychain 3** ssh-agent and loads every configured
  `vault_host_<id>_ssh_privkey_file` into it; the recipe re-exports the agent env
  (`keychain agent start --eval`) before running the playbook. When OpenSSH
  rejects a key's file permissions (e.g. the WSL `/mnt/c` mount), the key is
  loaded via stdin (`ssh-add - < key`), i.e. the key content is read directly and
  the permission check is skipped. `make agent-setup` initializes the agent in
  every new shell (idempotent `~/.bashrc` block).

## 3. Build

```bash
make build                            # build every variant, in parallel
make build EXTRA='--limit ib-side' # single variant
```

`make build` targets the `builder` group; every inventory host in it is one
build variant on the same Docker machine, so Ansible builds them concurrently.
See "Multi-variant builds" below for isolation and naming details.

What happens (`roles/imagebuilder`):

1. **preflight** — asserts `openwrt_image` is set, the Docker CLI/daemon are
   reachable and the docker Python SDK is present. (The `ansible` service account
   is created separately, once, by `make host-bootstrap`.)
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

Each variant produces artifacts under
`~/.cache/openwrt-builder/artifacts/<variant>/targets/<target>/<subtarget>/`; the
control-node copy lands in
`artifacts/<variant>/targets/<target>/<subtarget>/`. Re-running with the same
inputs converges on the same output.

### Multi-variant builds

A variant is one inventory host in the `builder` group; all variants point at the
same `ansible_host` (the physical builder). Isolation comes from
`group_vars/builder/main.yml`, which derives per-variant paths from
`inventory_hostname`:

| Knob | Value |
|------|-------|
| `openwrt_workdir` | `{{ openwrt_build_dir }}/work/<variant>` (builder scratch) |
| `openwrt_output_dir` | `{{ openwrt_build_dir }}/artifacts/<variant>` (builder output) |
| `openwrt_artifacts_dir` | `<repo>/artifacts/<variant>` (control-node copy) |

The container name is `openwrt-bw-<target>-<version>-<variant>` (see
`roles/imagebuilder/tasks/setup.yml`), so two variants of the same target/version
do not collide when built in parallel. `ansible.cfg` sets `forks = 25`, so
`make build` runs all variants concurrently; bound it with `ANSIBLE_FORKS=1` (or
`--limit`) on a resource-constrained builder. `make host-bootstrap` only needs to
run once — `bootstrap.yml` acts on `groups['builder'][0]` and the connection
credentials are shared.

### Artifact retrieval

| Knob | Default | Effect |
|------|---------|--------|
| `openwrt_fetch_artifacts` | `true` | Pull built artifacts from the builder to the control node |
| `openwrt_artifacts_dir` | `<repo>/artifacts/<variant>` | Control-node destination (contents gitignored; the directory is tracked) |
| `openwrt_output_dir` | `~/.cache/openwrt-builder/artifacts/<variant>` | Builder-side output directory |

The `artifacts/` directory itself is committed (via `.gitkeep`); everything
inside it is gitignored. Disable retrieval for large builds or when the builder
is the control node and you do not need a second copy.

### Verify

```bash
ls -R artifacts
sha256sum -c artifacts/*/targets/*/*/sha256sums 2>/dev/null || true
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
make build EXTRA='-e openwrt_setup_use_mirror=true'
```

The same knob also works for release images; combined with
`openwrt_use_mirror: true` it keeps every download off `downloads.openwrt.org`.

## 7. Secrets

- Firmware secrets (root/PPPoE passwords) are **per variant** and live in
  `inventory/host_vars/<variant>/vault.yml` as
  `vault_openwrt_root_password` / `vault_openwrt_pppoe_password`, referenced from
  the variant's `main.yml` as `{{ vault_* }}`.
- Connection credentials are **machine-wide** and live in the shared vault
  `inventory/group_vars/builder/vault.yml`
  (`vault_host_*_ssh_privkey_file`, `vault_host_*_password`, plus the install key
  `vault_host_ansible_ssh_pubkey_file`).
- The vault password file (`~/.config/projects/openwrt-builder-wrapper/ansible_vault_password`)
  is created by `make vault-init` and **never** committed; back it up.
  `make vault-encrypt VARIANT=<host>` encrypts a plaintext vault; without a
  vault password a plaintext vault keeps working (secrets are gitignored).
- Values are Jinja-templated and shell-quoted automatically, so special
  characters (`$`, `'`, `\`, `"`) are safe. Leave a secret empty to skip its
  module.
- **The built image carries the secrets it was built with.** Treat artifact
  files as sensitive.

## 8. Adding a module

1. Add overlay files under `roles/imagebuilder/files/overlay/<name>/...`
   (static) or `templates/overlay/<name>/...` (Jinja, for variables).
2. Add its packages to `openwrt_module_packages` in
   `roles/imagebuilder/defaults/main.yml` (if any).
3. Add `<name>` to `openwrt_known_modules`.
4. Reference any operator variables in `host_vars/example/main.yml`
   (with empty role defaults so the templates always resolve).
5. Run `make lint`, then build with the module active.

## 9. Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `host-bootstrap`: "Could not log in as ansible, admin or root" | Configure one of the vault entries: `vault_host_ansible_*`, `vault_host_admin_*`, or `vault_host_root_*` (`password` / `ssh_privkey_file`); or load a key into the SSH agent. If your only usable account is root, set `vault_host_root_password` (or a root private key) |
| `build`/`info` cannot connect as `ansible` | Run `make host-bootstrap` once (it creates/repairs the account); the effective password is `vault_host_ansible_password` (operator) or `vault_host_ansible_password_auto` in `vault_managed.yml`, else set `vault_host_ansible_ssh_privkey_file`/pubkey |
| Need the auto-generated password | `make vault-view VAULT_FILE=inventory/group_vars/builder/vault_managed.yml` (it is also printed once by `host-bootstrap`) |
| `build` fails: vault password file missing | Run `make vault-init` (the canonical ansible.cfg points at that file) |
| `host-bootstrap` user tasks fail (sudo/become) | The probed identity needs sudo or root; the first run must reach the host as `root` or a sudo-capable `admin` user |
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
| Cannot reach the builder over SSH | Fix `ansible_host` in `hosts.yml`; the connection identity comes from `group_vars/builder/main.yml` (`host_ssh_identities`) |
