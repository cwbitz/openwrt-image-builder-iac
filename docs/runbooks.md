# Runbooks

Operational procedures for building OpenWrt firmware with
`openwrt-image-builder-iac`. For the design see
[architecture](architecture.md), for configuration see
[configuration](configuration.md), and for what a build does see
[build-pipeline](build-pipeline.md).

## 1. Prerequisites

| Requirement | Notes |
|-------------|-------|
| Control node | Where you run `make`; hosts the repo and the Ansible toolchain |
| Build host | A separate LAN machine (by default) running Docker Engine; SSH-reachable as the connection user, who must access the Docker daemon |
| sudo (or root) on the build host | Required on the first `make host-bootstrap` run to create the `ansible` service account |
| Docker Engine / Desktop | Must be running on the `builder` host(s) |
| python >= 3.8 | Control node; runs `ansible-core` and the `community.docker` modules |
| `ansible-core` + `python` | Pinned in `.tool-versions` (`mise install` / `asdf install`) |
| `community.docker` | Installed into `collections/` by `make install` |
| `openssl` | Control node; generates secret values (`make install`) |
| `sshpass` | Control node; password SSH during `make host-bootstrap` (`make install`) |
| `passlib` | Control node; `password_hash` for the automation user (`make install`) |
| Keychain 3 | Control node; **fallback** ssh-agent, ensured by `make install` |
| vault password | Created once by `make vault-init`; required to store/read generated secrets |
| docker Python SDK | On the **build host** (not the control node); checked by the role preflight |

`make install` is the sole dependency entry point and is idempotent; see
[architecture](architecture.md) for what it ensures and the docker-SDK boundary.

## 2. First-time setup

```bash
mise install
# One inventory host = one build machine; list its variants in the machine's main.yml.
make host-init HOST=openwrt-ib-prod-1 HOST_IP=10.0.10.50   # scaffolds group_vars + host_vars/<machine>/
make host-init HOST=openwrt-ib-prod-2 HOST_IP=10.0.10.51   # repeat for each machine
# edit each host_vars/<machine>/main.yml (openwrt_variants: build config)
# and each host_vars/<machine>/vault.yml (firmware secrets)
make install
make vault-init
make vault-edit-group                     # shared SSH identity vault
make vault-edit HOST=openwrt-ib-prod-1    # that machine's firmware secrets
make host-bootstrap                       # once; probe ansible -> admin -> root on every machine
# or, to bootstrap and then build everything in one shot:
make deploy
```

Configuration is split by scope (machine-wide vs per-machine); see
[configuration](configuration.md). `hosts.yml`, the real
`group_vars/builder/main.yml`, and every `host_vars/<machine>/` directory are
gitignored; only the committed `*.example` templates are tracked.

### `host-bootstrap`

`make host-bootstrap` probes `ansible → admin → root` on **every** machine and
uses the first identity that works on each; when that is not `ansible`, it
(re)creates the `ansible` service account (key-first, NOPASSWD sudo, the `docker`
group when present) and the optional human `admin` account. It self-heals a
rotated/deleted credential. With no `vault_host_ansible_ssh_pubkey_file`, an empty
`vault_host_ansible_password` is generated into the shared vault under the same
name. Passwords use a per-account random salt with `update_password: on_create`.
See [architecture](architecture.md) for the full model.

## 3. Build

```bash
make build                            # build every variant (machines in parallel)
make build EXTRA='--limit openwrt-ib-prod-1'  # single machine
make deploy                           # host-bootstrap, then build (fresh host to image)
```

`make build` targets `hosts: builder`; the role loops each machine's
`openwrt_variants`, so machines build concurrently and a machine's variants
sequentially. See [build-pipeline](build-pipeline.md) for the per-variant steps,
container orchestration and overlay rendering.

### Artifact retrieval

| Knob | Default | Effect |
|------|---------|--------|
| `openwrt_fetch_artifacts` | `true` | Pull built artifacts from the builder to the control node |
| `openwrt_artifacts_dir` | `<repo>/artifacts/<machine>-<variant>` | Control-node destination |
| `openwrt_output_dir` | `~/.cache/openwrt-builder/artifacts/<machine>-<variant>` | Builder-side output directory |

The `artifacts/` directory itself is tracked (via `.gitkeep`); its contents are
gitignored. Disable retrieval for large builds or when the builder is the control
node and you do not need a second copy.

### Verify

```bash
ls -R artifacts
sha256sum -c artifacts/*/targets/*/*/sha256sums 2>/dev/null || true
```

### Rollback / cleanup

The build writes only to the builder's `~/.cache/openwrt-builder` and (when
fetching) the control node's `artifacts/`. `artifacts/` contents are gitignored and
can be removed freely; remove the control-node caches (`.cache`, `collections`,
`.ansible`) yourself. Nothing else on either host is modified.

