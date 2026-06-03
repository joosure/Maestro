#!/usr/bin/env bash
set -euo pipefail

workspace_root="${SYMPHONY_WORKSPACE_ROOT:-/workspaces}"
mkdir -p "${workspace_root}"

child_pid=""

shutdown_timeout_seconds() {
  local timeout="${SYMPHONY_SHUTDOWN_TIMEOUT_SECONDS:-25}"

  case "${timeout}" in
    "" | *[!0-9]* | 0)
      printf '%s\n' "25"
      ;;

    *)
      printf '%s\n' "${timeout}"
      ;;
  esac
}

terminate_child() {
  trap - INT TERM

  if [[ -n "${child_pid}" ]] && kill -0 "${child_pid}" 2>/dev/null; then
    kill -TERM "${child_pid}" 2>/dev/null || true

    (
      sleep "$(shutdown_timeout_seconds)"

      if kill -0 "${child_pid}" 2>/dev/null; then
        printf '%s\n' "Symphony release child did not stop after TERM; sending KILL." >&2
        kill -KILL "${child_pid}" 2>/dev/null || true
      fi
    ) &
    killer_pid="$!"

    wait "${child_pid}" 2>/dev/null || true
    kill "${killer_pid}" 2>/dev/null || true
    wait "${killer_pid}" 2>/dev/null || true
  fi
}

run_release() {
  trap terminate_child INT TERM

  /app/bin/symphony "$@" &
  child_pid="$!"

  set +e
  wait "${child_pid}"
  status="$?"
  set -e

  trap - INT TERM
  exit "${status}"
}

if [[ "${1:-serve}" == "serve" ]]; then
  run_release eval "SymphonyElixir.Release.Runner.serve_from_env()"
fi

exec /app/bin/symphony "$@"
