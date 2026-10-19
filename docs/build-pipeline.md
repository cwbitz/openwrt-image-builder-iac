# Build pipeline

What `roles/imagebuilder` does for one variant — the pipeline, the container
orchestration, the ImageBuilder internals, the overlay, and artifact handling.

`build.yml` targets `hosts: builder` and loops each machine's `build_variants`
(the current entry is the `build_variant` var); the role slices below run once
per variant and are individually selectable with `--tags`
(`preflight|modules|setup|packages|overlay|build`).

## Pipeline

1. **preflight** — asserts `imagebuilder_image` (the variant's) is set, the Docker
   CLI/daemon are reachable on the build host, and the `docker` Python SDK is
   importable by its interpreter.
2. **modules** — resolves the active module set from the default +
   `modules_adjust` / `modules_override`; fails on unknown names.
3. **setup** — pulls the image if needed and derives everything from the image's
   environment (see below).
4. **packages** — collects packages from the active modules (`base` is
   version-aware), appends `extra_packages`, deduplicates, and fails on
   add/remove conflicts.
5. **overlay** — renders the active modules' uci-defaults (see below).
6. **build** — runs the container, then locates and (optionally) fetches artifacts.
7. **fetch** (part of build) — when `fetch_artifacts` is true, pulls the
   artifacts to the control node.

## ImageBuilder internals (setup)

The role reads `VERSION_PATH` and `TARGET` from the image's `Config.Env` (an
official `openwrt/imagebuilder` tag always exposes them) and derives:

- the release path (`snapshots` for SNAPSHOT images, else the release path),
- the target and version,
- the package-manager switch (APK for non-numeric/SNAPSHOT or version ≥ 24.10,
  else opkg), which selects the matching LuCI translation package,
- the container name `openwrt-bw-<target>-<version>-<machine>-<variant>`.

`force_pull` forces a fresh image pull.

## Container orchestration (build)

`community.docker.docker_container` runs the official image once per variant:

- mounts: the (host) output dir → `/builder/bin`, the rendered `build.sh`, and the
  rendered overlay files;
- env: `HOST_UID`/`HOST_GID` (from facts), `OPENWRT_PACKAGES`,
  `OPENWRT_PROFILE`, `OPENWRT_EXTRA_IMAGE_NAME`, `OPENWRT_DISABLED_SERVICES`,
  `OPENWRT_ROOTFS_PARTSIZE`;
- `ulimits: nofile:65536:65536` — a bounded `nofile` limit. The host tools use
  fakeroot, whose `faked` daemon closes every fd up to `RLIMIT_NOFILE` on startup;
  the daemon's near-infinite inherited limit turns that into a hang. Keep it
  bounded.
- `cleanup: true`, `detach: false`, `output_logs: true`; a non-zero exit status is
  asserted as a build failure.

In the container, `templates/build.sh.j2` sets `TMPDIR` to a workspace on disk
(avoiding tmpfs exhaustion), runs `setup.sh` (via the configured mirror first,
then the official source) when the ImageBuilder environment is missing, applies
the repository mirror when enabled, then calls `make info` and `make image`. On
exit it restores ownership of the artifacts to the invoking host user.

## Overlay / uci-defaults

Modules ship first-boot config as uci-defaults under the role:

- `files/overlay/<module>/...` — copied verbatim;
- `templates/overlay/<module>/...` — rendered as Jinja templates (Ansible's
  `template` module replaces the old build-time `$VARNAME` substitution).

The role selects the files of the active modules, asserts no two active modules
target the same path, and applies executable modes to the paths listed in
`roles/imagebuilder/vars/main.yml` (`overlay_executable`); every other
file is installed `0644`. Rendered output is assembled under the variant's work
directory and mounted into the container.

## Artifacts

| Path | Where |
|------|-------|
| `~/.cache/openwrt-builder/artifacts/<machine>-<variant>` | builder-side output (`output_dir`) |
| `<repo>/artifacts/<machine>-<variant>` | control-node copy (`artifacts_dir`), contents gitignored |

When `fetch_artifacts` is true (default), the artifacts are fetched with
the `targets/<target>/<subtarget>/` layout preserved (firmware images,
`profiles.json`, `sha256sums`, ...). Set it to `false` to keep them only on the
builder. Re-running with the same inputs converges on the same output.
