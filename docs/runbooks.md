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
| sudo (or root) on the build host | Required on the first `make host-bootstrap` run to create the `iac` automation account |
| Docker Engine / Desktop | Must be running on the `builders` host(s) |
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
make host-init HOST=builder-1 HOST_IP=10.0.10.50   # scaffolds group_vars + host_vars/<machine>/
make host-init HOST=openwrt-ib-prod-2 HOST_IP=10.0.10.51   # repeat for each machine
# edit each host_vars/<machine>/main.yml (build_variants: build config)
make install
make vault-init
make vault-edit HOST=builder-1      # per-machine SSH identity vault
make host-bootstrap                       # once; probe iac -> admin -> root
# or, to bootstrap and then build everything in one shot:
make deploy
```

Configuration is split by scope (machine-wide vs per-machine); see
[configuration](configuration.md). `hosts.yml`, the real
`group_vars/builders/main.yml`, and every `host_vars/<machine>/` directory are
gitignored; the committed `group_vars/all/main.yml` baseline and `*.example`
templates are tracked.

### `host-bootstrap`

`make host-bootstrap` probes `iac → admin → root` on **every**
machine (or only `ANSIBLE_ARGS='--limit <machine>'`) and uses the first identity that
works on each; when that is not `iac`, it
(re)creates the `iac` automation account (key-first, NOPASSWD sudo, the `docker`
group when present) and the optional human `admin` account. It self-heals a
rotated/deleted credential. With no `host_iac_ssh_pubkey_file`, an empty
`vault_host_iac_password` is generated into the machine's vault under the same
name. Passwords use a per-account random salt with `update_password: on_create`.
See [architecture](architecture.md) for the full model.

## 3. Build

```bash
make build                            # build every variant (machines in parallel)
make build ANSIBLE_ARGS='--limit builder-1'  # single machine
make deploy                           # host-bootstrap, then build (fresh host to image)
```

`make build` targets `hosts: builders`; the role loops each machine's
`build_variants`, so machines build concurrently and a machine's variants
sequentially. See [build-pipeline](build-pipeline.md) for the per-variant steps,
container orchestration and overlay rendering.

### Artifact retrieval

| Knob | Default | Effect |
|------|---------|--------|
| `artifacts_dir` | `<repo>/artifacts/<artifact_id>` | Control-node destination (always fetched); `<artifact_id>` = `<machine>-<variant>-imagebuilder-<target>-<version-label>-<digest>` where `<version-label>` is `v<release>` or `SNAPSHOT` and `<digest>` covers the variant's build inputs |
| `output_dir` | `~/.cache/openwrt-builder/artifacts/<machine>-<variant>` | Builder-side staging, removed after the build |

Artifacts are always fetched; the `artifacts/` directory is local-only and
gitignored, and is created on demand. The builder's staging and work directories
are removed after a successful fetch, and after a failed build, so repeated
builds do not accumulate files.

### Verify

```bash
ls -R artifacts
sha256sum -c artifacts/*/targets/*/*/sha256sums 2>/dev/null || true
```

### Rollback / cleanup

The build writes only to the builder's `~/.cache/openwrt-builder` (its per-build
staging and work directories are removed after the build) and the control node's
`artifacts/`. `artifacts/` contents are gitignored and can be removed freely;
remove the control-node caches (`.cache`, `collections`, `.ansible`) yourself.
Nothing else on either host is modified.

An interrupted (`Ctrl-C`) build is cleaned up automatically: the run's container
is force-removed with its anonymous `/builder` volume and the builder-side
scratch is deleted. If the wrapper itself is killed with `SIGKILL`, run
`make build` once more (its stale-scratch cleanup escalates via sudo) or remove
the container by label:

```bash
ssh <builder> 'docker ps -aq --filter label=openwrt-builder=true | xargs -r docker rm -f -v'
```

## 4. Query image/profile info

```bash
make info
make info ANSIBLE_ARGS='--limit builder-1'   # single machine
```

Runs `make info` inside the container without building; use it to discover the
target's profiles before setting a variant's `target_profile`. It prints one
machine banner followed by one `== <machine>-<variant> ==` block per variant, with
the dependency-helper chatter
silenced (`QUIET=1`). The query pulls the image/profile index over the network;
`make info` captures its own run to drive the `Querying ImageBuilder info`
spinner, then prints the result. Builds, by contrast, stream live.

## 5. Mirrors

The knob is off by default (official OpenWrt sources); see
[configuration](configuration.md) for the exact semantics. `mirror` is a full
base URL (default `https://mirrors.tuna.tsinghua.edu.cn/openwrt`). To use it for
a release build:

