#!/usr/bin/env python3
"""Ensure a host exists under <group>.hosts in an Ansible inventory.

Comment-preserving, line-based edit: the file is modified in place and existing
lines, comments and formatting are never re-serialised. Idempotent: if a host
entry for <host> already exists under the group the file is left untouched.

The new entry is inserted directly under the group's ``hosts:`` key, using the
same indentation as the existing entries (or ``hosts:`` + 2 spaces when the group
has none yet). The entry carries an ``ansible_host`` (``CHANGE_ME_HOST_IP`` by
default; pass ``--ansible-host`` with the machine's real address).

Usage:
    ensure_inventory_host.py <inventory.yml> <host> [--group builders]

Uses only the standard library, so the control node's (possibly minimal)
toolchain ``python3`` is enough.
"""
from __future__ import annotations

import argparse
import re
import sys

DEFAULT_GROUP = "builders"
DEFAULT_ANSIBLE_HOST = "CHANGE_ME_HOST_IP"


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


def _read_entry(lines: list[str], entry_index: int, entry_indent: int) -> dict[str, str]:
    """Read an existing host entry's ``ansible_host`` / ``ansible_port`` children."""
    values: dict[str, str] = {}
    for index in range(entry_index + 1, len(lines)):
        line = lines[index]
        if _is_noise(line):
            continue
        if _indent(line) <= entry_indent:
            break
        match = re.match(r"^[ ]*(ansible_host|ansible_port)\s*:\s*(.*?)\s*$", line.rstrip("\n"))
        if match:
            values[match.group(1)] = match.group(2).strip().strip('"').strip("'")
    return values


def _keep_existing(lines: list[str], entry_index: int, entry_indent: int, args) -> int:
    """Report an existing host entry; never overwrite unless explicitly forced."""
    current = _read_entry(lines, entry_index, entry_indent)
    requested = {
        key: value
        for key, value in (("ansible_host", args.ansible_host), ("ansible_port", args.ansible_port))
        if value
    }
    conflicts = {k: (current.get(k, ""), v) for k, v in requested.items() if current.get(k, "") != v}

    if not conflicts:
        detail = f" ({', '.join(f'{k}={v}' for k, v in current.items())})" if current else ""
        print(f"{args.host} already present in {args.inventory} ({args.group}); unchanged{detail}")
        for key in ("ansible_host", "ansible_port"):
            if current.get(key):
                print(f"effective {key}={current[key]}")
        return 0

    if not args.force:
        for key, (existing, wanted) in conflicts.items():
            print(
                f"WARNING: {args.host} already has {key} '{existing}' (requested '{wanted}'); not changed.",
                file=sys.stderr,
            )
        print(f"         Fix: edit {args.inventory}, or re-run with FORCE_IP=1.", file=sys.stderr)
        for key, (existing, _) in conflicts.items():
            if existing:
                print(f"effective {key}={existing}")
        return 0

    new_lines = [l for l in lines]
    for key, (_, wanted) in conflicts.items():
        pattern = re.compile(r"^[ ]*" + key + r"\s*:")
        for index in range(entry_index + 1, len(new_lines)):
            if _indent(new_lines[index]) <= entry_indent:
                break
            if pattern.match(new_lines[index]):
                new_lines[index] = " " * (entry_indent + 2) + f'{key}: "{wanted}"\n'
                break
    with open(args.inventory, "w", encoding="utf-8") as handle:
        handle.writelines(new_lines)
    print(f"{args.host}: overwritten with the requested values (forced)")
    for key, (_, wanted) in conflicts.items():
        print(f"effective {key}={wanted}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inventory", help="Path to the inventory YAML file")
    parser.add_argument("host", help="Inventory host name to ensure")
    parser.add_argument("--group", default=DEFAULT_GROUP, help="Inventory group (default: %(default)s)")
    parser.add_argument(
        "--ansible-host",
        default=DEFAULT_ANSIBLE_HOST,
        help="ansible_host value for a newly added host; empty (the default) omits the key",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite an existing entry whose value differs (the deliberate override)",
    )
    parser.add_argument(
        "--ansible-port",
        default="",
        help="ansible_port value for a newly added host; empty omits the key (default: %(default)s)",
    )
    parser.add_argument(
        "--comment",
        default="",
        help="inline comment appended to the ansible_host line",
    )
    args = parser.parse_args()

    requested_host = args.ansible_host.strip()

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
            return _keep_existing(lines, index, indent, args)
        if entry_indent is None:
            entry_indent = indent

    if entry_indent is None:
        entry_indent = hosts_indent + 2

    created_host = requested_host or DEFAULT_ANSIBLE_HOST
    inserted = [" " * entry_indent + f"{args.host}:\n"]
    line = " " * (entry_indent + 2) + f'ansible_host: "{created_host}"'
    if args.comment:
        line += f"  # {args.comment}"
    inserted.append(line + "\n")
    if args.ansible_port:
        inserted.append(" " * (entry_indent + 2) + f"ansible_port: {args.ansible_port}\n")
    lines[hosts_index + 1 : hosts_index + 1] = inserted

    with open(args.inventory, "w", encoding="utf-8") as handle:
        handle.writelines(lines)
    print(f"added {args.host} to {args.inventory} ({args.group})")
    print(f"effective ansible_host={created_host}")
    if args.ansible_port:
        print(f"effective ansible_port={args.ansible_port}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
