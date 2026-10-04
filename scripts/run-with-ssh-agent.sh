#!/usr/bin/env bash
#
# run-with-ssh-agent.sh — shared by the 5 IaC projects. DO NOT fork unless the
# interface itself must change (then update all 5 together).
#
# Run a command; if it fails because OpenSSH refused a private key, start the
# Keychain ssh-agent, load the configured keys, and retry ONCE.
#
# Output policy ("silent retry, show only on failure"):
#   * the first attempt is buffered and replayed only when it SUCCEEDS, or when
#     it fails for a reason OTHER than a refused key;
#   * on a refused-key failure the first attempt is DISCARDED and the retry is
#     run (streamed); if the retry also fails, the first attempt's log is shown
#     for diagnosis.
#
# Environment (identical names in every project):
#   SSH_AGENT_ENV            file exporting SSH_AUTH_SOCK of the prepared agent
#   SSH_AGENT_KEYCHAIN_BIN   Keychain binary
#   SSH_AGENT_ANS_PLAY       ansible-playbook binary
#   SSH_AGENT_INVENTORY      inventory path
#   SSH_AGENT_LOAD_PLAYBOOK  playbook that loads the vault keys into the agent
#
# Usage: run-with-ssh-agent.sh <command> [args...]

if [ -n "${SSH_AGENT_ENV:-}" ] && [ -f "$SSH_AGENT_ENV" ]; then
  # shellcheck disable=SC1090
  . "$SSH_AGENT_ENV"
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

"$@" >"$log" 2>&1
rc=$?

if [ "$rc" -eq 0 ]; then
  cat "$log"
  exit 0
fi

if grep -qiE 'UNPROTECTED PRIVATE KEY FILE|are too open|bad permissions|Permissions [0-9]+ for|no such identity|Permission denied \(publickey\)' "$log"; then
  echo "run-with-ssh-agent: SSH refused a private key — starting Keychain, loading keys, retrying once..." >&2
  eval "$("$SSH_AGENT_KEYCHAIN_BIN" agent start --eval --quiet 2>/dev/null)"
  "$SSH_AGENT_ANS_PLAY" -i "$SSH_AGENT_INVENTORY" "$SSH_AGENT_LOAD_PLAYBOOK"
  if "$@"; then
    exit 0
  fi
  echo "run-with-ssh-agent: retry failed; original attempt output follows:" >&2
  cat "$log" >&2
  exit 1
fi

cat "$log" >&2
exit "$rc"
