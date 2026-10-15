#!/usr/bin/env python3
"""Render a comment-free copy of a YAML template.

Every full-line comment is dropped and runs of blank lines collapse to a single
separator; a leading ``---`` marker is kept. Content lines (including any inline
comments) are copied verbatim. Uses only the standard library.

Usage:
    render_clean_template.py <source> <dest>
"""
from __future__ import annotations

import argparse
import sys


def clean(text: str) -> str:
    result: list[str] = []
    pending_blank = False
    for raw in text.splitlines():
        stripped = raw.strip()
        if not stripped:
            pending_blank = True
            continue
        if stripped.startswith("#"):
            continue
        if pending_blank and result and result[-1] != "---":
            result.append("")
        result.append(raw.rstrip())
        pending_blank = False
    return "".join(line + "\n" for line in result)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", help="Commented template to read")
    parser.add_argument("dest", help="Comment-free file to write")
    args = parser.parse_args()

    try:
        with open(args.source, encoding="utf-8") as handle:
            text = handle.read()
    except FileNotFoundError:
        print(f"ERROR: {args.source} does not exist", file=sys.stderr)
        return 1

    with open(args.dest, "w", encoding="utf-8") as handle:
        handle.write(clean(text))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
