# AGENTS.md

Ansible IaC that builds customized **OpenWrt firmware images** with the official
`openwrt/imagebuilder` running in a Docker container on a build host.

The **control node** (where `make` runs) and the **build host** (the machine
running Docker) are separate LAN machines by default; every build variant runs
against that same machine (the builder address is written once as a group
variable). Entry playbooks: `playbooks/bootstrap.yml` (once,
provisions the `ansible` service account), `playbooks/build.yml` (build every
variant in parallel) and `playbooks/info.yml` (read-only ImageBuilder query). The
build logic lives in `roles/imagebuilder/`.

## Topology and configuration scope

- **Control node** — runs `make` + Ansible. Needs `python`/`ansible-core`
  (pinned in `.tool-versions`), the `community.docker` collection, `openssl`,
  `sshpass` (bootstrap password probe only), `passlib`, and — only as a
  fallback — Keychain 3.
- **Build host** — separate machine with Docker Engine reachable over SSH as the
  configured identity, and the `docker` Python SDK importable by its
  interpreter. The role preflight asserts the Docker CLI/daemon and SDK here.
- **Per variant** (`inventory/host_vars/<variant>/`): build config (`main.yml`)
  and firmware secrets (`vault.yml`). One variant = one inventory host = one
  (target, profile, settings); the builder `ansible_host` is defined once as a
  group variable and inherited by every variant.
- **Machine-wide** (`inventory/group_vars/builder/`): the SSH identity map,
  service account, shared connection vault and per-variant isolation paths
  (derived from `inventory_hostname`).

## Dependency model

- **`make install` is the only dependency entry point.** Every other target
  depends on it (build/info/host-bootstrap go through the internal
  `run-playbook`). In order it ensures: the toolchain (`ensure-toolchain`:
  python >= 3.8 + openssl), `ensure-sshpass`, `ensure-keychain`,
  `ensure-ansible-collections`, `ensure-passlib`. These are internal (`ensure-*`, no
  help entry) and **fail loudly** — no silent fallbacks.
- The **docker Python SDK is a build-host dependency**, not a control-node one.
  `install` does not install it; `roles/imagebuilder/tasks/preflight.yml`
  asserts it on the target with an actionable message.
- **`sshpass`** is installed with passwordless `apt-get`, else rootless into
  `~/.local/bin/sshpass`; if both fail, `install` exits non-zero (install it
  manually or use key-only bootstrap credentials). Auto-install is
  Debian-family only.
- **Keychain 3 is a fallback, never a prerequisite.** `install` only guarantees
  it *can* be installed: the pinned GitHub asset is downloaded and
  SHA256-verified against `keychain.pin`, then installed to `~/.local/bin`. Every
  SSH-consuming target runs through the shared, project-agnostic
  `scripts/run-with-ssh-agent.sh` (driven by the `SSH_AGENT_*` environment
  variables). The internal `agent-fallback` prepares the agent only when
  `agent-needed` detects a configured key whose permissions OpenSSH would refuse
  (e.g. `0777` on the WSL `/mnt/c` mount; `agent-ensure` is the unconditional
  variant), loads the vault keys via `playbooks/ssh_agent_load.yml` (stdin
  fallback), and the runner retries once on a refused-key failure. Correctly
  permissioned keys and password auth connect directly, with no agent.

## Commands

- `make help` — aligned target list; each target's overridable variables
  (`VARIANT`, `EXTRA`) are shown inline in its description. `help` is listed last.
- `make install` — the sole dependency entry (see above).
- `make host-init VARIANT=<name>` — scaffold `inventory/hosts.yml` and
  `group_vars/builder/main.yml` from the examples, plus `host_vars/<name>/`; the
  vault is encrypted immediately (dir `0700`, file `0600`). Re-running does not
  overwrite existing files.
- `make host-bootstrap` — once: probe `ansible → admin → root` and create/repair
  the `ansible` service account (key-first, NOPASSWD sudo, `docker` group) plus
  the human `admin` account when `host_admin_enabled` is set (always given a
  password). Passwords use a per-account random salt with `update_password:
  on_create`.
