# Base Packages

## Overview

This module provides a base OpenWrt package set, including the LuCI web interface, utilities, and essential system components.

## Features

- Install core OpenWrt components and tools
- Configure the LuCI web interface
- Include Simplified Chinese language support
- Adjust packages based on OpenWrt version

## Packages

### Core
- `zoneinfo-all` — time zone data
- `luci` — LuCI web interface
- `luci-compat` — compatibility layer for LuCI
- `luci-lib-ipkg` — package management library
- `dnsmasq-full` — full-featured DNS/DHCP server
- `openssl-util` — OpenSSL utility tools

### Chinese localization
- `luci-i18n-base-zh-cn` — LuCI base translation
- `luci-i18n-firewall-zh-cn` — firewall translation

### Version-specific
- OpenWrt 24.10 and later (including SNAPSHOT): `luci-i18n-package-manager-zh-cn`
- Older stable versions (before 24.10): `luci-i18n-opkg-zh-cn`

## Version Detection

Environment variables:
- `OPENWRT_VERSION` — OpenWrt version identifier
- `IS_SNAPSHOT_BUILD` — whether the build is a snapshot

## Files

- `packages` — package list generation script

## Usage

Use this module as the foundation for OpenWrt systems that require a full web management interface.
