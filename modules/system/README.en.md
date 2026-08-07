# System Configuration

## Overview

This module configures basic OpenWrt system settings, including the default time zone and system log levels.

## Features

- Set the system time zone to China Standard Time
- Configure system log verbosity
- Apply settings automatically on first boot

## System Settings

### Time Zone
- **Time zone**: `Asia/Shanghai`
- **Offset**: `CST-8` (UTC+8)
- Automatically handles daylight saving time

### Log Settings
- **Cron log level**: `8` (debug)
- **Console log level**: `7` (info)

## Configuration Details

### Time Zone
```bash
set system.@system[0].zonename='Asia/Shanghai'
set system.@system[0].timezone='CST-8'
```

### Log Levels
```bash
set system.@system[0].cronloglevel='8'
set system.@system[0].conloglevel='7'
```

## Log Level Guide

- **Level 8**: Debug-level output for detailed diagnostics
- **Level 7**: Informational output for normal system events
- Higher values produce more verbose logging

## Configuration File

- `files/etc/uci-defaults/91-system` — system UCI configuration script

## Effects

- Displays system time in Beijing time
- Improves logging detail for troubleshooting

## Use Cases

- Home router configurations
- Enterprise network appliances
- Lab and development environments
- Localized system customization

## Notes

- Settings are applied on first boot
- Configuration persists after reboot
- Time zone can be changed later if needed
- Higher log levels increase log output
