# Bypass Router Configuration

## Overview

This module configures the OpenWrt system as a **Bypass Router** (also known as Side Router). The device connects to the main network via LAN, routing its gateway and DNS to the main router.

## Features

- Set the static IP address for the LAN interface of the bypass router.
- Set the LAN gateway (`network.lan.gateway`, pointing to the main router's LAN IP).
- Set the LAN DNS (`network.lan.dns`, pointing to the main router's LAN IP or public DNS servers).
- Optional: Disable the LAN interface DHCP service (`network.lan.ignore='1'`).

## Parameters

### Environment Variables
- `BW_BYPASS_LAN_IP` — Bypass router static LAN IP address (default: empty)
- `BW_BYPASS_GATEWAY` — LAN gateway, usually pointing to the main router (default: empty)
- `BW_BYPASS_DNS` — LAN DNS list, space-separated (default: empty)
- `BW_BYPASS_DISABLE_DHCP` — Set to `1` to ignore/disable LAN DHCP service (default: empty)