```bash
make build ANSIBLE_ARGS='-e use_mirror=true'
```

A mirror that has not yet synced a new release can cause build failures: turn it
off and use the official source.

## 6. SNAPSHOT images

SNAPSHOT images always use the official `downloads.openwrt.org` source: no
mirror carries `snapshots/`, so `use_mirror` is ignored for them. Build SNAPSHOT
variants without the mirror knob.

## 7. Secrets

- **No firmware secrets are baked** into the image: set the WAN (PPPoE/DHCP) and
  root passwords after first boot.
- **Connection credentials** are per machine (`inventory/host_vars/<machine>/vault.yml`).
- The vault password file lives outside the repo and is never committed;
  `make vault-edit` encrypts a plaintext vault before editing.
- Vault keys are kept in alphabetical order: `make vault-edit` re-sorts
  the top-level keys after the editor closes (comment-preserving) and re-encrypts
  only when the order changed. Hand edits should stay alphabetical too. A save is
  refused when the vault changed while the editor was open, so a secret a deploy
  wrote in the meantime is never lost (the edited text is kept for a merge).
- Values are Jinja-templated and shell-quoted automatically, so special
  characters are safe. WAN (PPPoE/DHCP) and the root password are set after
  first boot.
- **The built image carries the secrets it was built with** — treat artifacts as
  sensitive.

## 8. Adding a module

1. Add overlay files under `roles/imagebuilder/files/overlay/<name>/...` (static)
   or `templates/overlay/<name>/...` (Jinja).
2. Add `<name>` to `module_names` (a presence-based mapping) or `module_flags`
   (a plain boolean) in `roles/imagebuilder/vars/main.yml`.
3. Reference its operator variables in the role defaults and
   `host_vars/example/main.yml`; add an `<name>:` mapping with its fields (or a
   boolean key for a flag module).
4. Add any packages the module needs. A module with package logic (like
   `statistics`) owns its set in `packages.yml`; otherwise list them in the
   variant's `packages`.

