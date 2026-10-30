<div align="center">

# OpenWrt Image Builder IaC

Ansible IaC that builds customized OpenWrt firmware images with the official OpenWrt ImageBuilder running in a Docker container.

Reproducible OpenWrt firmware, built in Docker

[![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](LICENSE)
</div>

---

## Overview

One inventory host = one build **machine**; each machine builds one or more
**variants** (one `(target, profile, settings)` each, listed in its `host_vars`).
`make build` builds every variant of every machine, and the artifacts are fetched
back to the control node.

| Layer | Tool | Responsibility |
|-------|------|----------------|
| Build host | **Docker** | runs the official `openwrt/imagebuilder` container |
| Firmware image | **Ansible** (role `imagebuilder`) | module resolution, package passthrough, uci-defaults overlay, container orchestration |
| Operator config | `host_vars/<machine>/main.yml` + `group_vars/builders/main.yml` | per-machine build variants; machine-wide operator overrides (e.g. `create_admin_account`) |

The control node (where `make` runs) and the build host (the machine running
Docker) are separate LAN machines by default; building on the control node itself
is also possible (`ansible_connection: local`).

## Quick Start

```bash
# 0) Control-node toolchain: asdf/mise pin python + ansible-core in
#    .tool-versions. Install them once:
mise install           # or: asdf install

# 1) Scaffold one config dir per build MACHINE (the dir name must match the
#    inventory host name). Then list its variants in the machine's main.yml.
make host-init HOST=builder-1 HOST_IP=10.0.10.50
#    (comment-free; builder-1 is added under builder.hosts automatically)
#    -> edit inventory/host_vars/builder-1/main.yml (build_variants)
#    -> add another machine: make host-init HOST=openwrt-ib-prod-2 HOST_IP=10.0.10.51

# 2) Secrets: connection secrets go in the shared vault (once per fleet);
#    no firmware secrets are baked (WAN/root passwords are set after boot).
make install           # toolchain + collections + sshpass/passlib + Keychain
make vault-init        # one-time: vault password (back it up)
make vault-edit-group  # shared SSH identity vault

# 3) Bootstrap the build machine(s) once (probe iac -> admin -> root,
#    provision the 'iac' automation account: password, keys, NOPASSWD sudo).
make host-bootstrap

# 4) Build every variant (machines in parallel; connects as 'iac')
make build
make build EXTRA='--limit builder-1'   # or just one machine

# One-shot alternative to steps 3-4: bootstrap the hosts, then build
make deploy
```

Each variant is built on its machine under
`~/.cache/openwrt-builder/artifacts/<machine>-<variant>/`, then fetched to the
control node's `artifacts/<machine>-<variant>/targets/<target>/<subtarget>/` when
`fetch_artifacts` is enabled (the default). Use `make info` to inspect the
ImageBuilder image and profile information without building.

## Directory Layout

```
openwrt-image-builder-iac/
├── ansible.cfg                        # canonical Ansible config (repo root == Ansible root)
├── inventory/
│   ├── hosts.yml.example              # builders group: one host per build machine
│   ├── group_vars/
│   │   ├── all/                       # committed project-owned baseline (SSH identity wiring, uid/gid, shared vault path)
│   │   └── builders/                  # machine-wide operator overrides (main.yml local-only)
│   │       ├── main.yml.example       # operator knob template (main.yml is local-only)
│   │       └── vault.yml.example      # shared connection secrets template
│   └── host_vars/
│       └── example/                   # machine template; real machines gitignored
│           └── main.yml               # per-machine build variants (build_variants)
├── playbooks/
│   ├── bootstrap.yml                  # probe + provision the service account (make host-bootstrap)
│   ├── build.yml                      # build firmware (make build)
│   └── info.yml                       # query ImageBuilder info (make info)
├── roles/imagebuilder/
│   ├── defaults/main.yml              # fallbacks for the per-variant operator knobs
│   ├── vars/main.yml                  # module registry, internals
│   ├── tasks/                         # preflight/modules/setup/packages/overlay/build/info
│   ├── files/overlay/<module>/...     # static uci-defaults overlay
│   └── templates/overlay/<module>/    # templated uci-defaults + build.sh.j2
├── roles/sshd/                        # opt-in key-only SSH hardening (tag sshd)
├── requirements.yml                   # collections
├── artifacts/                         # fetched firmware (dir tracked; contents gitignored)
├── docs/                              # architecture / configuration / build-pipeline / runbooks
├── .tool-versions                     # pinned control-node toolchain (asdf/mise)
├── Makefile                           # unified orchestration
└── README.md
```

## Makefile Targets

| Command | Purpose |
|---------|---------|
| `make install` | **Sole dependency entry**: ensures the control-node toolchain, collections, `sshpass`, `passlib` and Keychain |
| `make host-init HOST=<name>` | Scaffold `group_vars/builders/main.yml` + `host_vars/<name>/` from the examples; add the machine with `HOST_IP=<addr>` |
| `make host-bootstrap` | Probe iac → admin → root on every machine and provision the automation account |
| `make deploy` | One-click first build: `host-bootstrap` then `build` |
| `make build` | Build every variant of every machine (ImageBuilder container) |
| `make info` | Query image/profile information (no build) |
| `make vault-init` | One-time: generate the vault password |
| `make vault-edit-group` | Edit the shared builder connection vault |
| `make vault-view` | View the shared builder connection vault (read-only) |

`make lint` (syntax-check + `ansible-lint` + the operator-example audit) is an
**internal** target invoked by CI; it is hidden from `make help` but can be run
directly. `make lint` and `make build` also validate the operator knobs against
`inventory/knob_schema.yml` before any change.

## Documentation

- [docs/architecture.md](docs/architecture.md) — model, configuration scope, dependency model, secrets and bootstrap.
- [docs/configuration.md](docs/configuration.md) — inventory & variant schema, modules, packages, mirrors, post-boot credentials.
- [docs/build-pipeline.md](docs/build-pipeline.md) — per-variant pipeline, container orchestration, overlay/uci-defaults, artifacts.
- [docs/runbooks.md](docs/runbooks.md) — operational procedures and troubleshooting.

## License

MIT — see [LICENSE](./LICENSE).
