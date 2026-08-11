# System Statistics

## Overview

This module adds system monitoring to OpenWrt, providing performance data collection and LuCI visualization.

## Features

- Performance data collection
- Temperature monitoring and display
- Web UI graphs and charts
- Hardware IRQ statistics
- Sensor metrics

## Packages

### UI Components
- Temperature status shown on the LuCI "Status → Temperature" page (provided by the built-in `luci-mod-status`, shipped with the base `luci` package — no extra package required); sensor metrics are collected by `collectd-mod-sensors`
- `luci-app-statistics` — Web interface for configuring and viewing collectd graphs

### Data Collectors
- `collectd-mod-irq` — IRQ statistics module
- `collectd-mod-sensors` — sensor metrics reporting module

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
- IRQ activity frequency
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
- `files/etc/uci-defaults/99-statistics` — statistics UCI configuration script that enables sensors, irq, interface (configured for `eth1` by default), and rrdtool charts spanning up to a year

## Use Cases

- Performance tuning
- Hardware health monitoring
- Fault diagnosis and analysis
- Resource accounting
- Device maintenance and management

## Notes

- Monitoring collectors consume some system resources (CPU and RAM)
- Requires supported hardware sensors to display temperature and sensor stats
- Historical data is stored via RRDtool and consumes storage space
- Default interface monitoring is set for `eth1`; update the config script if your layout differs
