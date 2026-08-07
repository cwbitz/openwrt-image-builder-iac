# LAN Configuration

## Overview

This module configures the LAN interface IP address on OpenWrt and supports custom subnet assignment.

## Features

- Custom LAN IP address configuration
- Configurable via environment variables
- Apply settings automatically on first boot
- Support for custom subnet deployment

## Parameters

### Environment
- `LAN_IP` — LAN interface IP address (default: `192.168.2.1`)

## Example

Set in `.env.example`:
```bash
LAN_IP=192.168.2.1
```

## How It Works

1. Read `LAN_IP` from the environment
2. Update the OpenWrt network configuration via UCI
3. Set `network.lan.ipaddr`
4. Commit the changes

## Files

- `.env.example` — example environment file
- `files/etc/uci-defaults/89-lan` — UCI configuration script

## Use Cases

When customizing the default LAN network:
- Avoid IP conflicts
- Match network design requirements
- Integrate into enterprise environments
- Support multiple routers or nested networks

## Notes

- Ensure the IP does not conflict with other devices
- Update DHCP pool settings if needed
- Use private IPv4 address space
