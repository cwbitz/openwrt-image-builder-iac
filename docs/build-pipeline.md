# Build pipeline

What `roles/imagebuilder` does for one variant — the pipeline, the container
orchestration, the ImageBuilder internals, the overlay, and artifact handling.

`build.yml` targets `hosts: builders` and loops each machine's `build_variants`
(the current entry is the `build_variant` var); the role slices below run once
per variant and are individually selectable with `--tags`
(`preflight|modules|setup|packages|overlay|build`).

## Pipeline

1. **preflight** — asserts `imagebuilder_image` (the variant's) is set and is
   not the example placeholder, the Docker CLI/daemon are reachable on the build
   host, and the `docker` Python SDK is importable by its interpreter.
2. **modules** — resolves the enabled modules from each module mapping's
   `enabled` flag.
3. **setup** — pulls the image if needed and derives everything from the image's
   environment (see below).
4. **packages** — merges the statistics module's package set (removing any
   duplicates from the operator list), deduplicates, and fails on add/remove
   conflicts.
5. **overlay** — renders the enabled modules' uci-defaults and the `network`
   block when set (see below).
6. **build** — runs the container, then locates and (optionally) fetches artifacts.
7. **fetch** (part of build) — when `fetch_artifacts` is true, pulls the
   artifacts to the control node.

## ImageBuilder internals (setup)

The role reads `VERSION_PATH` and `TARGET` from the image's `Config.Env` (an
official `openwrt/imagebuilder` tag always exposes them) and derives:

- the release path (`snapshots` for SNAPSHOT images, else the release path),
- the target and version,
- the container name `openwrt-bw-<target>-<version>-<machine>-<variant>`.

`force_pull` forces a fresh image pull.

## Container orchestration (build)

`community.docker.docker_container` runs the official image once per variant:

- mounts: the (host) output dir → `/builder/bin`, the rendered `build.sh`, and the
  rendered overlay files;
- env: `HOST_UID`/`HOST_GID` (from facts), `OPENWRT_PACKAGES`,
  `OPENWRT_PROFILE`, `OPENWRT_EXTRA_FIRMWARE_NAME`, `OPENWRT_DISABLED_SERVICES`,
  `OPENWRT_ROOTFS_PARTSIZE`;
- `ulimits: nofile:65536:65536` — a bounded `nofile` limit. The host tools use
  fakeroot, whose `faked` daemon closes every fd up to `RLIMIT_NOFILE` on startup;
  the daemon's near-infinite inherited limit turns that into a hang. Keep it
  bounded.
- `cleanup: true`, `detach: false`, `output_logs: true`; a non-zero exit status is
  asserted as a build failure.

In the container, `templates/build.sh.j2` sets `TMPDIR` to a workspace on disk
(avoiding tmpfs exhaustion), runs `setup.sh` (release images with
`use_mirror`: via `mirror` first, then the official source; SNAPSHOT images
always via the official source) when the ImageBuilder environment is missing,
applies the repository mirror when enabled (release images only), then calls
`make info` and `make image`. On exit it restores ownership of the artifacts
to the invoking host user.

## Overlay / uci-defaults

Modules ship first-boot config as uci-defaults under the role:

- `files/overlay/<module>/...` — copied verbatim;
- `templates/overlay/<module>/...` — rendered as Jinja templates by Ansible's
  `template` module.

`network` is not a module: when a variant's `network` block is non-empty, the
role adds the `network` overlay to the selected set and renders
`templates/overlay/network/etc/uci-defaults/89-network`.

The role selects the files of the active modules, asserts no two active modules
target the same path, installs every `etc/uci-defaults/*` and `etc/hotplug.d/*`
file `0755`, and every other file `0644`. After that it copies the variant's
`custom_overlay` directory (if set) over the same tree, preserving modes.
Rendered output is assembled under the variant's work directory and mounted into
the container.

## Artifacts

| Path | Where |
|------|-------|
| `~/.cache/openwrt-builder/artifacts/<machine>-<variant>` | builder-side output (`output_dir`) |
| `<repo>/artifacts/<machine>-<variant>` | control-node copy (`artifacts_dir`), contents gitignored |

When `fetch_artifacts` is true (default), the artifacts are fetched with
the `targets/<target>/<subtarget>/` layout preserved (firmware images,
`profiles.json`, `sha256sums`, ...). Set it to `false` to keep them only on the
builder. Re-running with the same inputs converges on the same output.
