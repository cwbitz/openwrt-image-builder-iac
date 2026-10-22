"""Coverage for ``scripts/sort_vault_keys.py``."""
from __future__ import annotations

import os


UNSORTED = """---
vault_zeta: "z"
# comment: about alpha
vault_alpha: "a"
vault_alpha_list:
  - one
  - two
vault_middle: "m"
"""


def test_sorts_blocks_and_keeps_comments(run_python, write_file):
    path = write_file("vault.yml", UNSORTED, mode=0o600)
    result = run_python("sort_vault_keys.py", path)

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "4"
    # A comment line belongs to the block above it, so it travels with zeta.
    assert path.read_text() == (
        "---\n"
        'vault_alpha: "a"\n'
        "vault_alpha_list:\n"
        "  - one\n"
        "  - two\n"
        'vault_middle: "m"\n'
        'vault_zeta: "z"\n'
        "# comment: about alpha\n"
    )
    assert os.stat(path).st_mode & 0o777 == 0o600


def test_already_sorted_file_is_unchanged(run_python, write_file):
    content = '---\nvault_a: "1"\nvault_b: "2"\n'
    path = write_file("vault.yml", content)
    before = path.stat().st_mtime_ns
    result = run_python("sort_vault_keys.py", path)

    assert result.returncode == 0
    assert path.read_text() == content
    assert path.stat().st_mtime_ns == before


def test_file_without_top_level_keys_is_refused(run_python, write_file):
    content = "# only a comment\n- item\n"
    path = write_file("vault.yml", content)
    result = run_python("sort_vault_keys.py", path)

    assert result.returncode == 1
    assert "no top-level keys found" in result.stderr
    assert path.read_text() == content


def test_usage_without_argument(run_python):
    result = run_python("sort_vault_keys.py")
    assert result.returncode == 2
    assert "usage:" in result.stderr


def test_missing_newline_is_normalised(run_python, write_file):
    path = write_file("vault.yml", 'vault_b: "2"\nvault_a: "1"')
    result = run_python("sort_vault_keys.py", path)

    assert result.returncode == 0
    assert path.read_text() == 'vault_a: "1"\nvault_b: "2"\n'
