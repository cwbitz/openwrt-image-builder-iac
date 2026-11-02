"""Coverage for ``scripts/run-build.sh``."""
from __future__ import annotations

import pathlib
import stat


def make_script(tmp_path: pathlib.Path, name: str, body: str) -> pathlib.Path:
    path = tmp_path / name
    path.write_text("#!/usr/bin/env bash\n" + body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


def run_build(run_shell, tmp_path: pathlib.Path, ansible_exit: int):
    calls = tmp_path / "calls"
    calls.write_text("", encoding="utf-8")
    runner = make_script(
        tmp_path,
        "runner.sh",
        f'printf "%s\\n" "$*" >> {calls}\nexec "$@"\n',
    )
    ansible = make_script(tmp_path, "ansible.sh", f"exit {ansible_exit}\n")
    result = run_shell(
        "run-build.sh",
        env={
            "ANS_PLAY": str(ansible),
            "INV": str(tmp_path / "inventory.yml"),
            "SSH_AGENT_RUN": str(runner),
            "BUILD_EXTRA": "--limit builder-1",
        },
    )
    return result, calls.read_text(encoding="utf-8")


def test_run_build_leaves_cleanup_to_the_playbook_on_success(run_shell, tmp_path):
    result, calls = run_build(run_shell, tmp_path, 0)

    assert result.returncode == 0, result.stdout + result.stderr
    assert "playbooks/build.yml" in calls
    assert "playbooks/cleanup_build.yml" not in calls
    assert "--limit builder-1" in calls


def test_run_build_cleans_up_after_a_failed_build(run_shell, tmp_path):
    result, calls = run_build(run_shell, tmp_path, 7)

    assert result.returncode == 7
    assert "playbooks/build.yml" in calls
    assert "playbooks/cleanup_build.yml" in calls
    assert "--limit builder-1" in calls
    assert "removing containers and scratch" in result.stderr
