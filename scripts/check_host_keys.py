#!/usr/bin/env python3
"""Reject SSH host-key verification bypasses in tracked project files.

Run from the repository root (``make lint`` / CI).
"""
from __future__ import annotations

import pathlib
import re
import subprocess
import sys


FORBIDDEN = (
    ("host_key_checking disabled", re.compile(r"host_key_checking\s*=\s*(False|no|0)\b", re.IGNORECASE)),
    ("ANSIBLE_HOST_KEY_CHECKING override", re.compile(r"ANSIBLE_HOST_KEY_CHECKING\s*=", re.IGNORECASE)),
    ("StrictHostKeyChecking disabled", re.compile(r"StrictHostKeyChecking\s*=\s*(no|off)\b", re.IGNORECASE)),
    ("UserKnownHostsFile=/dev/null", re.compile(r"UserKnownHostsFile\s*=\s*/dev/null", re.IGNORECASE)),
)
SKIP_DIRS = {".git", "collections", ".cache", ".terragrunt-cache", "artifacts", "backup", "node_modules"}
SKIP_SUFFIXES = {".md", ".rst", ".png", ".jpg", ".jpeg", ".gif", ".pdf", ".zip", ".gz", ".tgz", ".tar"}


def tracked_files(root: pathlib.Path) -> list[pathlib.Path]:
    try:
        raw = subprocess.check_output(
            ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            cwd=root,
        )
        return [root / item.decode() for item in raw.split(b"\0") if item]
    except (OSError, subprocess.CalledProcessError):
        return [
            path
            for path in root.rglob("*")
            if path.is_file() and not any(part in SKIP_DIRS for part in path.parts)
        ]


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    script = pathlib.Path(__file__).resolve()
    problems: list[str] = []
    for path in tracked_files(root):
        if path.resolve() == script or not path.is_file():
            continue
        if path.suffix.lower() in SKIP_SUFFIXES:
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            for label, pattern in FORBIDDEN:
                if pattern.search(line):
                    problems.append(f"{path.relative_to(root)}:{lineno}: {label}: {line.strip()}")
    if problems:
        print("check_host_keys: forbidden SSH host-key settings:", file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        return 1
    print("check_host_keys: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
