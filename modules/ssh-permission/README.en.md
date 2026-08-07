# SSH Permission Configuration

## Overview

This module corrects the permissions of the SSH authorized keys file to ensure public key authentication works properly and securely.

## Features

- Fix authorized keys file permissions
- Ensure SSH public key authentication works reliably
- Improve system security by enforcing strict file permissions
- Satisfy Dropbear security and permission requirements

## How It Works

### Permissions
- Check whether `/etc/dropbear/authorized_keys` exists
- Set the file mode to `600` (rw-------)
- Ensure the SSH service can read authorized keys while blocking access to other local accounts

### Why It Matters
- `600` grants only the owner read/write access, keeping group and others without any permissions
- Helps avoid Dropbear ignoring key files or authentication failures caused by overly loose permissions
- Matches Dropbear/SSH security best practices for authorized keys

## Technical Notes

### Dropbear SSH
- OpenWrt uses Dropbear by default
- Authorized keys path: `/etc/dropbear/authorized_keys`
- Each public key should appear on its own line

### Permission Detail
- `600` (rw-------)
  - Owner: read/write
  - Group: no access
  - Others: no access

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
