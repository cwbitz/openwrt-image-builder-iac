# PPPoE

## Overview

This module configures PPPoE on OpenWrt during the first boot, using environment variables for credentials.

## Features

- Set WAN protocol to PPPoE
- Configure PPPoE username and password
- Apply WAN settings automatically on boot

## Environment Variables

- `PPPOE_USERNAME` — PPPoE login name
- `PPPOE_PASSWORD` — PPPoE password

## Files

- `.env.example` — example environment variables
- `files/etc/uci-defaults/89-pppoe` — PPPoE UCI configuration script

## Use Cases

- DSL and fiber connections using PPPoE
- ISP environments requiring username/password authentication
- Routers deployed in consumer or business networks

## Notes

- Ensure the provided credentials are valid
- PPPoE may require provider-specific settings
- The configuration is applied on first boot only
