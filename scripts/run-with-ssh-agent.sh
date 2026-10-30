#!/usr/bin/env bash

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
