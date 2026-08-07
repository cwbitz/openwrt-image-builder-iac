# SSH Permission Configuration

## Overview

This module corrects the permissions of the SSH authorized keys file to ensure public key authentication works properly.

## Features

- Fix authorized keys file permissions
- Ensure SSH public key authentication works reliably
- Improve system security
- Satisfy Dropbear permission requirements

## How It Works

### Permissions
- Check whether `/etc/dropbear/authorized_keys` exists
- Set the file mode to `644` (rw-r--r--)
- Ensure the SSH service can read authorized keys

### Why It Matters
- `644` grants owner write access while keeping group and others read-only
- Helps avoid authentication failures caused by incorrect permissions
- Matches Dropbear/SSH expectations for authorized keys

## Technical Notes

### Dropbear SSH
- OpenWrt uses Dropbear by default
- Authorized keys path: `/etc/dropbear/authorized_keys`
- Each public key should appear on its own line

### Permission Detail
- `644` (rw-r--r--)
  - Owner: read/write
  - Group: read-only
  - Others: read-only

## Files

- `files/etc/uci-defaults/99-ssh` — SSH permission fix script

## Use Cases

For environments using SSH keys:
- Passwordless SSH login
- Automated deployments
- Secure remote administration
- CI/CD integration

## Notes

- Runs only if the authorized keys file exists
- Does not create missing files
- Applied on first boot
- Use with SSH public key authentication
