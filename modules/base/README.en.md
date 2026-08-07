# Base Packages

## Overview

This module provides a base OpenWrt package set, including the LuCI web interface, system utilities, and essential system components.

## Features

- Install core OpenWrt components and utilities (SFTP, Rsync, etc.)
- Configure the LuCI web interface with full WPA/WPA2/WPA3 wireless encryption support (`wpad-mbedtls`)
- Replace the lightweight DNS/DHCP server with full-featured `dnsmasq-full`
- Include Simplified Chinese language support
- Dynamically adjust packages based on OpenWrt target version

## Packages

### Core
- `luci` — LuCI web interface
- `-dnsmasq` / `dnsmasq-full` — removes minimal dnsmasq and installs full-featured DNS/DHCP server
- `-wpad-basic-mbedtls` / `wpad-mbedtls` — removes basic wpad and installs full-featured wireless encryption component
- `openssl-util` — OpenSSL utility tools
- `openssh-sftp-server` — SSH SFTP server support
- `rsync` — Remote data synchronization utility

### Chinese localization
- `luci-i18n-base-zh-cn` — LuCI base translation
- `luci-i18n-firewall-zh-cn` — firewall translation

### Version-specific
- OpenWrt 24.10 and later (including SNAPSHOT): `luci-i18n-package-manager-zh-cn`
- Older stable versions (before 24.10): `luci-i18n-opkg-zh-cn`

## Version Detection

The module automatically inspects the target version via the `VERSION_PATH` environment variable and includes the appropriate package manager translation package.

## Files

- `packages` — package list generation script

## Usage

Use this module as the foundation for OpenWrt systems that require a full web management interface and standard system tools.
