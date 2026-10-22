"""Coverage for ``scripts/check_repo_privacy.py``.

Each case builds a throwaway git repository, stages the files under test and runs
the checker, so nothing real is ever read.
"""
from __future__ import annotations

import pathlib
import shutil
import subprocess

import pytest

CLEAN = """---
# Host template
domain_name: "netbird.example.com"
acme_email: "admin@example.com"
network_gateway: "172.30.0.1"
"""


def init_repo(root: pathlib.Path, files: dict[str, str]) -> pathlib.Path:
    subprocess.run(["git", "-C", str(root), "init", "-q"], check=True)
    for name, content in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        subprocess.run(["git", "-C", str(root), "add", "-f", name], check=True)
    return root


def test_clean_tree_passes(run_python, tmp_path):
    root = init_repo(tmp_path, {"docs/readme.md": CLEAN})

    result = run_python("check_repo_privacy.py", root)

    assert result.returncode == 0, result.stdout + result.stderr
    assert "OK" in result.stdout


def test_local_only_tree_is_rejected(run_python, tmp_path):
    root = init_repo(tmp_path, {"inventory/host_vars/live-1/main.yml": "timezone: UTC\n"})

    result = run_python("check_repo_privacy.py", root)

    assert result.returncode == 1
    assert "inventory/host_vars/live-1/main.yml: local-only tree is tracked" in result.stdout


def test_example_tree_is_accepted(run_python, tmp_path):
    root = init_repo(tmp_path, {"inventory/host_vars/example/main.yml": CLEAN})

    result = run_python("check_repo_privacy.py", root)

    assert result.returncode == 0, result.stdout + result.stderr


def test_credential_file_is_rejected(run_python, tmp_path):
    root = init_repo(tmp_path, {"inventory/host_vars/example/vault.yml": "secret: x\n"})

    result = run_python("check_repo_privacy.py", root)

    assert result.returncode == 1
    assert "credential file is tracked" in result.stdout


def test_vault_template_is_accepted(run_python, tmp_path):
    root = init_repo(tmp_path, {"inventory/host_vars/example/vault.yml.example": "vault_x: \"\"\n"})

    result = run_python("check_repo_privacy.py", root)

    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.parametrize("address", ["100.125." + "231.160", "8.8." + "8.8"])
def test_live_address_is_rejected(run_python, tmp_path, address):
    root = init_repo(tmp_path, {"docs/run.md": f"probe {address}:9100 failed\n"})

    result = run_python("check_repo_privacy.py", root)

    assert result.returncode == 1
    assert f"non-placeholder address {address}" in result.stdout


def test_documentation_address_is_accepted(run_python, tmp_path):
    root = init_repo(tmp_path, {"docs/run.md": "probe 203.0.113.11:9100 failed\n"})

    result = run_python("check_repo_privacy.py", root)

    assert result.returncode == 0, result.stdout + result.stderr


def test_cidr_notation_is_not_an_address(run_python, tmp_path):
    root = init_repo(tmp_path, {"playbooks/validate.yml": "overlay: 100.64.0.0/10\n"})

    result = run_python("check_repo_privacy.py", root)

    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.parametrize(
    "line",
    ["collabora_version: \"26.04.5.1.1\"\n", "network_netmask: 255.255.255.0\n"],
)
def test_version_and_netmask_are_not_addresses(run_python, tmp_path, line):
    root = init_repo(tmp_path, {"roles/demo/vars/main.yml": line})

    result = run_python("check_repo_privacy.py", root)

    assert result.returncode == 0, result.stdout + result.stderr


def test_allowlisted_subnet_is_accepted(run_python, tmp_path):
    root = init_repo(
        tmp_path,
        {
            ".privacy-allowlist": "# fixed container network\n172.30.0.0/16\n",
            "roles/demo/vars/main.yml": "gateway: 172.30.0.1\n",
        },
    )

    result = run_python("check_repo_privacy.py", root)

    assert result.returncode == 0, result.stdout + result.stderr


def test_real_mailbox_is_rejected(run_python, tmp_path):
    root = init_repo(tmp_path, {"README.md": "Contact: ops@" + "meshify.example-domain.fr\n"})

    result = run_python("check_repo_privacy.py", root)

    assert result.returncode == 1
    assert "real mailbox" in result.stdout


def test_example_mailbox_is_accepted(run_python, tmp_path):
    root = init_repo(tmp_path, {"README.md": "Contact: ops@example.com\n"})

    result = run_python("check_repo_privacy.py", root)

    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.skipif(shutil.which("ansible-inventory") is None, reason="ansible-inventory is not installed")
def test_inventory_host_name_is_rejected(run_python, tmp_path):
    root = init_repo(tmp_path, {"docs/run.md": "Ran against live-host-1 for the run.\n"})
    (root / "inventory").mkdir(exist_ok=True)
    (root / "inventory/hosts.yml").write_text(
        "---\nall:\n  children:\n    management:\n      hosts:\n        live-host-1:\n",
        encoding="utf-8",
    )

    result = run_python("check_repo_privacy.py", root)

    assert result.returncode == 1
    assert "inventory host name live-host-1" in result.stdout


def test_missing_work_tree_is_an_error(run_python, tmp_path):
    result = run_python("check_repo_privacy.py", tmp_path)

    assert result.returncode == 2
    assert "not a git work tree" in result.stderr
