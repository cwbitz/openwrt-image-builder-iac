"""Coverage for ``scripts/edit_vault.py``.

The tests drive the helper with a fake ``ansible-vault`` and a fake editor, so no
real vault password or Ansible install is involved.
"""
from __future__ import annotations

import os
import stat

MARKER = "$ANSIBLE_VAULT;1.1;AES256\n"

FAKE_VAULT = """#!/bin/sh
cmd=$1; shift
case "$cmd" in
  view)
    sed '1d' "$1"
    ;;
  encrypt)
    out=$2; src=$3
    { printf '$ANSIBLE_VAULT;1.1;AES256\\n'; cat "$src"; } > "$out"
    ;;
  *)
    echo "unexpected ansible-vault command: $cmd" >&2
    exit 2
    ;;
esac
"""

EDIT_WITH_TEXT = """#!/bin/sh
printf '%s' "$FAKE_EDIT_TEXT" > "$1"
"""

EDIT_AND_TOUCH_VAULT = """#!/bin/sh
printf '%s' "$FAKE_EDIT_TEXT" > "$1"
printf 'vault_written_by_a_deploy: "x"\\n' >> "$FAKE_VAULT_PATH"
"""

EDIT_FAILS = """#!/bin/sh
printf '%s' "$FAKE_EDIT_TEXT" > "$1"
exit 3
"""

VAULT_TEXT = '---\nvault_zeta: "z"\nvault_alpha: "a"\n'


def make_executable(path):
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


def setup_tools(tmp_path, write_file, editor_body):
    vault_bin = make_executable(write_file("fake-ansible-vault", FAKE_VAULT))
    editor = make_executable(write_file("fake-editor", editor_body))
    return vault_bin, editor


def vault_file(tmp_path, write_file, text=VAULT_TEXT, mode=0o600):
    return write_file("vault.yml", MARKER + text, mode=mode)


def test_saves_sorted_vault_and_keeps_mode(tmp_path, run_python, write_file):
    vault_bin, editor = setup_tools(tmp_path, write_file, EDIT_WITH_TEXT)
    path = vault_file(tmp_path, write_file)
    edited = VAULT_TEXT + 'vault_middle: "m"\n'

    result = run_python(
        "edit_vault.py",
        path,
        "--ansible-vault",
        vault_bin,
        "--editor",
        editor,
        env={"FAKE_EDIT_TEXT": edited},
    )

    assert result.returncode == 0, result.stderr
    assert "Encryption successful! (Total keys: 3)" in result.stdout
    content = path.read_text()
    assert content.startswith(MARKER)
    assert content[len(MARKER):] == (
        '---\nvault_alpha: "a"\nvault_middle: "m"\nvault_zeta: "z"\n'
    )
    assert os.stat(path).st_mode & 0o777 == 0o600
    assert not list(tmp_path.glob("vault-edit-*")), "the plaintext copy must be removed"


def test_unchanged_edit_leaves_the_vault_untouched(tmp_path, run_python, write_file):
    vault_bin, editor = setup_tools(tmp_path, write_file, EDIT_WITH_TEXT)
    path = vault_file(tmp_path, write_file)
    before = path.read_bytes()

    result = run_python(
        "edit_vault.py",
        path,
        "--ansible-vault",
        vault_bin,
        "--editor",
        editor,
        env={"FAKE_EDIT_TEXT": VAULT_TEXT},
    )

    assert result.returncode == 0, result.stderr
    assert "No changes" in result.stdout
    assert path.read_bytes() == before
    assert not list(tmp_path.glob("vault-edit-*"))


def test_refuses_a_save_when_the_vault_changed_while_editing(tmp_path, run_python, write_file):
    vault_bin, editor = setup_tools(tmp_path, write_file, EDIT_AND_TOUCH_VAULT)
    path = vault_file(tmp_path, write_file)
    edited = VAULT_TEXT + 'vault_new: "n"\n'

    result = run_python(
        "edit_vault.py",
        path,
        "--ansible-vault",
        vault_bin,
        "--editor",
        editor,
        env={"FAKE_EDIT_TEXT": edited, "FAKE_VAULT_PATH": str(path)},
    )

    assert result.returncode == 1
    assert "changed while you were editing" in result.stderr
    # The externally written vault is untouched, and the edit is kept for merging.
    assert path.read_text().endswith('vault_written_by_a_deploy: "x"\n')
    kept = [line.rsplit(" ", 1)[-1] for line in result.stderr.splitlines() if "kept at" in line]
    assert kept, result.stderr
    assert "vault_new" in open(kept[0], encoding="utf-8").read()


def test_editor_failure_aborts_without_writing(tmp_path, run_python, write_file):
    vault_bin, editor = setup_tools(tmp_path, write_file, EDIT_FAILS)
    path = vault_file(tmp_path, write_file)
    before = path.read_bytes()

    result = run_python(
        "edit_vault.py",
        path,
        "--ansible-vault",
        vault_bin,
        "--editor",
        editor,
        env={"FAKE_EDIT_TEXT": VAULT_TEXT + 'vault_new: "n"\n'},
    )

    assert result.returncode == 3
    assert "the editor exited with status 3" in result.stderr
    assert path.read_bytes() == before


def test_editor_from_environment(tmp_path, run_python, write_file):
    vault_bin, editor = setup_tools(tmp_path, write_file, EDIT_WITH_TEXT)
    path = vault_file(tmp_path, write_file)

    result = run_python(
        "edit_vault.py",
        path,
        "--ansible-vault",
        vault_bin,
        env={"EDITOR": str(editor), "FAKE_EDIT_TEXT": VAULT_TEXT + 'vault_new: "n"\n'},
    )

    assert result.returncode == 0, result.stderr
    assert "vault_new" in path.read_text()


def test_refuses_an_empty_edit(tmp_path, run_python, write_file):
    vault_bin, editor = setup_tools(tmp_path, write_file, EDIT_WITH_TEXT)
    path = vault_file(tmp_path, write_file)
    before = path.read_bytes()

    result = run_python(
        "edit_vault.py",
        path,
        "--ansible-vault",
        vault_bin,
        "--editor",
        editor,
        env={"FAKE_EDIT_TEXT": ""},
    )

    assert result.returncode == 1
    assert "no top-level keys" in result.stderr
    assert path.read_bytes() == before


def test_refuses_a_plaintext_file(tmp_path, run_python, write_file):
    path = write_file("vault.yml", VAULT_TEXT, mode=0o600)

    result = run_python("edit_vault.py", path)

    assert result.returncode == 1
    assert "not an encrypted vault" in result.stderr
    assert path.read_text() == VAULT_TEXT


def test_missing_vault_is_a_usage_error(tmp_path, run_python):
    result = run_python("edit_vault.py", tmp_path / "absent.yml")

    assert result.returncode == 2
    assert "no such vault file" in result.stderr