- `make deploy` — one-click: `host-bootstrap` then `build` (fresh host to image).
- `make build` / `make info` — build every variant in parallel / query
  ImageBuilder info. Non-`ansible` runs are unsupported. `info` targets every
  variant and prints one `===== variant =====` block per variant, hiding the
  dependency-helper chatter (`QUIET=1`) — via the `callback_plugins/info_format.py`
  stdout callback plus the no-op `info_silent` displacing `profile_tasks`, all
  selected only by that target; limit to one with `EXTRA='--limit <variant>'`.
- `make vault-init` — generate the vault password file (outside the repo).
- `make vault-edit VARIANT=<name>` — edit that variant's vault; a plaintext
  vault is encrypted first.
- `make vault-edit-group` — same, for the shared builder connection vault.
- `make vault-view` — read-only: iterate every inventory `builder` host and print
  its `host_vars/<host>/vault.yml`, then the shared
  `group_vars/builder/vault.yml`. Missing per-host vaults show `(missing)`.
- `lint` (syntax-check + `ansible-lint`, invoked by CI) is internal and hidden
  from `make help`.
- `agent-needed`/`agent-fallback`/`agent-ensure` (prepare the agent), `agent-load`
  (start+load keys) and `agent-check` (verify loaded) are internal: `run-playbook`
  prepares the agent through the shared runner.
- `EXTRA` is appended to every `ansible-playbook` invocation, e.g.
  `make build EXTRA='--limit ib-side'`.

Removed — do not reintroduce: `agent-setup`, `clean`, `vault-encrypt`, the
separate `vault_managed.yml` managed vault (and its `*_auto` indirection —
generated secrets are merged into `vault.yml` in place), the public `check-*`
(`check-deps`/`check-collections`) and `keychain-*` helpers,
`install-sshpass-local` / `install-passlib-local`, and the `KEYCHAIN_PYZ`
local-asset override. The control-node caches (`.cache`, `collections`,
`.ansible`) are the operator's to delete. Keychain's asset URL is a fixed
constant.

## Secrets and local-only files

- `inventory/group_vars/builder/main.yml` — machine-wide non-secret config, local
  only; the committed template is `main.yml.example` (scaffolded by `host-init`).
- `inventory/group_vars/builder/vault.yml` — machine-wide connection secrets
  (`vault_host_<id>_{user,password,ssh_privkey_file,ssh_pubkey_file}`),
  operator-owned; a missing generated value (the `ansible` password when no key
  is set, and the `admin` password when `host_admin_enabled`) is merged in place
  by `make host-bootstrap` under the same name.
- `inventory/host_vars/<variant>/vault.yml` — per-variant firmware secrets
  (`vault_openwrt_root_password`, `vault_openwrt_pppoe_password`), operator owned.
- Vault password file:
  `~/.config/projects/openwrt-image-builder-iac/ansible_vault_password`
  (pointed to by `ansible.cfg`, auto-generated by `make vault-init`). It lives
  outside the repo and is never committed.
- Reference secrets by path only; the private key content is never stored in the
  vault (only `vault_host_<id>_ssh_privkey_file`). SSH prefers the key (explicit
  path or agent) then the password, capped at one prompt.

## Gotchas

- Only `host_vars/variant.example/` and the `group_vars/builder/*.example`
  templates are committed. `inventory/hosts.yml`, real variant directories, and
  `group_vars/builder/main.yml` / real `vault*.yml` are gitignored.
- `bootstrap.yml` acts on `groups['builder'][0]`; `host-bootstrap` runs once for
  the whole builder.
- The built image carries the secrets it was built with — treat fetched
  artifacts as sensitive.
- `ansible.cfg` sets `vault_password_file`; ansible-core 2.19 hard-fails when it
  is missing, so CI generates a throwaway file before lint/syntax-check.
