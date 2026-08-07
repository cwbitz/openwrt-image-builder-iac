# Prefer IPv6 Settings

## Overview

This module configures OpenWrt to prefer IPv6 networking for LAN clients by adjusting DHCP and Router Advertisement settings, and resolves a common timing issue during boot.

## Features

- Enable IPv6 Router Advertisement (RA) on LAN
- Configure DHCP and RA lifetime behavior
- Prefer IPv6 routing for downstream clients
- Apply recommended IPv6 LAN settings on first boot
- Prevent IPv6 hang issues caused by the LAN starting up faster than the WAN interface receives its Prefix Delegation (PD)

## Files

- `files/etc/uci-defaults/99-ipv6` — IPv6 initialization and UCI configuration script
- `files/etc/hotplug.d/iface/99-odhcpd` — Hotplug script that reloads the LAN interface once WAN obtains a valid IPv6 address, ensuring odhcpd broadcasts correctly

## How It Works

1. **UCI Initialization (`99-ipv6`)**:
   - Deletes the default ULA prefix (`ula_prefix`)
   - Reinitializes the LAN DHCP config section
   - Configures the LAN interface as a Router Advertisement (RA) server (`ra='server'`) with `ra_useleasetime` enabled
   - Sets the preferred lifetime to 8 hours (`preferred_lifetime='8h'`)

2. **Hotplug Trigger (`99-odhcpd`)**:
   - Listens to WAN interface state changes (`ifup` and `ifupdate`)
   - If a valid IPv6 address is detected on WAN, it locks the execution, stops miniupnpd (if installed) to avoid state conflicts, runs `ifup lan` to refresh the odhcpd assignment, and restarts miniupnpd

## Use Cases

- IPv6-enabled networks
- WAN links providing prefix delegation (PD)
- Environments where IPv6 should be preferred over IPv4

## Notes

- Requires upstream IPv6 support from your ISP
- Applied on first boot, but the hotplug script operates continuously
- Best used when the WAN link provides delegatable IPv6 prefixes
