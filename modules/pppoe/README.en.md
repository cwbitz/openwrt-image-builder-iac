# PPPoE WAN Configuration

## Overview

This module configures PPPoE on OpenWrt's WAN interface during the first boot, using environment variables for dial-up credentials.

## Features

- Set WAN protocol to PPPoE
- Configure PPPoE username and password
- Apply WAN settings automatically on boot

## Parameters

### Environment Variables
- `BW_PPPOE_USERNAME` — PPPoE login name provided by your ISP
- `BW_PPPOE_PASSWORD` — PPPoE password provided by your ISP

## Example

Set in `.env` or `.env.example`:
```bash
BW_PPPOE_USERNAME=your_username
BW_PPPOE_PASSWORD=your_password
```

Or pass when executing build scripts:
```bash
BW_PPPOE_USERNAME=your_username BW_PPPOE_PASSWORD=your_password ./run.sh ...
```

## How It Works

1. Check if both `BW_PPPOE_USERNAME` and `BW_PPPOE_PASSWORD` are provided in the environment variables.
2. If available, update the WAN settings via UCI:
   - Set `network.wan.proto` to `pppoe`
   - Set `network.wan.username` to `BW_PPPOE_USERNAME`
   - Set `network.wan.password` to `BW_PPPOE_PASSWORD`
3. Commit the changes.

## Files

- `.env.example` — example environment variables
- `files/etc/uci-defaults/89-pppoe` — PPPoE UCI configuration script

## Use Cases

- DSL and fiber connections using PPPoE
- ISP environments requiring username/password authentication
- Routers deployed in consumer or business networks directly connected to modems

## Notes

- Ensure the provided credentials are valid
- PPPoE may require provider-specific settings (such as VLAN IDs, which are not configured by this module by default)
- The configuration is applied on first boot only
