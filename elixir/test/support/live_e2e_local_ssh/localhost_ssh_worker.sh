#!/usr/bin/env bash
set -euo pipefail

readonly DEFAULT_STATE_DIR="${TMPDIR:-/tmp}/symphony-live-local-ssh-worker"
readonly DEFAULT_HOST_ALIAS="symphony-local-ssh"

STATE_DIR="${SYMPHONY_LOCAL_SSH_WORKER_DIR:-$DEFAULT_STATE_DIR}"
HOST_ALIAS="${SYMPHONY_LOCAL_SSH_WORKER_ALIAS:-$DEFAULT_HOST_ALIAS}"
REMOTE_PATH="${SYMPHONY_LOCAL_SSH_WORKER_REMOTE_PATH:-${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}}"
REQUESTED_PORT="${SYMPHONY_LOCAL_SSH_WORKER_PORT:-}"

started_here=0

usage() {
  cat <<'EOF'
Usage:
  localhost_ssh_worker.sh start
  localhost_ssh_worker.sh status
  localhost_ssh_worker.sh env
  localhost_ssh_worker.sh stop
  localhost_ssh_worker.sh run -- <command...>

Environment overrides:
  SYMPHONY_LOCAL_SSH_WORKER_DIR
  SYMPHONY_LOCAL_SSH_WORKER_ALIAS
  SYMPHONY_LOCAL_SSH_WORKER_REMOTE_PATH
  SYMPHONY_LOCAL_SSH_WORKER_PORT
EOF
}

require_cmd() {
  local name="$1"

  if ! command -v "$name" >/dev/null 2>&1; then
    echo "missing required command: $name" >&2
    exit 1
  fi
}

find_sshd() {
  if command -v sshd >/dev/null 2>&1; then
    command -v sshd
  elif [ -x /usr/sbin/sshd ]; then
    printf '/usr/sbin/sshd\n'
  else
    echo "missing required command: sshd" >&2
    exit 1
  fi
}

reserve_port() {
  python3 - <<'PY'
import socket

sock = socket.socket()
sock.bind(("127.0.0.1", 0))
print(sock.getsockname()[1])
sock.close()
PY
}

shell_escape() {
  printf '%q' "$1"
}

port_file() {
  printf '%s/port\n' "$STATE_DIR"
}

pid_file() {
  printf '%s/sshd.pid\n' "$STATE_DIR"
}

log_file() {
  printf '%s/sshd.log\n' "$STATE_DIR"
}

client_config_path() {
  printf '%s/ssh_config\n' "$STATE_DIR"
}

sshd_config_path() {
  printf '%s/sshd_config\n' "$STATE_DIR"
}

client_key_path() {
  printf '%s/client_ed25519\n' "$STATE_DIR"
}

host_key_path() {
  printf '%s/host_ed25519\n' "$STATE_DIR"
}

authorized_keys_path() {
  printf '%s/authorized_keys\n' "$STATE_DIR"
}

is_running() {
  local pid

  if [ ! -s "$(pid_file)" ]; then
    return 1
  fi

  pid="$(cat "$(pid_file)")"

  if [ -z "$pid" ]; then
    return 1
  fi

  kill -0 "$pid" 2>/dev/null
}

current_port() {
  if [ -n "$REQUESTED_PORT" ]; then
    printf '%s\n' "$REQUESTED_PORT"
    return 0
  fi

  if [ -s "$(port_file)" ]; then
    cat "$(port_file)"
    return 0
  fi

  return 1
}

write_client_config() {
  local port="$1"
  local user_name

  user_name="$(id -un)"

  cat > "$(client_config_path)" <<EOF
Host $HOST_ALIAS
  HostName 127.0.0.1
  Port $port
  User $user_name
  IdentityFile $(client_key_path)
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR

Host 127.0.0.1 localhost
  HostName 127.0.0.1
  Port $port
  User $user_name
  IdentityFile $(client_key_path)
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
EOF
}

write_sshd_config() {
  local port="$1"
  local sshd_bin="$2"
  local user_name

  user_name="$(id -un)"

  cat > "$(sshd_config_path)" <<EOF
Port $port
ListenAddress 127.0.0.1
HostKey $(host_key_path)
PidFile $(pid_file)
AuthorizedKeysFile $(authorized_keys_path)
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
UsePAM no
PermitRootLogin no
PermitEmptyPasswords no
AllowUsers $user_name
StrictModes no
UseDNS no
PrintMotd no
Subsystem sftp internal-sftp
SetEnv PATH=$REMOTE_PATH
LogLevel VERBOSE
EOF

  "$sshd_bin" -t -f "$(sshd_config_path)"
}

