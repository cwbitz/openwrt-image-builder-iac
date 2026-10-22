"""Coverage for ``scripts/audit_example_knobs.py``.

The fixture is a snapshot of the project's own tracked tree, so the suite follows
the knob inventory instead of duplicating it: the audit must pass on the tree as
committed, and must fail when an example knob is dropped.
"""
from __future__ import annotations

import pathlib
import re

KEY_LINE = re.compile(r"^([a-z_][a-z0-9_]*):")


def example_path(root: pathlib.Path) -> pathlib.Path:
    matches = [
        path
        for path in root.rglob("main.yml")
        if path.parent.name == "example" and path.parent.parent.name == "host_vars"
    ]
    assert matches, "the tracked tree carries no host_vars/example/main.yml"
    return matches[0]


def declared_knobs(root: pathlib.Path) -> set[str]:
    """Every knob the project declares in role defaults or group vars."""
    knobs: set[str] = set()
    for path in root.rglob("main.yml"):
        if "group_vars" not in path.parts and "defaults" not in path.parts:
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            match = KEY_LINE.match(line)
            if match:
                knobs.add(match.group(1))
    return knobs


def test_audit_passes_on_the_tracked_tree(run_python_at, tracked_snapshot):
    result = run_python_at(tracked_snapshot, "audit_example_knobs.py", tracked_snapshot)

    assert result.returncode == 0, result.stdout + result.stderr


def test_dropping_an_example_knob_is_reported(run_python_at, tracked_snapshot):
    example = example_path(tracked_snapshot)
    original = example.read_text(encoding="utf-8")
    lines = original.splitlines(keepends=True)
    declared = declared_knobs(tracked_snapshot)
    keyed = [
        (index, line.split(":", 1)[0])
        for index, line in enumerate(lines)
        if KEY_LINE.match(line)
    ]
    assert keyed, "the example carries no knob lines"
    ordered = [entry for entry in keyed if entry[1] in declared] + [
        entry for entry in keyed if entry[1] not in declared
    ]

    for index, key in ordered[:10]:
        example.write_text("".join(lines[:index] + lines[index + 1:]), encoding="utf-8")
        result = run_python_at(tracked_snapshot, "audit_example_knobs.py", tracked_snapshot)
        if result.returncode == 1:
            example.write_text(original, encoding="utf-8")
            assert key in result.stdout, result.stdout
            return
        example.write_text(original, encoding="utf-8")

    raise AssertionError("dropping an example knob never failed the audit")
