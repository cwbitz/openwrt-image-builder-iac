<div align="center">

# OpenWrt Builder Wrapper

English | [简体中文](README.md)

A modular firmware build wrapper for official OpenWrt ImageBuilder

CLI driven, Docker powered, and easy to extend with modules

[![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](LICENSE)
</div>

---

## Features at a glance

- **Ready to use**: Build custom firmware with official OpenWrt ImageBuilder
- **Modular**: Bundled modules plus support for `custom_modules`
- **CLI driven**: `run.sh`, supporting Linux and macOS
- **Containerized**: Docker isolates the build environment
- **Reusable configs**: Centralized environment variables and reusable presets

---

## Quick Start

### Linux / macOS

```bash
# Help
./run.sh --help

# Example: official OpenWrt ImageBuilder
./run.sh \
  --image=openwrt/imagebuilder:generic-arm64 \
  --profile=generic \
  --force-pull --force-recreate --use-mirror
```

### Common options

```bash
# Docker container and pull policies
-i | --image=...                  Specify the openwrt/imagebuilder Docker image (required)
-P | --force-pull                 Pull the image before building
-R | --force-recreate             Remove the existing container before building
-I | --info                       Query basic image and profile information

# Target profile config
-p | --profile=...                Specify the build profile (defaults to target's first profile if omitted)

# Module and package control configurations
-O | --override-modules=...       Specify a complete list of modules to build, bypassing defaults (e.g. "base lan prefer-ipv6 extras")
-a | --adjust-modules=...         Specify adjustments to the default module set (e.g. "statistics -extras")
-e | --extra-packages=...         Specify an explicit PACKAGES list for imagebuilder
-d | --disabled-services=...      Specify DISABLED_SERVICES for imagebuilder

# Target image customization configurations
-E | --extra-image-name=...       Specify a custom string to append to the output image filename
-r | --rootfs-partsize=...        Specify the root partition size in MB (defaults to target's default if omitted)

# Output, local custom modules, and mirror network configurations
-o | --output-dir=...             Specify the output directory for build artifacts (default: ./artifacts)
-c | --custom-modules-path=...    Specify the path to custom modules directory (default: ./custom_modules)
-u | --use-mirror                 Enable mirror usage (defaults to mirrors.tuna.tsinghua.edu.cn if -m / --mirror is not specified)
-m | --mirror=...                 Specify a custom mirror host, e.g. mirrors.ustc.edu.cn (do not include http:// or https://)
```

### Environment Variable Configuration

Module environment variables (such as `BW_MAIN_LAN_IP`, `BW_ROOT_PASSWORD`, `BW_PPPOE_USERNAME`, etc.) can be configured in two ways:

1. **Submodule Directory `.env` File**: Create a `.env` file directly under the module's subdirectory (refer to the `.env.example` template in each module).
2. **Command Line Environment Variables**: Pass them directly when executing the `run.sh` script, for example:
   ```bash
   BW_MAIN_LAN_IP='192.168.2.1' BW_ROOT_PASSWORD='secret' ./run.sh --image=...
   ```

> ⚠️ **Wrap command-line values in single quotes**: single quotes pass the value through **verbatim**; **double quotes let your shell expand it first** — e.g. in `BW_ROOT_PASSWORD="pa$$w@rd"` the `$$` becomes the shell's PID (turning into `pa<PID>w@rd`), so the password baked into the firmware differs from what you intended. **Any value containing `$`, `\`, backticks, double quotes or spaces MUST be single-quoted** (single quotes are safe for every other value too).

```bash
# ✅ Correct: single quotes pass the value through verbatim
BW_ROOT_PASSWORD='pa$$w@rd' BW_BYPASS_LAN_IP='192.168.2.3/24' ./run.sh ...

# ❌ Wrong: double quotes let the shell expand $, command substitutions and backslashes
BW_ROOT_PASSWORD="pa$$w@rd" ./run.sh ...
```

> In a `.env` file no quotes are needed (the script reads values as plain text), which is equally safe.

#### Precedence Rules

When the same configuration option or control variable is defined in multiple places, the precedence (from highest to lowest) is resolved as follows:
1. **CLI command-line options**: e.g., `--profile`, `--extra-packages`, `--force-pull`. Command line arguments always have the highest priority and override any other values.
2. **Host environment variables / Inline assignments**: e.g., `export BW_MAIN_LAN_IP=...` on the host, or passing variables directly inline `BW_MAIN_LAN_IP=... ./run.sh ...` (applies to all `BW_` prefixes and custom module-level environment variables).
3. **Module-specific environment files**: i.e., configurations declared inside `modules/<name>/.env` files.
4. **Global environment configuration**: i.e., configurations declared inside the root `.env` file.

> ⚠️ **Note**: A module's `.env.example` file is **for variable discovery only** (it tells the build script which variable NAMES the module supports). The script **never reads values from it**, so it is not part of the precedence chain above. See [Custom Module Development Guide](#custom-module-development-guide).

### Core Control Environment Variables

```bash
# Adjust default module set (base system root-password pppoe lan disable-ipv6 extras), e.g. -extras removes extras
BW_ADJUST_MODULES="statistics -extras"

# Completely override the default module set
BW_OVERRIDE_MODULES="base lan pppoe extras"

# Explicitly override/append packages passed to ImageBuilder (use - prefix to remove default packages)
BW_EXTRA_PACKAGES="luci-app-openclash -dnsmasq"

# Customize build image parameters
BW_EXTRA_IMAGE_NAME="custom"
BW_DISABLED_SERVICES="dnsmasq"
BW_ROOTFS_PARTSIZE="256"
```

Default output directory is `./artifacts`; override with `--output-dir`.

The build artifacts are laid out under `artifacts/targets/<target>/<subtarget>/`, containing the generated firmware images (e.g. `*-sysupgrade.bin`, `*-factory.bin`), `profiles.json`, `sha256sums`, etc.

---

## Module System

A reference table of all modules and the environment variables they support (for use when writing your `./run.sh` command). ✔ = enabled by default, ✘ = disabled by default (enable it via the module control options):

| Module | Enabled by default | Description | Supported environment variables (default) |
|--------|:---:|-------------|-------------------------------------------|
| `ap` | ✘ | Configures a wireless access point (AP): points the LAN gateway/DNS to the main router, optional DHCP disable. | `BW_AP_LAN_IP` (CIDR notation, e.g. `192.168.2.3/24`), `BW_AP_GATEWAY`, `BW_AP_DNS`, `BW_AP_DISABLE_DHCP` |
| `base` | ✔ | Provides the essential OpenWrt packages (LuCI Web UI, `-dnsmasq`/`dnsmasq-full`, `-wpad-basic-mbedtls`/`wpad-mbedtls`, Chinese language packs, etc.) and adapts the package list to the OpenWrt version. | none |
| `bypass-router` | ✘ | Configures the device as a bypass router: points the LAN gateway/DNS to the main router, optional LAN DHCP disable. | `BW_BYPASS_LAN_IP` (CIDR notation, e.g. `192.168.2.2/24`), `BW_BYPASS_GATEWAY`, `BW_BYPASS_DNS`, `BW_BYPASS_DISABLE_DHCP` |
| `disable-ipv6` | ✔ | Disables IPv6, RA (Router Advertisement), and DHCPv6 on LAN/WAN interfaces. | none |
| `extras` | ✔ | Installs common network diagnostics and system management tools (tcpdump, curl, vim-full, conntrack, etc.). | none |
| `main-router` | ✔ | Sets the LAN interface IP address for the main router. | `BW_MAIN_LAN_IP` (CIDR notation, e.g. `192.168.2.1/24`) |
| `pppoe` | ✔ | Configures the WAN PPPoE dial-up username/password on first boot. | `BW_PPPOE_USERNAME`, `BW_PPPOE_PASSWORD` (must both be set; empty by default) |
| `prefer-ipv6` | ✘ | Optimizes IPv6 priority and prefer-IPv6 configurations. | none |
| `python` | ✘ | Adds a lightweight Python 3 runtime (`python3-light`). | none |
| `root-password` | ✔ | Sets the root login password, with support for random generation. | `BW_ROOT_PASSWORD` (empty by default; values with `$` are best put in the module .env) |
| `ssh-permission` | ✘ | Fixes/converges the SSH `authorized_keys` file permissions (600). | none |
| `statistics` | ✘ | Enables collectd system performance/temperature monitoring and LuCI statistics graphing. | none |
| `system` | ✔ | Configures basic system settings: timezone (`Asia/Shanghai` / `CST-8`) and log levels. | none |

Default enabled modules: `base disable-ipv6 extras main-router pppoe root-password system`

- Add or remove modules on top of the default set with `-a | --adjust-modules` (e.g. `statistics -extras`).
- Specify an entirely custom module list (ignoring the default set) with `-O | --override-modules` (e.g. `base main-router pppoe extras`).
- Modules marked ✘ above (`ap`, `bypass-router`, `prefer-ipv6`, `python`, `ssh-permission`, `statistics`) can be enabled through either of these two options.

> For how to supply these variables and their precedence, see [Environment Variable Configuration](#environment-variable-configuration) above.

Module locations:

- `modules/`: built-in modules
- `custom_modules/`: custom modules

For details on the project and module file layout, see [Development & Build](#development--build) below.

Advanced features:

- Env var configuration: module-specific `.env` files or direct CLI assignments (`.env.example` only declares variable NAMES, never values)
- Variable substitution: files under `files/etc/uci-defaults` support `$VARNAME`
- Conflict protection: build fails if multiple modules produce the same target path

---

## Notes

- Only official OpenWrt ImageBuilder images are supported
- Built with a CLI-first workflow

---

## FAQ

**General:**
- Slow build or limited bandwidth? Enable `--use-mirror` or set `--mirror=mirrors.ustc.edu.cn`
- Build failed after enabling mirror sources? If the designated local mirror source (e.g. Tsinghua or USTC) is out of sync with official packages for a newly released version, package manager errors or build failures might occur. In such cases, it is recommended to **disable the mirror option** (omit the `-u | --use-mirror` flag) to fetch from official repositories directly, or wait until the local mirrors complete synchronization.
- Docker not installed? Install Docker Desktop (macOS) or Docker Engine (Linux)
- Where are outputs? Default is `./artifacts`, firmware under `artifacts/targets/<target>/<subtarget>/` (change with `--output-dir`)
- Docker not found? Ensure Docker Desktop is installed and running; try restarting the terminal
- Non-ASCII path issues? Prefer checking out the repo into an ASCII-only path

**Linux specific:**
- AppImage won’t start? `sudo apt install fuse`
- No Docker permission? Add your user to the docker group: `sudo usermod -aG docker $USER`, then re-login
- .deb install failed? `sudo apt-get install -f`

---

## Development & Build

Project and module layout:

```
.
├─ build.sh             # Actual build script inside container
├─ run.sh               # Build script
├─ .env                 # Optional: system-wide environment file (see .env.example)
├─ .env.example         # System-wide environment template with usage instructions
├─ artifacts/           # Build artifacts output directory (default; change with --output-dir)
├─ modules/             # Built-in module library
│  └─ [module-name]/    # Module structure layout
│     ├─ packages       # Dependency packages or executable script
│     ├─ files/         # Files to include in the firmware
│     ├─ post-script.sh # Optional post-processing shell script
│     ├─ .env           # Optional module-specific environment file (see .env.example)
│     ├─ .env.example   # Optional: declares the variable NAMES the module supports (discovery only; values never read)
│     └─ README.md      # Optional module description
├─ custom_modules/      # Custom modules directory
└─ LICENSE              # MIT license
```

Required:

- Docker

## Custom Module Development Guide

Custom modules live in `custom_modules/` (or any directory chosen with `-c | --custom-modules-path`). Each module is a sub-directory:

```
custom_modules/my-module/
├─ packages              # Package list (or an executable script whose stdout prints the package list)
├─ files/                # File tree to merge into the firmware (all merged into the FILES dir)
│  └─ etc/uci-defaults/  # Scripts executed automatically on first boot (use 2-digit numeric prefixes to order)
├─ post-script.sh        # Optional: post-processing script run inside the build container
├─ .env                  # Optional: module-specific variable values (ranked right below command line)
└─ .env.example          # Strongly recommended: declare the variable NAMES the module supports (for discovery)
```

### Basic requirements

- Module names should be lowercase with hyphens (e.g. `my-module`).
- **Do not reuse a name from the built-in `modules/` directory**: a name present in both places is processed twice, causing duplicated packages and file-path conflicts that fail the build.
- Package conflict protection: the same package cannot appear both as `+pkg` and `-pkg` in the final package list; the build aborts if it does.

### `packages` file

- A whitespace-separated package list, or
- an **executable script** whose `stdout` is treated as the package list (it is sourced first; on failure the file is read as plain text).
- A `-pkg` prefix removes that package from the default set; positive/negative conflicts in the final list are detected by `check_package_conflicts` and abort the build.

### Variable substitution in `files/` (`$VARNAME`)

`$VARNAME` placeholders inside **text files** under `files/` are replaced with actual values during the build:

- **Variable discovery**: only variable names declared in the module's `.env` or `.env.example` are substituted; an undeclared `$FOO` stays untouched. Therefore:
  - To use a variable in your scripts you MUST list its name in `.env.example` (otherwise the name is never discovered);
  - keep placeholders you do NOT want replaced out of `.env.example`.
- **Empty values**: if a variable has no value anywhere (command line, module `.env`, global `.env`), it is replaced by an **empty string** — the `$VARNAME` placeholder is NOT preserved:
  ```sh
  # ✅ Recommended: safely skip when empty
  if [ -n "$MY_VALUE" ]; then
      # only run when a value was provided
      ...
  fi
  # ❌ Not recommended: writes an empty config line when empty
  uci set network.lan.ipaddr='$MY_VALUE'
  ```
- **Escaping rules**:
  - **Shell scripts** (ending in `.sh` or located under `etc/uci-defaults/`): `\`, `$`, backticks and double quotes inside values are auto-escaped so the firmware runtime sees the literal value (e.g. a password `pa$$w@rd` is not wrongly expanded to `pa`).
  - **Plain-text files**: no escaping is applied; values are used directly in awk string concatenation, guaranteeing literal transmission.
- **File type detection**: only files detected as text (`is_text_file`) are processed (e.g. `.conf`, `.json`, scripts, etc.); binary files are skipped outright.

### `post-script.sh`

- Sourced inside the build container before files are merged; can tweak the build environment or stage files.
- It runs inside the container, where `TMPDIR` is already set to the build workspace (`/builder/tmp`), so large temporary operations need not worry about tmpfs overflow.

### Variable precedence (important)

```
command-line env vars / inline assignments  >  module .env  >  global .env
```

`.env.example` is **not** in this chain — it only declares names, never values. See [Environment Variable Configuration](#environment-variable-configuration) above.

### Checklist for a new module

1. Create `custom_modules/<my-module>/` with `packages` and `files/` (plus `post-script.sh` when needed).
2. Create `.env.example` and **list every variable name** referenced in `files/`.
3. Guard every uci-defaults script that uses a variable with `if [ -n "$VARNAME" ]`.
4. Enable the module with `-a | --adjust-modules` or `-O | --override-modules`, rebuild, and verify via the `.manifest` / unpacked `rootfs`.

## License

This project is licensed under MIT. See `LICENSE`
