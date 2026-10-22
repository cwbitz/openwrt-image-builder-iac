"""Coverage for ``scripts/render_clean_template.py``."""
from __future__ import annotations

SOURCE = """---
# leading comment
key: "value"  # inline comment kept

# section


other: 1
"""


def test_strips_comments_and_collapses_blanks(run_python, write_file, tmp_path):
    source = write_file("example.yml", SOURCE)
    dest = tmp_path / "clean.yml"
    result = run_python("render_clean_template.py", source, dest)

    assert result.returncode == 0, result.stderr
    assert dest.read_text() == '---\nkey: "value"  # inline comment kept\n\nother: 1\n'


def test_strip_blank_lines(run_python, write_file, tmp_path):
    source = write_file("example.yml", SOURCE)
    dest = tmp_path / "clean.yml"
    result = run_python("render_clean_template.py", source, dest, "--strip-blank-lines")

    assert result.returncode == 0
    assert dest.read_text() == '---\nkey: "value"  # inline comment kept\nother: 1\n'


def test_missing_source_is_an_error(run_python, tmp_path):
    result = run_python("render_clean_template.py", tmp_path / "absent.yml", tmp_path / "out.yml")
    assert result.returncode == 1
    assert "does not exist" in result.stderr
    assert not (tmp_path / "out.yml").exists()