For one-off operator settings (extra UCI, extra files), do **not** edit the
role: set the variant's `custom_overlay` to a directory under
`inventory/custom/<machine>/<variant>/`; the role copies it over the image
rootfs after the module overlays. See [configuration](configuration.md#custom-overlay).
5. Run the internal `make lint`, then build with the module active.

## 9. SSH hardening

`make build` (and therefore `make deploy`) also applies `roles/sshd` at the end
when `sshd_hardening_enabled: true` is set in `group_vars/builders/main.yml`. It
closes password login, so it needs a key-only login that survives it — the
`iac` account's key (`host_iac_ssh_pubkey_file`) or root's key
with `sshd_permit_root_login: prohibit-password`. Run it alone with:

```bash
make build ANSIBLE_ARGS='--tags sshd'
```

The role validates the drop-in (`sshd -t`), asserts the effective configuration
(`sshd -T`) and proves a fresh key-only login from the control node; on any
failure it restores the previous drop-in, reloads sshd and fails the run, so the
host keeps its old login policy. The provider console remains the recovery path.

## 10. Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `host-bootstrap`: "no working identity" | Configure the connection passwords in the machine's vault and/or the key paths in `group_vars/builders/main.yml`, or load a key into the SSH agent. If only `root` works, set the root password (or a root private key) |
| `build`/`info` cannot connect as `iac` | Run `make host-bootstrap` once; the effective password is `vault_host_iac_password` (generated when empty), else set `host_iac_ssh_privkey_file`/pubkey |
| Need the auto-generated password | `make vault-view` |
| `build` fails: vault password file missing | Run `make vault-init` |
| `host-bootstrap` user tasks fail (sudo/become) | The probed identity needs sudo or root; the first run must reach the host as `root` or a sudo-capable `admin` |
| preflight: "Docker CLI not found" | Install Docker and ensure it is on PATH on the builder |
| preflight: "Cannot reach the Docker daemon" | Start Docker; ensure the connection user can access the socket (the `iac` user joins the `docker` group when present) |
| preflight: "Docker Python SDK" | Install `docker` for the build host's Python: `<python> -m pip install docker` |
| preflight: "imagebuilder_image is still the example placeholder" | Replace it with a real tag from hub.docker.com/r/openwrt/imagebuilder/tags |
| `Module ... does not expose VERSION_PATH/TARGET` | Use an official `openwrt/imagebuilder` tag |
| `Packages are both added and removed` | Remove the `-pkg`/`pkg` conflict in a variant's `packages` |
| `Duplicate overlay target files across modules` | Two active modules ship the same file path; rename or disable one |
| A module does not run | The block is missing or empty; list at least one of its fields (a flag module needs `true`) |
| `statistics` packages | The module adds `luci-app-statistics` + `collectd-mod-sensors`/`collectd-mod-irq` itself; entries in `packages` are removed/deduped |
| WAN is not configured | The image intentionally leaves WAN (DHCP/PPPoE) unset; configure it after first boot |
| Build fails after enabling a mirror | Mirror sync lag; disable `use_mirror`. `mirror` is a full base URL ending at the mirror's OpenWrt path |
| Build hangs at "Building package index..." (25.12+, APK) | The container `nofile` ulimit is unbounded and fakeroot's `faked` spins; the role pins `nofile:65536:65536`, keep it bounded |
| Artifacts owned by root | The in-container `chown` needs `HOST_UID`/`HOST_GID` (from facts) |
| Artifacts not in the control node's `artifacts/` | The fetch failed; the builder staging directory is only removed after a successful fetch, so re-run `make build` and check the fetch task |
| `--tags sshd` fails at "Prove a key-only login" | The chosen identity has no authorized key yet: set `host_iac_ssh_pubkey_file` (or root's) and run `make host-bootstrap`, or unset `sshd_hardening_enabled` |
| Cannot reach a builder over SSH | Fix its `ansible_host` in `hosts.yml`; the connection identity comes from the committed `group_vars/all/main.yml` |

## Manual verification on a disposable host

The cases `tests/` cannot cover: they need a real build machine, the build
container and destructive steps. Run them on a disposable machine with its own
inventory and vault password file, read-only checks first, destructive ones last,
and evidence under `/tmp/opencode/test-run-<stamp>/artifacts/<case>/`, redacted.
The expected result is the contract — a deviation is a defect to record, not a
reason to skip.

### Bootstrap and build

- [ ] `make host-init` scaffolds `inventory/hosts.yml` and `host_vars/<machine>/`;
      the `CHANGE_ME_HOST_IP` placeholder is refused until replaced.
- [ ] `make host-bootstrap`: `iac` created with passwordless sudo and the configured
      keys, Docker Engine and Compose v2 present; a second run changes nothing.
- [ ] `make build` builds every declared variant and fetches the images into the
      control node's `artifacts/`; each artifact is a complete image for its target
      and profile, and the builder keeps no per-build artifacts or work directory
      afterwards (success and failure).
- [ ] A second `make build` with `force_pull: false` reuses the cached imagebuilder
      input instead of downloading it again; `force_pull: true` rebuilds.
- [ ] Two variants on one machine build in sequence without sharing or clobbering
      their `build_id` directories.
- [ ] Artifacts are owned by the invoking user (`HOST_UID`/`HOST_GID`), not root.

### Variants, mirrors and info

- [ ] Each variant's target/profile/packages and enabled module mappings are
      reflected in the image (log in and check the declared package set).
- [ ] `make info` returns the image/profile metadata without starting a build.
- [ ] A mirror-enabled release build succeeds (`mirror` is a full base URL), a
      SNAPSHOT build ignores `use_mirror`, and disabling the mirror falls back
      cleanly.

### Secrets and security

- [ ] No firmware secrets are in the artifacts or the tree: a built image carries
      no WAN/root password.
- [ ] Each machine vault is `0600` and encrypted; `make vault-view` reads it
      and `-vvv` shows no value.
- [ ] With `sshd_hardening_enabled`: password login refused, keyed login works, and
      a missing authorized key blocks the role before it writes the config.
- [ ] `make lint` and `make test` are green.
- [ ] `AGENTS.md`, `docs/` and this runbook match observed behaviour; a
      contradiction is recorded as a defect.
