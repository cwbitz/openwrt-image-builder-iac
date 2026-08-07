# System Statistics

## Overview

This module adds system monitoring to OpenWrt, providing performance data collection and LuCI visualization.

## Features

- Performance data collection
- Temperature monitoring
- Web UI graphs and charts
- Hardware IRQ statistics
- Sensor metrics

## Packages

### UI components
- `luci-app-temp-status` — temperature status interface
- `luci-app-statistics` — statistics dashboard

### Data collectors
- `collectd-mod-irq` — IRQ statistics
- `collectd-mod-sensors` — sensor reporting

## Capabilities

### Temperature
- Real-time temperature display
- Historical sensor logs
- Threshold alerts
- Support for multiple sensors

### System Stats
- CPU usage tracking
- Memory usage monitoring
- Network traffic stats
- Storage and disk monitoring
- System load overview

### Hardware Monitoring
- IRQ activity
- Sensor metrics
- Voltage and current readings
- Fan speed monitoring

## Web UI

Accessible through LuCI:
- System → Administration → Statistics
- Status → Temperature
- Real-time charts
- Historical queries

## Files

- `packages` — package list
- `files/etc/uci-defaults/99-statistics` — initial statistics configuration script

## Use Cases

- Performance tuning
- Hardware health monitoring
- Fault diagnosis
- Resource accounting
- Device maintenance

## Notes

- Monitoring collectors consume system resources
- Requires supported hardware sensors
- Historical data consumes storage
- Some features depend on platform support
