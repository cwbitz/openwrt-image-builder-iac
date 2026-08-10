# Access Point (AP) Configuration

## Overview

This module configures an OpenWrt device as a **wireless access point (AP)**: the device connects to the main router through the LAN port, points its gateway and DNS to the main router, and can optionally disable DHCP.

## Features

- Set the AP's own static LAN IP address
- Set the LAN gateway (`network.lan.gateway`, usually the main router's LAN IP)
- Set LAN DNS (`network.lan.dns`, usually the main router's LAN IP or public DNS; multiple values supported)
- Optionally disable the LAN DHCP server (`network.lan.ignore='1'`)

## Parameters

### Environment Variables
- `BW_AP_LAN_IP` — the AP's own static LAN IP (empty by default; left unchanged when empty)
- `BW_AP_GATEWAY` — LAN gateway, usually the main router's LAN IP (empty by default)
- `BW_AP_DNS` — LAN DNS servers, space-separated (empty by default)
- `BW_AP_DISABLE_DHCP` — set to `1` to disable the LAN DHCP server (empty by default)

## Example

Set in `.env` or the module's `.env` file:
```bash
BW_AP_LAN_IP=192.168.1.100
BW_AP_GATEWAY=192.168.1.1
BW_AP_DNS="192.168.1.1 223.5.5.5"
BW_AP_DISABLE_DHCP=1
```

Or pass when executing the build script:
```bash
BW_AP_GATEWAY=192.168.1.1 \
BW_AP_DNS="192.168.1.1 223.5.5.5" \
BW_AP_DISABLE_DHCP=1 \
./run.sh -i openwrt/imagebuilder:... -a ap ...
```

## Enabling the Module

This module is disabled by default. Add it with `-a | --adjust-modules`:
```bash
./run.sh -i openwrt/imagebuilder:... -a "ap" -p <profile> ...
```

## How It Works

1. `BW_AP_*` values are substituted into the script at build time
2. On first boot the script updates `network.lan` parameters (`ipaddr` / `gateway` / `dns`) via UCI
3. Optionally disables the LAN DHCP server (`network.lan.ignore='1'`)
4. Commits the configuration to make it effective

## Files

- `.env.example` — environment variable template (discovery only; values are never read from this file)
- `files/etc/uci-defaults/90-ap` — UCI configuration script

## Use Cases

- Turn an old router or new device into a pure wireless AP

## Notes

- The AP's LAN IP must be on the same subnet as the main router and must not conflict with other devices
- Both gateway and DNS usually point to the main router's LAN IP
- Make sure the main router is running DHCP if you disable it here
- Empty variables are skipped; see the [Custom Module Development Guide](../README.en.md#custom-module-development-guide) in the root README