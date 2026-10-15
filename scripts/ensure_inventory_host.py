#!/usr/bin/env python3
"""Ensure a host exists under <group>.hosts in an Ansible inventory.

Comment-preserving, line-based edit: the file is modified in place and existing
lines, comments and formatting are never re-serialised. Idempotent: if a host
entry for <host> already exists under the group the file is left untouched.

The new entry is inserted directly under the group's ``hosts:`` key, using the
same indentation as the existing entries (or ``hosts:`` + 2 spaces when the group
has none yet).

Usage:
    ensure_inventory_host.py <inventory.yml> <host> [--group remnawave_nodes]

Uses only the standard library, so the control node's (possibly minimal)
toolchain ``python3`` is enough.
"""
from __future__ import annotations

import argparse
import re
import sys

DEFAULT_GROUP = "remnawave_nodes"
DEFAULT_ANSIBLE_HOST = "{{ vault_host.ip }}"


def _indent(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def _is_noise(line: str) -> bool:
    stripped = line.strip()
    return not stripped or stripped.startswith("#")


def _find_group(lines: list[str], group: str) -> int | None:
    """Return the index of the ``<group>:`` mapping key line, or None."""
    pattern = re.compile(r"^[ ]*" + re.escape(group) + r"\s*:\s*(?:#.*)?$")
    for index, line in enumerate(lines):
        if pattern.fullmatch(line.rstrip("\n")):
            return index
    return None


def _find_hosts(lines: list[str], group_index: int, group_indent: int) -> int | None:
    """Return the index of the ``hosts:`` key that belongs to the group block."""
    for index in range(group_index + 1, len(lines)):
        line = lines[index]
        if _is_noise(line):
            continue
        if _indent(line) <= group_indent:
            break
        if re.fullmatch(r"[ ]*hosts\s*:\s*(?:#.*)?", line.rstrip("\n")):
            return index
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inventory", help="Path to the inventory YAML file")
    parser.add_argument("host", help="Inventory host name to ensure")
    parser.add_argument("--group", default=DEFAULT_GROUP, help="Inventory group (default: %(default)s)")
    parser.add_argument(
        "--ansible-host",
        default=DEFAULT_ANSIBLE_HOST,
        help="ansible_host value for a newly added host; empty omits the key (default: %(default)s)",
    )
    parser.add_argument(
        "--comment",
        default="",
        help="inline comment appended to the ansible_host line",
    )
    args = parser.parse_args()

    try:
        with open(args.inventory, encoding="utf-8") as handle:
            lines = handle.readlines()
    except FileNotFoundError:
        print(f"ERROR: {args.inventory} does not exist", file=sys.stderr)
        return 1

    group_index = _find_group(lines, args.group)
    if group_index is None:
        print(f"ERROR: group '{args.group}' not found in {args.inventory}", file=sys.stderr)
        return 1
    group_indent = _indent(lines[group_index])

    hosts_index = _find_hosts(lines, group_index, group_indent)
    if hosts_index is None:
        print(
            f"ERROR: no 'hosts:' mapping under '{args.group}' in {args.inventory}",
            file=sys.stderr,
        )
        return 1
    hosts_indent = _indent(lines[hosts_index])

    # Walk the hosts block: detect an existing entry and learn its indentation.
    entry_indent: int | None = None
    dup = re.compile(r"^[ ]*" + re.escape(args.host) + r"\s*:\s*(?:#.*)?$")
    for index in range(hosts_index + 1, len(lines)):
        line = lines[index]
        if _is_noise(line):
            continue
        indent = _indent(line)
        if indent <= hosts_indent:
            break
        if dup.fullmatch(line.rstrip("\n")):
            print(f"{args.host} already present in {args.inventory} ({args.group})")
            return 0
        if entry_indent is None:
            entry_indent = indent

    if entry_indent is None:
        entry_indent = hosts_indent + 2

    inserted = [" " * entry_indent + f"{args.host}:\n"]
    if args.ansible_host:
        line = " " * (entry_indent + 2) + f'ansible_host: "{args.ansible_host}"'
        if args.comment:
            line += f"  # {args.comment}"
        inserted.append(line + "\n")
    lines[hosts_index + 1 : hosts_index + 1] = inserted

    with open(args.inventory, "w", encoding="utf-8") as handle:
        handle.writelines(lines)
    print(f"added {args.host} to {args.inventory} ({args.group})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
