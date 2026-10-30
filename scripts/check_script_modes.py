#!/usr/bin/env python3
"""Assert control-node shell scripts in scripts/ are executable.

Usage: check_script_modes.py [repo root]      # exit 1 with a report on failure
"""
from __future__ import annotations

import os
import subprocess
import sys

SKIP_DIRS = {".git", ".cache", "collections", ".ansible", "__pycache__"}
SHELL_INTERPRETERS = (b"#!/bin/sh", b"#!/bin/bash", b"#!/usr/bin/env bash", b"#!/usr/bin/env sh")


def tracked_files(root: str) -> list[str] | None:
    try:
        output = subprocess.run(
            ["git", "-C", root, "ls-files", "-z"],
            check=True,
            capture_output=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return None
    return [raw.decode() for raw in output.split(b"\0") if raw]


def walk_files(root: str) -> list[str]:
    files: list[str] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [name for name in dirnames if name not in SKIP_DIRS]
        for name in filenames:
            files.append(os.path.relpath(os.path.join(dirpath, name), root))
    return files


def is_shell_script(path: str) -> bool:
    try:
        with open(path, "rb") as handle:
            first = handle.readline()
    except OSError:
        return False
    return first.startswith(SHELL_INTERPRETERS)


def main(argv: list[str]) -> int:
    root = argv[1] if len(argv) > 1 else os.getcwd()
    files = tracked_files(root)
    if files is None:
        files = walk_files(root)

    problems: list[str] = []
    checked = 0
    for relative in files:
        if not relative.startswith("scripts/"):
            continue
        path = os.path.join(root, relative)
        if not is_shell_script(path):
            continue
        checked += 1
        if not os.access(path, os.X_OK):
            problems.append(relative)

    if problems:
        for problem in problems:
            print(f"ERROR: control-node shell script is not executable: {problem}", file=sys.stderr)
        return 1

    print(f"check_script_modes: OK ({checked} shell scripts checked)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
