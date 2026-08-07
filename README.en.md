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
-o | --output-dir=...             Specify the output directory for build artifacts (default: ./bin)
-c | --custom-modules-path=...    Specify the path to custom modules directory (default: ./custom_modules)
-u | --use-mirror                 Enable mirror usage (defaults to mirrors.tuna.tsinghua.edu.cn if -m / --mirror is not specified)
-m | --mirror=...                 Specify a custom mirror host, e.g. mirrors.ustc.edu.cn (do not include http:// or https://)
```

### Environment Variable Configuration

Module environment variables (such as `BW_LAN_IP`, `BW_ROOT_PASSWORD`, `BW_PPPOE_USERNAME`, etc.) can be configured in two ways:

1. **Submodule Directory `.env` File**: Create a `.env` file directly under the module's subdirectory (refer to the `.env.example` template in each module).
2. **Command Line Environment Variables**: Pass them directly when executing the `run.sh` script, for example:
   ```bash
   BW_LAN_IP=192.168.2.1 BW_ROOT_PASSWORD=secret ./run.sh --image=...
   ```

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

Default output directory is `./bin`; override with `--output-dir`.

---

## Module System

Default enabled module set:

`base system root-password pppoe lan disable-ipv6 extras`

All currently available built-in modules:

`base disable-ipv6 extras lan pppoe prefer-ipv6 python root-password ssh-permission statistics system`

Module locations:

- `modules/`: built-in modules
- `custom_modules/`: custom modules

For details on the project and module file layout, see [Development & Build](#development--build) below.

Module notes:

- `base`: Provides essential packages including the LuCI Web UI, system tools, and required system dependencies.
- `disable-ipv6`: Disables IPv6 on LAN/WAN interfaces, and stops IPv6 RA (Router Advertisement) and DHCPv6 services upon boot.
- `extras`: Installs common network diagnosis and system tools (e.g., tcpdump, curl) for advanced troubleshooting.
- `lan`: Sets up the LAN interface IP address, supporting customization via environment variables.
- `pppoe`: Automates PPPoE WAN dialing configurations (username and password) on first startup.
- `prefer-ipv6`: Optimizes IPv6 priority settings and prefer-IPv6 configurations.
- `python`: Installs a lightweight Python 3 environment and package support.
- `root-password`: Configures root user login credentials (supports custom or random passwords).
- `ssh-permission`: Fixes ownership and permissions of SSH authorized_keys files to ensure secure public-key login.
- `statistics`: Enables performance telemetry, system statistics tracking, temperature monitoring, and LuCI graphing interfaces.
- `system`: Configures basic system attributes, such as switching timezone to China timezone (CST) and adjusting system log levels.

Advanced features:

- Env var configuration: support module-specific `.env` files or direct CLI assignments
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
- Docker not installed? Install Docker Desktop (macOS) or Docker Engine (Linux)
- Where are outputs? Default is `./bin` (change with `--output-dir`)
- Docker not found? Ensure Docker Desktop is installed and running; try restarting the terminal
- Permission issues? Run Docker Desktop as Administrator
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
├─ modules/             # Built-in module library
│  └─ [module-name]/    # Module structure layout
│     ├─ packages       # Dependency packages or executable script
│     ├─ files/         # Files to include in the firmware
│     ├─ post-script.sh # Optional post-processing shell script
│     ├─ .env           # Optional module-specific environment file (see .env.example)
│     ├─ .env.example   # Optional environment template with usage instructions
│     └─ README.md      # Optional module description
├─ custom_modules/      # Custom modules directory
└─ LICENSE              # MIT license
```

Required:

- Docker

## License

This project is licensed under MIT. See `LICENSE`
