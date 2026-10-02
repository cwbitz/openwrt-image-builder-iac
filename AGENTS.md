# AGENTS.md

Ansible IaC that builds customized **OpenWrt firmware images** with the official
`openwrt/imagebuilder` running in a Docker container on a build host.

The **control node** (where `make` runs) and the **build host** (the machine
running Docker) are separate LAN machines by default; every build variant points
at the same `ansible_host`. Entry playbooks: `playbooks/bootstrap.yml` (once,
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
  (target, profile, settings); all variants share `ansible_host`.
- **Machine-wide** (`inventory/group_vars/builder/`): the SSH identity map,
  service account, shared connection vault, always-encrypted managed vault and
  per-variant isolation paths (derived from `inventory_hostname`).

## Dependency model

- **`make install` is the only dependency entry point.** Every other target
  depends on it (build/info/host-bootstrap go through the internal
  `run-playbook`). In order it ensures: the toolchain (`ensure-toolchain`:
  python >= 3.8 + openssl), `ensure-sshpass`, `ensure-keychain`,
  `ensure-collections`, `ensure-passlib`. These are internal (`ensure-*`, no
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
  SHA256-verified against `keychain.pin`, then installed to `~/.local/bin`. The
  agent is started only when OpenSSH refuses a private key whose file
  permissions cannot be fixed (e.g. `0777` on the WSL `/mnt/c` mount);
  `run-playbook` then starts Keychain, loads the vault keys via stdin and retries
  once. Correctly permissioned keys and password auth connect directly, with no
  agent.

## Commands

- `make help` — flat target list + overridable variables (`HOST`, `VARIANT`,
  `VAULT_FILE`, `EXTRA`, `KEYCHAIN_BIN`, `KEYCHAIN_CACHE`, `SSHPASS_BIN`).
  `VAULT_FILE` overrides `VARIANT`.
- `make install` — the sole dependency entry (see above).
- `make lint` — `ansible-playbook --syntax-check` for every playbook +
  `ansible-lint`.
- `make host-init HOST=<name>` — scaffold `inventory/hosts.yml` and
  `host_vars/<name>/` from `example/`; the vault is encrypted immediately (dir
  `0700`, file `0600`). Re-running does not overwrite existing files.
- `make host-bootstrap` — once: probe `ansible → admin → root` and create/repair
  the `ansible` service account (keys, NOPASSWD sudo, `docker` group).
- `make build` / `make info` — build every variant in parallel / query
  ImageBuilder info. Non-`ansible` runs are unsupported.
- `make vault-init` — generate the vault password file (outside the repo).
- `make vault-edit` / `make vault-view` — edit/view a vault; `vault-edit`
  encrypts a plaintext vault first.
- `make agent-setup` / `make agent-load` / `make agent-check` — explicit
  Keychain lifecycle: init in every new shell / start+load keys / verify loaded.
- `EXTRA` is appended to every `ansible-playbook` invocation, e.g.
  `make build EXTRA='--limit ib-side'`.

Removed — do not reintroduce: `clean`, `vault-encrypt`, the public `check-*`
(`check-deps`/`check-collections`) and `keychain-*` helpers, `install-sshpass-local`
/ `install-passlib-local`, and the `KEYCHAIN_PYZ` local-asset override. The
control-node caches (`.cache`, `collections`, `.ansible`) are the operator's to
delete. Keychain's asset URL is a fixed constant.

## Secrets and local-only files

- `inventory/group_vars/builder/vault.yml` — machine-wide connection secrets
  (`vault_host_<id>_{user,password,ssh_privkey_file,ssh_pubkey_file}`), operator
  owned.
- `inventory/host_vars/<variant>/vault.yml` — per-variant firmware secrets
  (`vault_openwrt_root_password`, `vault_openwrt_pppoe_password`), operator owned.
- `inventory/group_vars/builder/vault_managed.yml` — automation-owned and always
  encrypted; holds generated `*_auto` values only (never hand-edited).
- Vault password file:
  `~/.config/projects/openwrt-builder-wrapper/ansible_vault_password`
  (pointed to by `ansible.cfg`, auto-generated by `make vault-init`). It lives
  outside the repo and is never committed.
- Reference secrets by path only; the private key content is never stored in the
  vault (only `vault_host_<id>_ssh_privkey_file`). SSH prefers the key (explicit
  path or agent) then the password, capped at one prompt.

## Gotchas

- Only `host_vars/example/` and `group_vars/builder/` (minus the real
  `vault*.yml`) are committed. `inventory/hosts.yml` and real variant directories
  are gitignored.
- `bootstrap.yml` acts on `groups['builder'][0]`; `host-bootstrap` runs once for
  the whole builder.
- The built image carries the secrets it was built with — treat fetched
  artifacts as sensitive.
- `ansible.cfg` sets `vault_password_file`; ansible-core 2.19 hard-fails when it
  is missing, so CI generates a throwaway file before lint/syntax-check.
