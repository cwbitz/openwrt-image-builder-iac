"""Coverage for ``scripts/check_host_keys.py``."""
from __future__ import annotations

DISABLED_KEY_CHECKING = "host_key_" + "checking = False"
STRICT_NO = "StrictHost" + "KeyChecking=no"
NULL_KNOWN_HOSTS = "UserKnownHosts" + "File=/dev/null"


def test_clean_tree_passes(run_python, write_file):
    root = write_file("ansible.cfg", "[defaults]\nhost_key_checking = True\n").parent
    result = run_python("check_host_keys.py", root)

    assert result.returncode == 0, result.stdout + result.stderr
    assert "OK" in result.stdout


def test_disabled_host_key_checking_is_rejected(run_python, write_file):
    path = write_file("ansible.cfg", "[defaults]\n" + DISABLED_KEY_CHECKING + "\n")
    result = run_python("check_host_keys.py", path.parent)

    assert result.returncode == 1
    assert "host_key_checking disabled" in result.stderr


def test_strict_host_key_checking_override_is_rejected(run_python, write_file):
    path = write_file("ssh_args.cfg", "ssh_args = -o " + STRICT_NO + "\n")
    result = run_python("check_host_keys.py", path.parent)

    assert result.returncode == 1
    assert "StrictHostKeyChecking disabled" in result.stderr


def test_known_hosts_null_override_is_rejected(run_python, write_file):
    path = write_file("cfg", "ssh_args = -o " + NULL_KNOWN_HOSTS + "\n")
    result = run_python("check_host_keys.py", path.parent)

    assert result.returncode == 1
    assert NULL_KNOWN_HOSTS in result.stderr


def test_documentation_is_skipped(run_python, write_file):
    path = write_file("notes.md", "Never set " + DISABLED_KEY_CHECKING + "\n")
    result = run_python("check_host_keys.py", path.parent)

    assert result.returncode == 0, result.stdout + result.stderr
