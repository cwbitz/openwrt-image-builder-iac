"""Coverage for ``scripts/check_script_modes.py``."""
from __future__ import annotations


def test_executable_shell_script_passes(run_python, write_file):
    path = write_file("scripts/tool.sh", "#!/bin/sh\nexit 0\n", 0o755)
    result = run_python("check_script_modes.py", path.parents[1])

    assert result.returncode == 0, result.stdout + result.stderr
    assert "OK" in result.stdout


def test_non_executable_shell_script_is_reported(run_python, write_file):
    path = write_file("scripts/tool.sh", "#!/bin/sh\nexit 0\n", 0o644)
    result = run_python("check_script_modes.py", path.parents[1])

    assert result.returncode == 1
    assert "scripts/tool.sh" in result.stderr


def test_python_helper_may_stay_non_executable(run_python, write_file):
    path = write_file("scripts/helper.py", "#!/usr/bin/env python3\n", 0o644)
    result = run_python("check_script_modes.py", path.parents[1])

    assert result.returncode == 0, result.stdout + result.stderr


def test_template_shell_files_are_ignored(run_python, write_file):
    path = write_file("roles/example/templates/run.sh.j2", "#!/bin/sh\n", 0o644)
    result = run_python("check_script_modes.py", path.parents[3])

    assert result.returncode == 0, result.stdout + result.stderr
