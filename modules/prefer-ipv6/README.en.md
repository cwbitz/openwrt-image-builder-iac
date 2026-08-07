# Prefer IPv6 Settings

## Overview

This module configures OpenWrt to prefer IPv6 networking for LAN clients by adjusting DHCP and Router Advertisement settings.

## Features

- Enable IPv6 Router Advertisement on LAN
- Configure DHCP and RA lifetime behavior
- Prefer IPv6 routing for downstream clients
- Apply recommended IPv6 LAN settings on first boot

## Files

- `files/etc/uci-defaults/99-ipv6` — IPv6 configuration script

## Use Cases

- IPv6-enabled networks
- WAN links providing prefix delegation
- Environments where IPv6 should be preferred over IPv4

## Notes

- Requires upstream IPv6 support
- Applied on first boot
- Best used when WAN provides IPv6 prefixes
