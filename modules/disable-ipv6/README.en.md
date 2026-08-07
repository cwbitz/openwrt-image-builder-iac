# Disable IPv6

## Overview

This module disables IPv6 on OpenWrt as thoroughly as possible, making it suitable for environments that use only IPv4 or need to avoid IPv6 compatibility issues.

## What It Does

- Disables IPv6 on LAN and WAN interfaces
- Turns off Router Advertisement (RA) and DHCPv6 services
- Applies kernel-level IPv6 disablement via sysctl settings

## Use Cases

- IPv4-only networks
- Environments avoiding IPv6 compatibility problems
- Scenarios requiring stricter network control

## Configuration Files

- `files/etc/sysctl.d/99-disable-ipv6.conf` — kernel sysctl configuration to disable IPv6 globally
- `files/etc/uci-defaults/99-disable-ipv6` — UCI configuration script to disable IPv6 on network interfaces and DHCP service

## Notes

- Enabling this module prevents IPv6 usage in most cases
- It may affect services or networks that depend on IPv6
- Do not enable this module if IPv6 is required
