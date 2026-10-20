#!/usr/bin/env python3
"""Re-order the top-level keys of a plaintext vault file alphabetically.

The control node's writers (roles/helpers/tasks/write_vault.yml) already render
every vault rewrite sorted, so a real vault.yml only drifts out of order when it
is edited by hand. `make vault-edit` runs this after the editor closes, so the
file keeps the deterministic layout.

Only the top-level key *blocks* move: a block is a top-level `key:` line plus
everything following it (continuation lines, list items, comments), so comments
and values are preserved verbatim. No YAML parser is involved (the control node's
python3 has no PyYAML): the sort is a pure line permutation, and it is verified
by comparing the line multisets before and after - content can never be lost, and
a mismatch leaves the file untouched.

Usage: sort_vault_keys.py <plaintext-vault.yml>
Output: the number of top-level keys (stdout).
Exit:  0 sorted (or already sorted), 1 refused (file untouched).
"""

import os
import re
import sys
import tempfile

# A top-level key starts at column 0; indented lines, list items (`- `) and
# comments belong to the block they follow.
KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*:")


def split_blocks(text):
    """Return (header_lines, [(key, block_lines), ...])."""
    header = []
    blocks = []
    current = None
    for line in text.splitlines(keepends=True):
        if KEY_RE.match(line):
            current = [line]
            blocks.append((line.split(":", 1)[0], current))
        elif current is None:
            header.append(line)
        else:
            current.append(line)
    return header, blocks


def sort_text(text):
    """Return the sorted text, or None when there is nothing to sort."""
    header, blocks = split_blocks(text)
    if not blocks:
        return None
    ordered = sorted(blocks, key=lambda block: block[0])
    return "".join(header + [line for _, block in ordered for line in block])


def line_bag(text):
    """Order-insensitive view of the lines, ignoring a final newline."""
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return sorted(lines)


def refuse(path, reason):
    print(f"refusing to sort {path}: {reason}", file=sys.stderr)
    return 1


def main(argv):
    if len(argv) != 2:
        print("usage: sort_vault_keys.py <plaintext-vault.yml>", file=sys.stderr)
        return 2
    path = argv[1]
    with open(path, encoding="utf-8") as handle:
        before = handle.read()

    content = before if before.endswith("\n") else before + "\n"
    _, blocks = split_blocks(content)
    if not blocks:
        return refuse(path, "no top-level keys found")

    after = sort_text(content)
    if line_bag(before) != line_bag(after):
        return refuse(path, "the sorted text would not round-trip")

    keys = [key for key, _ in blocks]
    print(len(keys))

    if after == before:
        return 0

    mode = os.stat(path).st_mode & 0o777
    handle, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(path)), suffix=".yml")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as out:
            out.write(after)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
