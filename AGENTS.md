# AGENTS.md

Ansible IaC that builds customized **OpenWrt firmware images** with the official
`openwrt/imagebuilder` running in a Docker container on a build host.

**One inventory host = one build machine**; each machine builds one or more
**variants** (one `(target, profile, settings)` each), listed in its
`host_vars/<machine>/main.yml` as `build_variants`. Entry playbooks:
`playbooks/bootstrap.yml` (once, provisions the `iac` automation account on every
machine), `playbooks/build.yml` (builds every variant, plus opt-in SSH
hardening) and `playbooks/info.yml`
(read-only ImageBuilder query). The build logic lives in `roles/imagebuilder/`;
the opt-in key-only SSH hardening lives in `roles/sshd/`.

## Commands

- `make help` — aligned target list; overridable variables (`HOST`, `EXTRA`) are
  shown inline. `help` is listed last.
- `make install` — the sole dependency entry point (toolchain, collections,
  `sshpass`, `passlib`, Keychain). Every other target depends on it.
- `make host-init HOST=<name> HOST_IP=<addr>` — scaffold `inventory/hosts.yml` and
  `group_vars/builders/main.yml` comment-free from the examples, plus
  `host_vars/<name>/` (with a `build_variants` list); add `<name>` under
  `builders.hosts` with `HOST_IP` as its `ansible_host`; encrypt the vault (dir
  `0700`, file `0600`). HOST defaults to `builder-1` and `HOST_IP` to a
  placeholder; re-running does not overwrite existing files.
- `make host-bootstrap` — once: probe `iac → admin → root` on
  every machine and create/repair the `iac` automation account (key-first, NOPASSWD sudo,
  `docker` group) plus the human `admin` account when `create_admin_account` is set.
  `REFRESH=1` refreshes host keys first.
- `make deploy` — one-click: `host-bootstrap` then `build`.
- `make build` / `make info` — build every variant (machines in parallel) / query
  ImageBuilder info; limit to one machine with `EXTRA='--limit <machine>'`.
- `make hostkey-init` — refresh every machine's SSH host key in the control node's
  `known_hosts` (drop the stale entry, re-add); `host-bootstrap`/`deploy` run it
  first when `REFRESH=1` is set.
- `make vault-init` — generate the vault password file (outside the repo).
- `make vault-edit-group` — edit the shared builder connection vault; a plaintext
  vault is encrypted first, and the top-level keys are re-sorted alphabetically
  after the editor closes.
- `make vault-view` — read-only: print the shared builder connection vault.
- Internal (hidden from `make help`): `lint` (syntax-check + `ansible-lint` +
  `yamllint` + `shellcheck` + the operator-example audit + the knob validation +
  `scripts/check_repo_privacy.py` — tracked local-only trees, credential files
  and real addresses or host names, allowlist in `.privacy-allowlist` — and
  `gitleaks`; run by CI), `make test` (helper unit suite) and the `ensure-*` /
  `agent-*` / `keychain-*` / `run-playbook` helpers. `make build` and `make lint`
  assert every operator knob against `inventory/knob_schema.yml` through
  `playbooks/validate_knobs.yml`.
- `EXTRA` is appended to every `ansible-playbook` invocation, e.g.
  `make build EXTRA='--limit builder-1'`.

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
  `sudo -n true` for the NOPASSWD `iac` account, while a password-sudo identity
  (`admin`) is proven with `sudo -S` before it is chosen. A
  half-provisioned account (login OK, sudoers not yet written) must never be
  chosen, or the bootstrap can no longer repair that host.

## Secrets and local-only files

- `inventory/group_vars/all/main.yml` — committed project-owned baseline for
  every build machine: the SSH connection identity wiring, the connection-plugin
  interface derived from it, the `iac` account's fixed uid/gid (operator override in `group_vars/builders/main.yml`, template `main.yml.example`),
  the shared connection vault path, and the supported ansible-core range.
- `inventory/knob_schema.yml` — committed validation expression per top-level
  operator knob; `playbooks/validate_knobs.yml` asserts the effective values and
  the `build_variants` entries (`make lint` / `make build` run it).
- `inventory/group_vars/builders/main.yml` — machine-wide operator overrides, local
  only; the committed template is `main.yml.example` (scaffolded by `host-init`).
  The project-owned wiring lives in the committed `group_vars/all/main.yml`. The
  non-secret connection knobs (the admin account name and the per-identity key
  paths) live here; connection passwords stay in the vault.
- `inventory/group_vars/builders/vault.yml` — machine-wide connection passwords
  (`vault_host_<id>_password`), operator-owned; a missing generated value (the
  `iac` password when no key is set, the `admin` password when
  `create_admin_account`) is merged in place by `make host-bootstrap` under the
  same name.
- No per-machine firmware vault exists. No firmware secrets are baked into the
  image: the WAN (PPPoE/DHCP) and root passwords are set after first boot.
  Connection credentials live in `group_vars/builders/vault.yml`.
- Vault password file:
  `~/.config/projects/openwrt-image-builder-iac/ansible_vault_password`
  (pointed to by `ansible.cfg`, auto-generated by `make vault-init`); never
  committed.
