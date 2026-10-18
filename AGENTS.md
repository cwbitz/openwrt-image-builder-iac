# AGENTS.md

Ansible IaC that builds customized **OpenWrt firmware images** with the official
`openwrt/imagebuilder` running in a Docker container on a build host.

**One inventory host = one build machine**; each machine builds one or more
**variants** (one `(target, profile, settings)` each), listed in its
`host_vars/<machine>/main.yml` as `openwrt_variants`. Entry playbooks:
`playbooks/bootstrap.yml` (once, provisions the `ansible` service account on every
machine), `playbooks/build.yml` (builds every variant) and `playbooks/info.yml`
(read-only ImageBuilder query). The build logic lives in `roles/imagebuilder/`.

## Commands

- `make help` — aligned target list; overridable variables (`HOST`, `EXTRA`) are
  shown inline. `help` is listed last.
- `make install` — the sole dependency entry point (toolchain, collections,
  `sshpass`, `passlib`, Keychain). Every other target depends on it.
- `make host-init HOST=<name> HOST_IP=<addr>` — scaffold `inventory/hosts.yml` and
  `group_vars/builder/main.yml` comment-free from the examples, plus
  `host_vars/<name>/` (with an `openwrt_variants` list); add `<name>` under
  `builder.hosts` with `HOST_IP` as its `ansible_host`; encrypt the vault (dir
  `0700`, file `0600`). HOST defaults to `openwrt-ib-prod-1`; re-running does not
  overwrite existing files.
- `make host-bootstrap` — once: probe `ansible → admin → root` on every machine
  and create/repair the `ansible` service account (key-first, NOPASSWD sudo,
  `docker` group) plus the human `admin` account when `host_admin_enabled` is set.
- `make deploy` — one-click: `host-bootstrap` then `build`.
- `make build` / `make info` — build every variant (machines in parallel) / query
  ImageBuilder info; limit to one machine with `EXTRA='--limit <machine>'`.
- `make vault-init` — generate the vault password file (outside the repo).
- `make vault-edit HOST=<name>` / `make vault-edit-group` — edit a machine vault /
  the shared builder connection vault; a plaintext vault is encrypted first.
- `make vault-view` — read-only: print every machine vault + the shared vault.
- Internal (hidden from `make help`): `lint` (syntax-check + `ansible-lint`, run by
  CI) and the `ensure-*` / `agent-*` / `keychain-*` / `run-playbook` helpers.
- `EXTRA` is appended to every `ansible-playbook` invocation, e.g.
  `make build EXTRA='--limit openwrt-ib-prod-1'`.

## Ansible conventions: probe & bootstrap host targeting

Shared by the `*-iac` repos; keep this chain statically resolvable so
`--syntax-check` stays clean:

- **Control-node-only plays** (preflight, the SSH probe, `host_keys`,
  `ssh_agent_load`) use `hosts: localhost` + `connection: local` — never
  `hosts: all` + `connection: local`.
- **The action play that follows a probe** targets a host/group that resolves
  from the static inventory. Never target a dynamic-only group: it forces either
  an empty-group declaration in the inventory or a `--syntax-check`
  "Could not match supplied host pattern" warning.
- **Single-host bootstrap** targets the probed host **by name**, with a safe
  default — `hosts: "{{ bootstrap_host | default(groups['<group>'] | default([]) | first | default('', true)) }}"` —
  and `make <target> HOST=<name>` passes `-e bootstrap_host=<name>`.
- **Multi-host bootstrap** targets the real inventory group. `add_host` only
  injects the probed identity/vars onto a host already present in the inventory;
  it never creates a play target.
- **The probe must verify escalation, not just login.** An identity other than
  `root` is usable only when it can actually become root: proven with
  `sudo -n true` for a password-less (NOPASSWD) identity, while a password-sudo
  identity proves it at deploy time via `ansible_become_password`. A
  half-provisioned account (login OK, sudoers not yet written) must never be
  chosen, or the bootstrap can no longer repair that host.

## Secrets and local-only files

- `inventory/group_vars/all/main.yml` — committed project-owned baseline for
  every build machine: the SSH connection identity wiring, the connection-plugin
  interface derived from it, the `ansible` account's fixed uid/gid + docker group,
  and the shared connection vault path.
- `inventory/group_vars/builder/main.yml` — machine-wide operator overrides, local
  only; the committed template is `main.yml.example` (scaffolded by `host-init`).
  The project-owned wiring lives in the committed `group_vars/all/main.yml`.
- `inventory/group_vars/builder/vault.yml` — machine-wide connection secrets
  (`vault_host_<id>_{user,password,ssh_privkey_file,ssh_pubkey_file}`),
  operator-owned; a missing generated value (the `ansible` password when no key is
  set, the `admin` password when `host_admin_enabled`) is merged in place by
  `make host-bootstrap` under the same name.
- `inventory/host_vars/<machine>/vault.yml` — per-machine firmware secrets
  (`vault_openwrt_root_password` / `vault_openwrt_pppoe_password`, each a dict
  keyed by variant name), operator owned.
- Vault password file:
  `~/.config/projects/openwrt-image-builder-iac/ansible_vault_password`
  (pointed to by `ansible.cfg`, auto-generated by `make vault-init`); never
  committed.
- Reference secrets by path only; the private key content is never stored in the
  vault (only `vault_host_<id>_ssh_privkey_file`). SSH prefers the key (explicit
  path or agent) then the password, capped at one prompt.

## Gotchas

- Committed: `group_vars/all/main.yml` (project-owned baseline),
  `host_vars/builder.example/` and the `group_vars/builder/*.example` templates.
  `inventory/hosts.yml`, real machine directories, and `group_vars/builder/main.yml`
  / real `vault*.yml` are gitignored.
- `bootstrap.yml` targets the `builder` group (one play per machine) and injects
  the probed identity per host with `add_host`; `build.yml`/`info.yml` loop each
  machine's `openwrt_variants` (build id = `<machine>-<variant>`).
- A machine's variants build sequentially; machines build in parallel.
- The built image carries the secrets it was built with — treat fetched artifacts
  as sensitive.
- `ansible.cfg` sets `vault_password_file`; ansible-core 2.19 hard-fails when it
  is missing, so CI generates a throwaway file before lint/syntax-check.

## Detailed documentation

- [docs/architecture.md](docs/architecture.md) — component model, configuration
  scope, dependency model, secrets and host-bootstrap.
- [docs/configuration.md](docs/configuration.md) — inventory & variant schema,
  modules, packages, mirrors, firmware secrets.
- [docs/build-pipeline.md](docs/build-pipeline.md) — per-variant pipeline,
  container orchestration, overlay/uci-defaults, artifacts.
- [docs/runbooks.md](docs/runbooks.md) — operational procedures and troubleshooting.
