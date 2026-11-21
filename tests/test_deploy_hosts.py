"""Coverage for ``scripts/deploy_hosts.py``.

The helper asks ``ansible-inventory --list`` for the inventory document; the
tests put a fake ``ansible-inventory`` first on ``PATH`` that replays a fixed
document, so no real inventory or Ansible installation is involved.
"""
from __future__ import annotations

import json
import os


def run_helper(run_python, write_file, tmp_path, document, group="builders"):
    payload = write_file("inventory.json", json.dumps(document))
    write_file(
        "ansible-inventory",
        '#!/usr/bin/env bash\ncat "$FAKE_INVENTORY_JSON"\n',
        mode=0o755,
    )
    return run_python(
        "deploy_hosts.py",
        tmp_path / "hosts.yml",
        group,
        env={
            "PATH": f"{tmp_path}{os.pathsep}{os.environ['PATH']}",
            "FAKE_INVENTORY_JSON": str(payload),
        },
    )


def test_skips_test_hosts_and_keeps_the_group_order(run_python, write_file, tmp_path):
    document = {
        "builders": {"hosts": ["lab-1", "lab-2", "lab-3"], "children": ["workers"]},
        "workers": {"hosts": ["lab-4"], "children": ["rack"]},
        "rack": {"hosts": ["lab-5"]},
        "_meta": {
            "hostvars": {
                "lab-1": {"is_test_host": False},
                "lab-2": {"is_test_host": True},
                "lab-3": {},
                "lab-4": {"is_test_host": False},
                "lab-5": {"is_test_host": True},
            }
        },
    }

    result = run_helper(run_python, write_file, tmp_path, document)

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "lab-1,lab-3,lab-4"


def test_every_test_host_yields_an_empty_list(run_python, write_file, tmp_path):
    document = {
        "builders": {"hosts": ["lab-1"]},
        "_meta": {"hostvars": {"lab-1": {"is_test_host": True}}},
    }

    result = run_helper(run_python, write_file, tmp_path, document)

    assert result.returncode == 0, result.stderr
    assert result.stdout == "\n"


def test_a_host_listed_twice_is_reported_once(run_python, write_file, tmp_path):
    document = {
        "builders": {"hosts": ["lab-1"], "children": ["workers"]},
        "workers": {"hosts": ["lab-1", "lab-2"]},
        "_meta": {"hostvars": {"lab-1": {}, "lab-2": {}}},
    }

    result = run_helper(run_python, write_file, tmp_path, document)

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "lab-1,lab-2"


def test_an_empty_group_yields_an_empty_list(run_python, write_file, tmp_path):
    document = {"builders": {}, "_meta": {"hostvars": {}}}

    result = run_helper(run_python, write_file, tmp_path, document)

    assert result.returncode == 0, result.stderr
    assert result.stdout == "\n"
