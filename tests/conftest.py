"""Shared fixtures for the control-node helper tests.

Every test runs the helper as a subprocess in a temporary directory, so the suite
never reads the real inventory, vault or backup tree.
"""
from __future__ import annotations

import os
import pathlib
import re
import shutil
import subprocess
import sys

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"


def _run(command: list[str], env: dict[str, str] | None = None) -> subprocess.CompletedProcess:
    merged = dict(os.environ)
    merged.pop("SSH_AGENT_ENV", None)
    if env:
        merged.update(env)
    return subprocess.run(command, capture_output=True, text=True, env=merged, timeout=60)


@pytest.fixture
def run_python():
    def run(name: str, *args: object, env: dict[str, str] | None = None) -> subprocess.CompletedProcess:
        return _run([sys.executable, str(SCRIPTS / name), *map(str, args)], env=env)

    return run


@pytest.fixture
def run_shell():
    def run(name: str, *args: object, env: dict[str, str] | None = None) -> subprocess.CompletedProcess:
        return _run(["bash", str(SCRIPTS / name), *map(str, args)], env=env)

    return run


@pytest.fixture
def run_python_at():
    def run(root: pathlib.Path, name: str, *args: object) -> subprocess.CompletedProcess:
        return _run([sys.executable, str(root / "scripts" / name), *map(str, args)])

    return run


@pytest.fixture
def tracked_snapshot(tmp_path):
    """A copy of the tracked files, so a test can mutate them without touching the tree."""
    dest = tmp_path / "repo"
    listing = subprocess.run(
        ("git", "-C", str(ROOT), "ls-files", "-z"), check=True, capture_output=True
    ).stdout
    for raw in listing.split(b"\0"):
        if not raw:
            continue
        relative = raw.decode()
        source = ROOT / relative
        if not source.is_file():
            continue
        target = dest / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    return dest


@pytest.fixture
def write_file(tmp_path):
    def write(name: str, content: str, mode: int | None = None) -> pathlib.Path:
        path = tmp_path / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        if mode is not None:
            path.chmod(mode)
        return path

    return write


@pytest.fixture
def default_group():
    """The inventory group ``ensure_inventory_host.py`` adds a host to by default."""
    source = (SCRIPTS / "ensure_inventory_host.py").read_text(encoding="utf-8")
    match = re.search(r'^DEFAULT_GROUP = "([^"]+)"', source, re.MULTILINE)
    assert match, "ensure_inventory_host.py carries no DEFAULT_GROUP constant"
    return match.group(1)
