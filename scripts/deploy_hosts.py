#!/usr/bin/env python3
"""Print the deployable hosts of an inventory group.

A host whose ``is_test_host`` is true is skipped; an explicit ``HOST=<name>``
bypasses this helper in the Makefile.
"""

from __future__ import annotations

import json
import subprocess
import sys


def main() -> int:
    inventory, group = sys.argv[1], sys.argv[2]
    result = subprocess.run(
        ["ansible-inventory", "-i", inventory, "--list"],
        check=True,
        capture_output=True,
        text=True,
    )
    data = json.loads(result.stdout)

    def group_hosts(name: str, seen: set[str]) -> list[str]:
        if name in seen:
            return []
        seen.add(name)
        node = data.get(name) or {}
        hosts = list(node.get("hosts") or [])
        for child in node.get("children") or []:
            hosts += group_hosts(child, seen)
        return hosts

    hostvars = data.get("_meta", {}).get("hostvars", {})
    deployable = [
        host for host in dict.fromkeys(group_hosts(group, set()))
        if not (hostvars.get(host, {}).get("is_test_host") or False)
    ]
    print(",".join(deployable))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