- Reference secrets by path only; the private key content is never stored in the
  vault. SSH prefers the key (explicit path `host_<id>_ssh_privkey_file` in the
  non-secret group config, or agent) then the password, capped at one prompt.

## Gotchas

- Committed: `group_vars/all/main.yml` (project-owned baseline),
  `host_vars/example/` and the `group_vars/builders/*.example` templates.
  `inventory/hosts.yml`, real machine directories, and `group_vars/builders/main.yml`
  / real `vault*.yml` are gitignored.
- `bootstrap.yml` targets the `builders` group (one play per machine) and injects
  the probed identity per host with `add_host`; `build.yml`/`info.yml` loop each
  machine's `build_variants` (build id = `<machine>-<variant>`).
- A machine's variants build sequentially; machines build in parallel.
- The built image carries the secrets it was built with — treat fetched artifacts
  as sensitive.
- `ansible.cfg` sets `vault_password_file`; ansible-core 2.19 hard-fails when it
  is missing, so CI generates a throwaway file before lint/syntax-check.

## Testing and verification

Two layers, and only one of them is executable:

- **Automated** — `make lint` (playbook syntax check, `ansible-lint`,
  `yamllint`, `shellcheck`, the knob-schema/example audit, the host-key and
  repository-privacy checks, `gitleaks`) and `make test` (the helper suite under
  `tests/`). Both run in CI on every change.
- **Manual** — the cases that need a disposable host and destructive steps; they
  are a checklist in `docs/runbooks.md` and are re-run when a role, the bootstrap
  or the backup path changes. `tests/` covers the helpers, not a live SSH session
  or a running stack.

### Environment and safety boundaries

- **Live hosts are read-only.** Inspect them with `make print`, `make print
  HOST=<name>`, `docker inspect`, `systemctl status` and external probes. No
  deploy, bootstrap, backup, restore or hardening run targets a live host.
- **Every state-changing or destructive case runs on a disposable build machine**
  (systemd, Docker Engine with Compose v2, sshd) whose cache and artifacts can be
  thrown away; the build container is privileged enough that it must never share a
  machine with anything else under test.
- **Isolate the test environment**: its own inventory (never the real
  `inventory/hosts.yml`) and its own vault password file.
- **Ask before creating resources** — hosts, DNS records, storage paths — and
  before anything that costs money or touches a system outside the test host.
- **Order of work**: read-only checks first, then state-changing cases, then
  destructive ones; snapshot or back up before every destructive step.
- **Never print, paste or commit secrets.** Redact evidence before quoting it; a
  secret in a log or a report is itself a defect to record.

### Execution rules

- Write the expected result before running a case; never backfill it.
- Cases are independently runnable; declare prerequisites where order matters.
- A defect gets a reproducing case before anything else happens.
- Separate product defects from environment failures, and state the evidence for
  that call.
- Skip only with a recorded reason; never count an unexecuted case as a pass.
- No change to the product to make a case pass; no drive-by fixes.

### Recording and defects

- Keep raw logs, `-vvv` output, `docker inspect`, `systemctl status` and probe
  responses under `/tmp/opencode/test-run-<UTC stamp>/artifacts/<case>/`; never
  store a decrypted vault, and redact before quoting.
- Severity: `blocker` (data loss, outage, security), `major` (feature unusable, or
  docs contradict behaviour), `minor`, `nit`. Each entry carries a minimal
  reproduction, expected vs actual, impact, evidence path and a suggested fix;
  merge entries that share a root cause.

### Definition of done

- `make lint` and `make test` green;
- the manual checklist passes on the disposable host, and a second run at the
  same desired state reports `changed=0` outside the documented non-idempotent
  steps;
- every destructive path fails safely with an actionable message;
- no unexplained high-severity security finding;
- every conclusion points at evidence, and every unexecuted check names the
  reason and what would unblock it.

## Repository automation

- Remote `cwbitz/openwrt-image-builder-iac`, default branch `main`. Every change
  lands through a `<type>/<slug>` pull request; merge commits and rebase are
  disabled, squash merge is the only method, and merged branches are deleted.
- The `Protect main` ruleset has no bypass actors. It requires a pull request and
  the status checks `lint` and `pr-title`, with a strict up-to-date branch.
- PR titles are Conventional Commits, validated by
  `.github/workflows/pr-title.yml`; the squash merge uses the PR title verbatim.
- CI (`.github/workflows/ci.yml`) runs the `lint` job with
  `ANSIBLE_CONFIG=ci/ansible-ci.cfg` (placeholder inventory in
  `ci/inventory.yml`) plus a full-history `gitleaks` scan and `make test`.
- Release automation uses release-please: non-major release PRs auto-merge,
  major releases stay manual. Renovate updates dependencies; major updates and
  the pinned toolchain need manual review.

## Detailed documentation

- [docs/architecture.md](docs/architecture.md) — component model, configuration
  scope, dependency model, secrets and host-bootstrap.
- [docs/configuration.md](docs/configuration.md) — inventory & variant schema,
  modules, packages, mirrors, and post-boot credentials.
- [docs/build-pipeline.md](docs/build-pipeline.md) — per-variant pipeline,
  container orchestration, overlay/uci-defaults, artifacts.
- [docs/runbooks.md](docs/runbooks.md) — operational procedures and troubleshooting.
