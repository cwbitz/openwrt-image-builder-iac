# Runbooks

Operational procedures for building OpenWrt firmware with
`openwrt-image-builder-iac`. Read the repo-level
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
| `openssl` | Control node; generates secret values (`make install`) |
| `sshpass` | Control node; password SSH during `make host-bootstrap` (ensured by `make install`) |
| `passlib` | Control node; `password_hash` for the automation user (`make install`) |
| Keychain 3 | Control node; **fallback** ssh-agent, ensured by `make install`; started automatically only when OpenSSH refuses a key's file permissions |
| vault password | Created once by `make vault-init`; required to store/read generated secrets |
| docker Python SDK | On the **build host** (not the control node); checked by the role preflight |

`make install` is the sole dependency entry point: it ensures the control-node
toolchain (`python` >= 3.8, `openssl`), the Galaxy collections, `sshpass`
(passwordless `apt-get`, else rootless into `~/.local/bin`; a failure is fatal)
and `passlib`, and installs the pinned Keychain 3 (fetched from its GitHub
release and SHA256-verified against `keychain.pin`). Every other target depends
on `install`, so `sshpass`/`passlib`/Keychain are ready before a playbook runs.
The Docker CLI, daemon and Python SDK are validated at run time by the role's
preflight tasks on the **build host** (actionable failure when missing); the
control node does not need the docker SDK.

## 2. First-time setup

```bash
mise install
# One variant per (target, profile, settings); all variants share one builder.
make host-init VARIANT=ib-main            # scaffolds group_vars + host_vars/<variant>/
make host-init VARIANT=ib-side            # repeat for each variant
# edit inventory/hosts.yml (list variants under builder; set ansible_host once
# as a group variable = the builder)
# and each host_vars/<variant>/main.yml (build config) + vault.yml (firmware secrets)
make install
make vault-init
make vault-edit-group                     # shared SSH identity vault
make vault-edit VARIANT=ib-main           # that variant's firmware secrets
make host-bootstrap EXTRA='--limit ib-main'   # once; probe ansible -> admin -> root
# or, to bootstrap and then build every variant in one shot:
make deploy
```

Configuration is split by scope:

- **Machine-wide** (shared by all variants): `inventory/group_vars/builder/main.yml`
  (SSH identity, service account, shared vault path, per-variant isolation) and
  `inventory/group_vars/builder/vault.yml` (connection secrets; a missing one,
  e.g. the `ansible` password, is generated into this same file by
  `make host-bootstrap`).
- **Per variant**: `host_vars/<variant>/main.yml` (build config) and
  `host_vars/<variant>/vault.yml` (firmware secrets), where `<variant>` matches
  the inventory host name.

Vault files are auto-loaded by the inventory. `hosts.yml`, the real
`group_vars/builder/main.yml`, and every `host_vars/<variant>/` directory are
gitignored; only the `group_vars/builder/*.example` templates and
`host_vars/variant.example/` are committed. A vault
may stay plaintext (mode 0600) until you encrypt it
(`make vault-edit VARIANT=<variant>` / `make vault-edit-group`, which encrypt a
plaintext file before editing; `make host-init` encrypts at scaffold time); any
file rewritten by `host-bootstrap` (a generated secret) is always encrypted.

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
  in `vault.yml` is generated and merged back into the same vault under the same
  name; a non-empty value is never rotated.
- Passwordless sudo via `/etc/sudoers.d/90-openwrt-builder-<user>`; fixed uid/gid
  (`host_ansible_uid` / `host_ansible_gid`, default `6000:6000`). The
  project-wide scheme reserves 5000-5999 for the shared data identity and
  6000-6499 for service/automation accounts.
- Added to the `docker` group when it exists (`host_ansible_docker_group`), so
  Docker commands run without an extra sudo.
- SSH prefers a key (explicit `vault_host_<id>_ssh_privkey_file`, else the
  running SSH agent), then the password, capped at one prompt
  (`host_ssh_common_args`). `sshpass` is required on the control node for password
  attempts (ensured by `make install`).
