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
| Firmware image | **Ansible** (role `imagebuilder`) | module resolution, package collection, uci-defaults overlay, container orchestration |
| Operator config | `host_vars/<machine>/main.yml` + `group_vars/builder/main.yml` | per-machine build variants; machine-wide connection identity |

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
make host-init HOST=openwrt-ib-prod-1 HOST_IP=10.0.10.50
#    (comment-free; openwrt-ib-prod-1 is added under builder.hosts automatically)
#    -> edit inventory/host_vars/openwrt-ib-prod-1/main.yml (openwrt_variants)
#    -> add another machine: make host-init HOST=openwrt-ib-prod-2 HOST_IP=10.0.10.51

# 2) Secrets: connection secrets go in the shared vault (once per fleet);
#    firmware secrets go in each machine's vault (one sub-key per variant).
make install           # toolchain + collections + sshpass/passlib + Keychain
make vault-init        # one-time: vault password (back it up)
make vault-edit-group  # shared SSH identity vault
make vault-edit HOST=openwrt-ib-prod-1   # that machine's firmware secrets

# 3) Bootstrap the build machine(s) once (probe ansible -> admin -> root, provision
#    the 'ansible' service account: generated password, keys, NOPASSWD sudo).
make host-bootstrap

# 4) Build every variant (machines in parallel; connects as 'ansible')
make build
make build EXTRA='--limit openwrt-ib-prod-1'   # or just one machine

# One-shot alternative to steps 3-4: bootstrap the hosts, then build
make deploy
```

Each variant is built on its machine under
`~/.cache/openwrt-builder/artifacts/<machine>-<variant>/`, then fetched to the
control node's `artifacts/<machine>-<variant>/targets/<target>/<subtarget>/` when
`openwrt_fetch_artifacts` is enabled (the default). Use `make info` to inspect the
ImageBuilder image and profile information without building.

## Directory Layout

```
openwrt-image-builder-iac/
├── ansible.cfg                        # canonical Ansible config (repo root == Ansible root)
├── inventory/
│   ├── hosts.yml.example              # builder group: one host per build machine
│   ├── group_vars/
│   │   └── builder/                   # machine-wide shared config (main.yml local-only)
│   │       ├── main.yml.example       # SSH identity, service account, shared vault
│   │       └── vault.yml.example      # shared connection secrets template
│   └── host_vars/
│       └── builder.example/           # machine template; real machines gitignored
│           ├── main.yml               # per-machine build variants (openwrt_variants)
│           └── vault.yml.example      # per-machine firmware secrets template
├── playbooks/
│   ├── bootstrap.yml                  # probe + provision the service account (make host-bootstrap)
│   ├── build.yml                      # build firmware (make build)
│   └── info.yml                       # query ImageBuilder info (make info)
├── roles/imagebuilder/
│   ├── defaults/main.yml              # fallbacks for the per-variant operator knobs
│   ├── vars/main.yml                  # module registry, package lists, internals
│   ├── tasks/                         # preflight/modules/setup/packages/overlay/build/info
│   ├── files/overlay/<module>/...     # static uci-defaults overlay
│   └── templates/overlay/<module>/    # templated uci-defaults + build.sh.j2
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
| `make host-init HOST=<name>` | Scaffold `group_vars/builder/main.yml` + `host_vars/<name>/` from the examples (vault encrypted); add the machine with `HOST_IP=<addr>` |
| `make host-bootstrap` | Probe ansible → admin → root on every machine and provision the service account |
| `make deploy` | One-click first build: `host-bootstrap` then `build` |
| `make build` | Build every variant of every machine (ImageBuilder container) |
| `make info` | Query image/profile information (no build) |
| `make vault-init` | One-time: generate the vault password |
| `make vault-edit HOST=<name>` | Edit a machine's vault |
| `make vault-edit-group` | Edit the shared builder connection vault |
| `make vault-view` | View every machine's vault + the shared vault (read-only) |

`make lint` (syntax-check + `ansible-lint`) is an **internal** target invoked by
CI; it is hidden from `make help` but can be run directly.

## Documentation

- [docs/architecture.md](docs/architecture.md) — model, configuration scope, dependency model, secrets and bootstrap.
- [docs/configuration.md](docs/configuration.md) — inventory & variant schema, modules, packages, mirrors, firmware secrets.
- [docs/build-pipeline.md](docs/build-pipeline.md) — per-variant pipeline, container orchestration, overlay/uci-defaults, artifacts.
- [docs/runbooks.md](docs/runbooks.md) — operational procedures and troubleshooting.

## License

MIT — see [LICENSE](./LICENSE).
