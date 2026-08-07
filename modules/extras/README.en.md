# Extras

## Overview

This module installs common network diagnostic and system management utilities on OpenWrt, providing useful tools for administration and troubleshooting.

## Features

- Network diagnostics and testing tools
- System administration utilities
- Text editing and processing tools
- Connection tracking and monitoring

## Included Tools

### Networking
- **bind-dig** — DNS query and diagnostic tool
  - Resolve domain names
  - Query DNS servers
  - Verify connectivity

- **wget** — Command-line downloader
  - Download files over HTTP/HTTPS
  - Support resumable downloads
  - Handle scripted downloads

- **curl** — Multi-protocol transfer utility
  - Work with HTTP/HTTPS/FTP and more
  - Test APIs
  - Transfer and debug data

### Network Diagnostics
- **nping** — Packet generation tool
  - Craft custom packets
  - Test latency
  - Check port reachability

- **tcpdump** — Packet capture utility
  - Capture live packets
  - Analyze traffic
  - Debug protocols

### System Utilities
- **vim-full** — Full-featured text editor
  - Syntax highlighting
  - Multiple editing modes
  - Supports plugins

- **diffutils** — File comparison utilities
  - Compare text files with `diff`
  - Compare binary files with `cmp`
  - Audit configuration changes

- **conntrack** — Connection tracking utility
  - Monitor connection states
  - Track NAT sessions
  - Manage firewall connection tracking

## Configuration Files

- `packages` — Package list

## Use Cases

### Network Diagnostics
- Connectivity testing
- DNS troubleshooting
- Performance analysis
- Protocol debugging

### System Administration
- Edit configuration files
- Create maintenance scripts
- Download and transfer files
- Analyze logs

### Troubleshooting
- Diagnose network problems
- Check service health
- Monitor performance
- Audit security issues

## Examples

```bash
# DNS lookup
dig google.com

# Download a file
wget https://example.com/file.tar.gz

# Port testing
nping -p 80 target.com

# Packet capture
tcpdump -i eth0 host 192.168.1.1

# Connection tracking
conntrack -L
```

## Notes

- This toolset consumes additional storage
- Install only the tools you need
- Some tools require root privileges
- Learn basic usage for best results
