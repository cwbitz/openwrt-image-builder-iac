# Root Password Configuration

## Overview

This module sets the root password for OpenWrt, providing secure administrator access control.

## Features

- Configure the root login password
- Support random password generation
- Strengthen system security
- Prevent unauthorized access

## Environment Variables

### Password
- `BW_ROOT_PASSWORD` — root password
  - `random`: generate a secure random password (depending on external build script implementation)
  - any other value: use the provided password

## Example

Set in `.env` or `.env.example`:
```bash
BW_ROOT_PASSWORD=your_secure_password
```

Or pass when executing build scripts:
```bash
BW_ROOT_PASSWORD=your_secure_password ./run.sh ...
```

## Security Advice

### Password policy
- Minimum 8 characters
- Mix uppercase, lowercase, digits, and symbols
- Avoid common or predictable passwords
- Rotate passwords periodically

### Best practices
- Prefer SSH key authentication
- Disable password login after keys are configured
- Enable firewall protection
- Restrict SSH access by source IP when possible

## Files

- `.env.example` — environment variable example
- `files/etc/uci-defaults/92-system` — password configuration script that runs `passwd` on first boot

## Use Cases

For secure system access:
- Production deployments
- Remote administration
- Multi-user environments
- Compliance requirements

## Notes

- Keep the password secure
- Use SSH keys when possible
- Avoid transmitting passwords over insecure networks
- Review security logs regularly
