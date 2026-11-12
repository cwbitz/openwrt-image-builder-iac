#!/usr/bin/env python3
"""Edit an encrypted vault file without losing secrets written meanwhile.

`ansible-vault edit` decrypts the file, runs the editor and re-encrypts whatever
the editor returns, so a deploy that writes a generated secret while the editor
is open is silently overwritten by that save. This tool fingerprints the
encrypted file before the edit, decrypts it into a private temp file, and
refuses the write when the file changed in the meantime (keeping the edited text
for a manual merge instead).

A successful save sorts the top-level keys alphabetically
(`sort_vault_keys.py` semantics), verifies the sorted text line by line, encrypts
into a sibling temp file, decrypts that file back to prove it round-trips, and
only then replaces the vault atomically.

Usage: edit_vault.py <vault.yml> [--editor CMD] [--ansible-vault PATH]
Exit:  0 written (or no change), 1 refused/aborted, 2 usage, editor rc otherwise.
"""

import hashlib
import os
import shlex
import subprocess
import sys
import tempfile
from argparse import ArgumentParser

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sort_vault_keys import line_bag, sort_text, split_blocks  # noqa: E402

VAULT_MARKER = b"$ANSIBLE_VAULT"


def fingerprint(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def editor_command(explicit):
    for candidate in (explicit, os.environ.get("EDITOR"), os.environ.get("VISUAL")):
        if candidate:
            return shlex.split(candidate)
    return ["vi"]


def refuse(message, keep=None):
    print(f"refusing to write the vault: {message}", file=sys.stderr)
    if keep:
        print(f"the edited text is kept at {keep}", file=sys.stderr)
    return 1


def decrypt(vault_bin, path):
    result = subprocess.run([vault_bin, "view", path], capture_output=True)
    return result.returncode, result.stdout


def encrypt(vault_bin, text, vault_path):
    """Encrypt *text* into a sibling temp file and take the vault's place atomically."""
    directory = os.path.dirname(os.path.abspath(vault_path))
    handle, plain = tempfile.mkstemp(dir=directory, prefix=".vault-edit-", suffix=".yml")
    handle_out, encrypted = tempfile.mkstemp(dir=directory, prefix=".vault-", suffix=".tmp")
    os.close(handle_out)
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as out:
            out.write(text)
        result = subprocess.run(
            [vault_bin, "encrypt", "--output", encrypted, plain], capture_output=True
        )
        if result.returncode != 0:
            return result.returncode, result.stderr.decode("utf-8", "replace").strip()
        if subprocess.run([vault_bin, "view", encrypted], capture_output=True).stdout.decode() != text:
            return 1, "the encrypted result did not decrypt back to the edited text"
        mode = os.stat(vault_path).st_mode & 0o777
        os.chmod(encrypted, mode)
        os.replace(encrypted, vault_path)
        return 0, ""
    finally:
        for leftover in (plain, encrypted):
            if os.path.exists(leftover):
                os.unlink(leftover)


def main(argv=None):
    parser = ArgumentParser(description=__doc__, add_help=True)
    parser.add_argument("vault", help="encrypted vault file to edit")
    parser.add_argument("--editor", help="editor command (default: $EDITOR, $VISUAL, vi)")
    parser.add_argument("--ansible-vault", help="ansible-vault binary (default: $ANSIBLE_VAULT_BIN or PATH)")
    args = parser.parse_args(argv)

    path = os.path.abspath(args.vault)
    if not os.path.isfile(path):
        print(f"no such vault file: {path}", file=sys.stderr)
        return 2
    with open(path, "rb") as handle:
        head = handle.read(4096)
    if VAULT_MARKER not in head:
        return refuse(f"{path} is not an encrypted vault; encrypt it first")
    before = fingerprint(path)
    vault_bin = args.ansible_vault or os.environ.get("ANSIBLE_VAULT_BIN") or "ansible-vault"

    rc, original = decrypt(vault_bin, path)
    if rc != 0:
        print(f"could not decrypt {path}", file=sys.stderr)
        return rc

    handle, plain = tempfile.mkstemp(prefix="vault-edit-", suffix=".yml")
    with os.fdopen(handle, "wb") as out:
        out.write(original)

    rc = subprocess.run(editor_command(args.editor) + [plain]).returncode
    if rc != 0:
        refuse(f"the editor exited with status {rc}", keep=plain)
        return rc

    with open(plain, encoding="utf-8") as handle:
        text = handle.read()
    if text == original.decode("utf-8"):
        os.unlink(plain)
        print("No changes; the vault is untouched.")
        return 0
    if fingerprint(path) != before:
        return refuse(
            "it changed while you were editing, so saving would drop the secrets "
            "written in the meantime; merge them into the edited text and re-run",
            keep=plain,
        )

    content = text if text.endswith("\n") else text + "\n"
    _, blocks = split_blocks(content)
    if not blocks:
        return refuse("the edited text has no top-level keys", keep=plain)
    ordered = sort_text(content)
    if ordered is None or line_bag(content) != line_bag(ordered):
        return refuse("the edited text does not normalise", keep=plain)

    try:
        rc, detail = encrypt(vault_bin, ordered, path)
    except OSError as error:
        rc, detail = 1, str(error)
    if rc != 0:
        return refuse(f"encryption failed ({detail or 'no detail'})", keep=plain)
    os.unlink(plain)
    print(f"Encryption successful! (Total keys: {len(blocks)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
