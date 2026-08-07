# Python Support

## Overview

This module adds Python 3 support to OpenWrt by installing a lightweight runtime.

## Features

- Install a minimal Python 3 runtime
- Provide basic Python scripting support
- Run Python scripts on the router
- Serve as a foundation for Python-based applications

## Package

- `python3-light` — lightweight Python 3 interpreter

## Characteristics

### Lightweight
- Minimal runtime footprint
- Reduced storage usage
- Retains core Python functionality
- Suitable for embedded environments

### Compatibility
- Supports standard Python 3 syntax
- Compatible with common base libraries
- Extensible with additional packages
- Useful for automation scripts

## Files

- `packages` — package list

## Use Cases

When Python scripting is needed:
- Automation
- System administration
- Network monitoring
- Data processing
- IoT control
- Extending firmware features

## Notes

- The lightweight build excludes some standard library modules
- Complex applications may require extra dependencies
- Pick packages based on actual requirements
