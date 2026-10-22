"""Coverage for ``scripts/run-with-ssh-agent.sh``."""
from __future__ import annotations

import pathlib
import stat


def make_script(tmp_path: pathlib.Path, name: str, body: str) -> pathlib.Path:
    path = tmp_path / name
    path.write_text("#!/usr/bin/env bash\n" + body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


def test_agent_runner_passes_output_through(run_shell, tmp_path):
    command = make_script(tmp_path, "ok.sh", 'echo "deployed"\n')
    result = run_shell("run-with-ssh-agent.sh", command)

    assert result.returncode == 0
    assert "deployed" in result.stdout


def test_agent_runner_propagates_failure(run_shell, tmp_path):
    command = make_script(tmp_path, "fails.sh", 'echo "playbook failed" >&2; exit 4\n')
    result = run_shell("run-with-ssh-agent.sh", command)

    assert result.returncode == 4
    assert "playbook failed" in result.stderr


def test_agent_runner_retries_once_on_a_refused_key(run_shell, tmp_path):
    counter = tmp_path / "count"
    counter.write_text("0", encoding="utf-8")
    command = make_script(
        tmp_path,
        "keyflaky.sh",
        f"""n=$(cat {counter}); n=$((n+1)); echo $n > {counter}
if [ "$n" -eq 1 ]; then echo "Permission denied (publickey)." >&2; exit 255; fi
echo "second attempt succeeded"
""",
    )
    keychain = make_script(tmp_path, "keychain.sh", "exit 0\n")
    result = run_shell(
        "run-with-ssh-agent.sh",
        command,
        env={
            "SSH_AGENT_KEYCHAIN_BIN": str(keychain),
            "SSH_AGENT_ANS_PLAY": "/bin/true",
            "SSH_AGENT_INVENTORY": str(tmp_path / "inventory.yml"),
            "SSH_AGENT_LOAD_PLAYBOOK": str(tmp_path / "load.yml"),
        },
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "retrying once" in result.stderr
    assert "second attempt succeeded" in result.stdout
    assert counter.read_text().strip() == "2"


def test_agent_runner_reports_a_failed_retry(run_shell, tmp_path):
    command = make_script(
        tmp_path,
        "always-refused.sh",
        'echo "Permission denied (publickey)." >&2; exit 255\n',
    )
    keychain = make_script(tmp_path, "keychain.sh", "exit 0\n")
    result = run_shell(
        "run-with-ssh-agent.sh",
        command,
        env={
            "SSH_AGENT_KEYCHAIN_BIN": str(keychain),
            "SSH_AGENT_ANS_PLAY": "/bin/true",
            "SSH_AGENT_INVENTORY": str(tmp_path / "inventory.yml"),
            "SSH_AGENT_LOAD_PLAYBOOK": str(tmp_path / "load.yml"),
        },
    )

    assert result.returncode == 1
    assert "retry failed" in result.stderr