wait_for_ready() {
  local attempt

  for attempt in $(seq 1 50); do
    if ssh -F "$(client_config_path)" "$HOST_ALIAS" 'printf ready' >/dev/null 2>&1; then
      return 0
    fi

    sleep 0.2
  done

  echo "local ssh worker failed to become ready" >&2

  if [ -f "$(log_file)" ]; then
    echo "--- sshd log ---" >&2
    cat "$(log_file)" >&2
  fi

  exit 1
}

start_worker() {
  local port
  local sshd_bin

  require_cmd ssh
  require_cmd ssh-keygen
  require_cmd python3
  sshd_bin="$(find_sshd)"

  if is_running; then
    return 0
  fi

  started_here=1
  port="${REQUESTED_PORT:-$(reserve_port)}"

  rm -rf "$STATE_DIR"
  mkdir -p "$STATE_DIR"
  chmod 700 "$STATE_DIR"

  ssh-keygen -q -t ed25519 -N '' -f "$(client_key_path)" >/dev/null
  ssh-keygen -q -t ed25519 -N '' -f "$(host_key_path)" >/dev/null
  cat "$(client_key_path).pub" > "$(authorized_keys_path)"
  chmod 600 "$(authorized_keys_path)"
  printf '%s\n' "$port" > "$(port_file)"
  : > "$(log_file)"

  write_client_config "$port"
  write_sshd_config "$port" "$sshd_bin"

  python3 - "$sshd_bin" "$(sshd_config_path)" "$(log_file)" > "$(pid_file)" <<'PY'
import os
import subprocess
import sys

sshd_bin, sshd_config, log_path = sys.argv[1:4]

with open(os.devnull, "rb") as devnull, open(log_path, "ab", buffering=0) as log_file:
    process = subprocess.Popen(
        [sshd_bin, "-D", "-e", "-f", sshd_config],
        stdin=devnull,
        stdout=log_file,
        stderr=log_file,
        start_new_session=True,
    )

print(process.pid)
PY

  wait_for_ready
}

print_status() {
  local pid
  local port

  if ! is_running; then
    echo "stopped"
    return 1
  fi

  pid="$(cat "$(pid_file)")"
  port="$(current_port)"

  cat <<EOF
status=running
state_dir=$STATE_DIR
pid=$pid
port=$port
ssh_config=$(client_config_path)
worker_host=127.0.0.1:$port
log_file=$(log_file)
EOF
}

print_env() {
  local port

  if ! is_running; then
    echo "local ssh worker is not running" >&2
    exit 1
  fi

  port="$(current_port)"

  printf 'export SYMPHONY_SSH_CONFIG=%s\n' "$(shell_escape "$(client_config_path)")"
  printf 'export SYMPHONY_LIVE_SSH_WORKER_HOSTS=%s\n' "$(shell_escape "127.0.0.1:$port")"
  printf 'export SYMPHONY_LOCAL_SSH_WORKER_DIR=%s\n' "$(shell_escape "$STATE_DIR")"
}

stop_worker() {
  local pid

  if is_running; then
    pid="$(cat "$(pid_file)")"
    kill "$pid" 2>/dev/null || true

    for _attempt in $(seq 1 20); do
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi

      sleep 0.1
    done
  fi

  rm -rf "$STATE_DIR"
}

run_command() {
  local port
  local command_status

  if [ $# -lt 2 ] || [ "$1" != "--" ]; then
    usage >&2
    exit 1
  fi

  shift
  start_worker
  port="$(current_port)"

  if [ "$started_here" -eq 1 ]; then
    trap 'stop_worker >/dev/null 2>&1 || true' EXIT INT TERM
  fi

  SYMPHONY_SSH_CONFIG="$(client_config_path)" \
    SYMPHONY_LIVE_SSH_WORKER_HOSTS="127.0.0.1:$port" \
    "$@"
  command_status=$?

  if [ "$started_here" -eq 1 ]; then
    trap - EXIT INT TERM
    stop_worker
  fi

  return "$command_status"
}

main() {
  local command="${1:-}"

  case "$command" in
    start)
      shift
      start_worker
      print_status
      ;;

    status)
      shift
      print_status
      ;;

    env)
      shift
      print_env
      ;;

    stop)
      shift
      stop_worker
      ;;

    run)
      shift
      run_command "$@"
      ;;

    *)
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
