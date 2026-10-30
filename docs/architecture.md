# Architecture

Design of the ImageBuilder IaC: components, configuration scope, the dependency
model, the secrets model, and how host bootstrap and variant isolation work.

## Components

| Layer | Tool | Responsibility |
|-------|------|----------------|
| Control node | **Ansible** (+ Make) | resolves modules/packages, renders the overlay, orchestrates the container |
| Build host | **Docker** | runs the official `openwrt/imagebuilder` container per variant |
| Build-host security | **Ansible** (role `sshd`) | opt-in key-only SSH hardening (password login closed, root SSH off) |
| Operator config | `host_vars/<machine>/main.yml` + `group_vars/builders/main.yml` | per-machine build variants; machine-wide operator overrides |

- **Control node** — where `make` runs. Needs `python`/`ansible-core` (pinned in
  `.tool-versions`), the `community.docker` collection, `openssl`, `sshpass`
  (bootstrap password probe only), `passlib`, and — only as a fallback — Keychain 3.
- **Build host** — a separate machine (by default) running Docker Engine,
  reachable over SSH as the configured identity, with the `docker` Python SDK
  importable by its interpreter. The role preflight asserts the Docker
  CLI/daemon and SDK here.

## Configuration scope

**One inventory host = one build machine.** Each machine builds one or more
**variants** — one `(target, profile, settings)` combination each.

- `inventory/hosts.yml` — the `builders` group; one host per machine, each with its
  own `ansible_host`.
- `inventory/host_vars/<machine>/main.yml` — that machine's `build_variants` list
  (per-variant build config) and, next to it, `vault.yml` (per-machine firmware
  secrets).
- `inventory/group_vars/all/main.yml` — the committed project-owned baseline for
  every machine: the SSH identity map (`ssh_identities`) plus the
  connection-plugin interface derived from it, the `iac` account's fixed
  uid/gid (operator override in `group_vars/builders/main.yml`, template
  `main.yml.example`), and the shared connection vault path.
- `inventory/group_vars/builders/` — machine-wide operator overrides, local-only
  (e.g. `create_admin_account`).

Committed: `group_vars/all/main.yml`, `host_vars/example/` and the
`group_vars/builders/*.example` templates; the real `group_vars/builders/main.yml`
and `vault*.yml` are local-only.

## Dependency model

- **`make install` is the only dependency entry point.** Every other target
  depends on it (build/info/host-bootstrap go through the internal
  `run-playbook`). In order it ensures: the toolchain (`ensure-toolchain`:
  python >= 3.8 + openssl), `ensure-sshpass`, `ensure-keychain`,
  `ensure-ansible-collections`, `ensure-passlib`. These are internal (`ensure-*`,
  no help entry) and fail loudly — no silent fallbacks.
- The **docker Python SDK is a build-host dependency**, not a control-node one.
  `install` does not install it; `roles/imagebuilder/tasks/preflight.yml` asserts
  it on the target with an actionable message.
- **`sshpass`** is installed with passwordless `apt-get`, else rootless into
  `~/.local/bin/sshpass`; if both fail, `install` exits non-zero. Auto-install is
  Debian-family only.
- **Keychain 3 is a fallback, never a prerequisite.** `install` only guarantees it
  *can* be installed (the pinned GitHub asset is SHA256-verified against
  `keychain.pin` then installed to `~/.local/bin`). Every SSH-consuming target
  runs through the shared `scripts/run-with-ssh-agent.sh` (driven by the
  `SSH_AGENT_*` variables): `agent-fallback` prepares the agent only when
  `agent-needed` finds a key whose permissions OpenSSH would refuse (e.g. `0777`
  on the WSL `/mnt/c` mount), loads the configured keys via
  `playbooks/ssh_agent_load.yml` (stdin fallback), and the runner retries once on
  a refused key. Correctly permissioned keys and password auth connect directly,
  with no agent.

## Connection identity and host bootstrap

The `iac` identity keeps `become: false` on purpose: `build`/`info` run as the
unprivileged builder user (Docker group access only), and a `true` value would
force root for those plays (the `ansible_become` variable outranks the play-level
`become: false`), changing artifact ownership. The bootstrap play does not use
that field for escalation — it injects `bootstrap_conn.become`, computed as
“identity != root”.

Normal runs (`build`/`info`) connect as the `iac` automation account; only
`make host-bootstrap` probes. The identity map `ssh_identities` in
`group_vars/all/main.yml` resolves the Ansible connection vars from the shared
vault (`vault_host_<id>_password`) and the non-secret group knobs
(`host_admin_username`, `host_<id>_ssh_{privkey,pubkey}_file` in
`group_vars/builders/main.yml`) for every machine.

`make host-bootstrap` (once per machine):

1. **Probes** `iac → admin → root` over SSH on every machine and uses the
   first identity that works on each.
2. **Creates/repairs** the least-privilege `iac` automation account (fixed
   uid/gid, NOPASSWD sudo, and the `docker` group when present) when that is not
   the probed identity; when it already is `iac`, it only applies the optional
   pubkey/sudo state. This self-heals a deleted/rotated credential.
3. **Sets credentials**: a supplied public key
   (`host_<id>_ssh_pubkey_file`, a control-node path) switches the account
   to key auth; otherwise an empty `vault_host_iac_password` is generated into
   the shared vault under the same name (existing non-empty values are never
   rotated). It optionally provisions the human `admin` account when
   `create_admin_account` is set.
4. **Grants sudo**: NOPASSWD for the automation account, password sudo for the
   human admin. Password hashes use a per-account random salt with
   `update_password: on_create`, so re-runs are idempotent.

## Secrets model

- **Connection credentials** are machine-wide and live in the shared vault
  `inventory/group_vars/builders/vault.yml`; the account name and the key paths
  are non-secret and live in `inventory/group_vars/builders/main.yml`.
- **No firmware secrets are baked into the image**: the WAN (PPPoE/DHCP) and root
  passwords are set after first boot; there is no per-machine firmware vault (see
  [configuration](configuration.md)).
- The vault password file lives outside the repo
  (`~/.config/projects/openwrt-image-builder-iac/ansible_vault_password`),
  auto-generated by `make vault-init`; a vault stays plaintext (mode 0600) until
  encrypted, and any file rewritten by `host-bootstrap` is always encrypted.
- SSH prefers a key (explicit path or agent) then the password, capped at one
  prompt. The private key is never stored in the vault — only its path.
- **The built image carries the secrets it was built with** — treat fetched
  artifacts as sensitive.

## Variant isolation

The inventory host is the machine, so the role appends the variant name to form a
**build id** (`<machine>-<variant>`). Every per-variant artifact uses it:

- builder-side scratch: `{{ build_dir }}/work/<machine>-<variant>` (removed after the build)
- builder-side output: `~/.cache/openwrt-builder/artifacts/<machine>-<variant>` (removed after the build)
- control-node copy: `<repo>/artifacts/<machine>-<variant>`
- container name: `openwrt-bw-<target>-<version>-<machine>-<variant>`

`make build` runs machines in parallel (Ansible forks) and a machine's variants
sequentially.