- `build`/`info`/`host-bootstrap` run through the shared
  `scripts/run-with-ssh-agent.sh`. Keychain is a **fallback**: the internal
  `agent-fallback` prepares the agent only when `agent-needed` finds a configured
  key whose permissions OpenSSH would refuse (e.g. `0777` on the WSL `/mnt/c`
  mount; `agent-ensure` is the unconditional variant), then loads every
  configured `vault_host_<id>_ssh_privkey_file` (via stdin, `ssh-add - < key`,
  which reads the key content directly and skips the permission check) and the
  runner retries once. Correctly permissioned keys and password auth connect
  directly, with no agent. The internal `make agent-load` (start/reuse the agent
  and load the keys) and `make agent-check` (verify identities) helpers remain
  available — `run-playbook` already performs the fallback on demand.

## 3. Build

```bash
make build                            # build every variant, in parallel
make build EXTRA='--limit ib-side' # single variant
make deploy                           # host-bootstrap, then build (fresh host to image)
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

A variant is one inventory host in the `builder` group; all variants build on the
same machine (the builder address is set once as a group variable). Isolation
comes from
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
`artifacts/` contents are gitignored and can be removed freely; remove the
control-node caches (`.cache`, `collections`, `.ansible`) yourself. Nothing else
on either host is modified.

## 4. Query image/profile info

```bash
make info
```

Runs `make info` inside the container without building; use it to discover the
target's profiles before setting `openwrt_profile`.

The target queries **every** variant (each inventory `builder` host) and prints
one `===== variant =====` block per variant — no task banners, per-host `ok:`
blocks, PLAY RECAP, or dependency-helper chatter (toolchain / collections /
Keychain / ssh-agent are silenced via `QUIET=1`). To query a single variant,
append `EXTRA='--limit <variant>'`, e.g.
`make info EXTRA='--limit ib-main'`.

The query pulls the ImageBuilder image / profile index over the network, and the
shared runner buffers the play output until it finishes. So the terminal can
pause with nothing to show; while it runs, `make info` displays a
`Querying ImageBuilder info` spinner (a static
line when stdout is not a TTY), then prints the captured output.

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
- The vault password file (`~/.config/projects/openwrt-image-builder-iac/ansible_vault_password`)
  is created by `make vault-init` and **never** committed; back it up.
  `make vault-edit VARIANT=<variant>` encrypts a plaintext vault before editing;
  without a vault password a plaintext vault keeps working (secrets are
  gitignored).
- Values are Jinja-templated and shell-quoted automatically, so special
  characters (`$`, `'`, `\`, `"`) are safe. Leave a secret empty to skip its
  module.
- **The built image carries the secrets it was built with.** Treat artifact
  files as sensitive.

## 8. Adding a module

1. Add overlay files under `roles/imagebuilder/files/overlay/<name>/...`
   (static) or `templates/overlay/<name>/...` (Jinja, for variables).
2. Add its packages to `openwrt_module_packages` in
   `roles/imagebuilder/vars/main.yml` (if any).
3. Add `<name>` to `openwrt_known_modules`.
4. Reference any operator variables in `host_vars/variant.example/main.yml`
   (with empty role defaults so the templates always resolve).
5. Run the internal `make lint` (syntax-check + `ansible-lint`, run by CI), then
   build with the module active.

## 9. Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `host-bootstrap`: "Could not log in as ansible, admin or root" | Configure one of the vault entries: `vault_host_ansible_*`, `vault_host_admin_*`, or `vault_host_root_*` (`password` / `ssh_privkey_file`); or load a key into the SSH agent. If your only usable account is root, set `vault_host_root_password` (or a root private key) |
| `build`/`info` cannot connect as `ansible` | Run `make host-bootstrap` once (it creates/repairs the account); the effective password is `vault_host_ansible_password` (generated into the shared vault by `host-bootstrap` when empty), else set `vault_host_ansible_ssh_privkey_file`/pubkey |
| Need the auto-generated password | `make vault-view` (it prints every pseudo-host vault plus the shared connection vault; the password is also printed once by `host-bootstrap`) |
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