## 4. Query image/profile info

```bash
make info
make info EXTRA='--limit openwrt-ib-prod-1'   # single machine
```

Runs `make info` inside the container without building; use it to discover the
target's profiles before setting a variant's `openwrt_profile`. It prints one
`== <machine>-<variant> ==` block per variant, with the dependency-helper chatter
silenced (`QUIET=1`). The query pulls the image/profile index over the network and
the shared runner buffers the output, so the terminal can pause (a `Querying
ImageBuilder info` spinner is shown) before printing.

## 5. Mirrors

Both knobs are off by default (official OpenWrt sources); see
[configuration](configuration.md) for the exact semantics. To use a domestic
mirror for a build:

```bash
make build EXTRA='-e openwrt_use_mirror=true -e openwrt_setup_use_mirror=true'
```

A mirror that has not yet synced a new release can cause build failures: turn it
off and use the official source.

## 6. SNAPSHOT images

Use `openwrt_setup_use_mirror: true` (USTC by default) to speed up the
ImageBuilder tarball download without changing the package repositories:

```bash
make build EXTRA='-e openwrt_setup_use_mirror=true'
```

The same knob also works for release images; combined with
`openwrt_use_mirror: true` it keeps every download off `downloads.openwrt.org`.

## 7. Secrets

- **Firmware secrets** are per machine
  (`inventory/host_vars/<machine>/vault.yml`) and keyed by variant name; see
  [configuration](configuration.md) for the layout.
- **Connection credentials** are machine-wide (`inventory/group_vars/builder/vault.yml`).
- The vault password file lives outside the repo and is never committed;
  `make vault-edit HOST=<machine>` encrypts a plaintext vault before editing.
- Values are Jinja-templated and shell-quoted automatically, so special
  characters are safe. Leave a secret empty to skip its module.
- **The built image carries the secrets it was built with** — treat artifacts as
  sensitive.

## 8. Adding a module

1. Add overlay files under `roles/imagebuilder/files/overlay/<name>/...` (static)
   or `templates/overlay/<name>/...` (Jinja).
2. Add its packages to `openwrt_module_packages` in
   `roles/imagebuilder/vars/main.yml` (if any).
3. Add `<name>` to `openwrt_known_modules`.
4. Reference any operator variables in `host_vars/builder.example/main.yml`.
5. Run the internal `make lint`, then build with the module active.

## 9. Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `host-bootstrap`: "could not log in as ansible, admin or root" | Configure one of `vault_host_ansible_*` / `vault_host_admin_*` / `vault_host_root_*` (`password` / `ssh_privkey_file`), or load a key into the SSH agent. If only `root` works, set `vault_host_root_password` (or a root private key) |
| `build`/`info` cannot connect as `ansible` | Run `make host-bootstrap` once; the effective password is `vault_host_ansible_password` (generated when empty), else set `vault_host_ansible_ssh_privkey_file`/pubkey |
| Need the auto-generated password | `make vault-view` |
| `build` fails: vault password file missing | Run `make vault-init` |
| `host-bootstrap` user tasks fail (sudo/become) | The probed identity needs sudo or root; the first run must reach the host as `root` or a sudo-capable `admin` |
| preflight: "Docker CLI not found" | Install Docker and ensure it is on PATH on the builder |
| preflight: "Cannot reach the Docker daemon" | Start Docker; ensure the connection user can access the socket (the `ansible` user joins the `docker` group when present) |
| preflight: "Docker Python SDK" | Install `docker` for the build host's Python: `<python> -m pip install docker` |
| `Module ... does not expose VERSION_PATH/TARGET` | Use an official `openwrt/imagebuilder` tag |
| `Packages are both added and removed` | Remove the `-pkg`/`pkg` conflict in a variant's packages |
| `Duplicate overlay target files across modules` | Two active modules ship the same file path; rename or disable one |
| Build fails after enabling a mirror | Mirror sync lag; disable `openwrt_use_mirror`. For 25.12+ (APK) the mirror path must include the OpenWrt prefix |
| Build hangs at "Building package index..." (25.12+, APK) | The container `nofile` ulimit is unbounded and fakeroot's `faked` spins; the role pins `nofile:65536:65536`, keep it bounded |
| Artifacts owned by root | The in-container `chown` needs `HOST_UID`/`HOST_GID` (from facts) |
| Artifacts not in the control node's `artifacts/` | Check `openwrt_fetch_artifacts` (default true); they are also kept on the builder at `openwrt_output_dir` |
| Cannot reach a builder over SSH | Fix its `ansible_host` in `hosts.yml`; the connection identity comes from `group_vars/builder/main.yml` |
