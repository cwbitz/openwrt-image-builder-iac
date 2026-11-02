#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root" || exit 1

: "${ANS_PLAY:?ANS_PLAY must point at ansible-playbook}"
: "${INV:?INV must point at the inventory}"
: "${SSH_AGENT_RUN:?SSH_AGENT_RUN must point at run-with-ssh-agent.sh}"

extra_args=()
if [ -n "${BUILD_EXTRA:-}" ]; then
  read -r -a extra_args <<<"$BUILD_EXTRA"
fi

run_id="build-$(date -u +%Y%m%dT%H%M%SZ)-$$"
interrupted=0
trap 'interrupted=130' INT
trap 'interrupted=143' TERM

"$SSH_AGENT_RUN" "$ANS_PLAY" -i "$INV" playbooks/build.yml \
  -e "build_run_id=$run_id" "${extra_args[@]}"
rc=$?

trap - INT TERM

if [ "$rc" -ne 0 ] || [ "$interrupted" -ne 0 ]; then
  printf 'build: removing containers and scratch for %s\n' "$run_id" >&2
  "$SSH_AGENT_RUN" "$ANS_PLAY" -i "$INV" playbooks/cleanup_build.yml \
    -e "build_run_id=$run_id" "${extra_args[@]}" || true
fi

if [ "$interrupted" -ne 0 ]; then
  exit "$interrupted"
fi
exit "$rc"
