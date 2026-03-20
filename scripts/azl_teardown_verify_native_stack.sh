#!/usr/bin/env bash
# Stop processes left by scripts/start_azl_native_mode.sh when the launcher shell has
# already exited (run_enterprise_daemon.sh backgrounds azl_bootstrap and returns).
# Call from EXIT trap in verify scripts that probed a daemon on a known port.
#
# Usage (from repo root):
#   bash scripts/azl_teardown_verify_native_stack.sh <port> <bearer_token>
#
# Token is reserved for future probes; port teardown uses the listener PID.
# Exits 0 even if nothing was running (idempotent).
set -euo pipefail

PORT="${1:-}"
TOKEN="${2:-}"
if [ -z "$PORT" ] || [ -z "$TOKEN" ]; then
  echo "usage: $0 <port> <bearer_token>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/azl_local_layout.sh"

kill_pid_file() {
  local f="$1"
  [ -f "$f" ] || return 0
  local p
  p="$(tr -d ' \t\r\n' <"$f" 2>/dev/null || true)"
  [ -n "$p" ] || return 0
  if kill -0 "$p" 2>/dev/null; then
    kill -TERM "$p" 2>/dev/null || true
    sleep 0.15
    if kill -0 "$p" 2>/dev/null; then
      kill -KILL "$p" 2>/dev/null || true
    fi
  fi
}

kill_listeners_on_port() {
  local sig="$1"
  if command -v lsof >/dev/null 2>&1; then
    # shellcheck disable=SC2046
    for ep in $(lsof -t -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true); do
      if [ -n "${ep:-}" ] && [ "$ep" -gt 1 ] 2>/dev/null; then
        kill -s "$sig" "$ep" 2>/dev/null || true
      fi
    done
    return 0
  fi
  if command -v fuser >/dev/null 2>&1; then
    if [ "$sig" = "TERM" ]; then
      fuser -TERM -k -n tcp "$PORT" 2>/dev/null || true
    else
      fuser -KILL -k -n tcp "$PORT" 2>/dev/null || true
    fi
    return 0
  fi
  echo "WARNING[azl_teardown_verify_native_stack]: no lsof or fuser; cannot kill listener on port ${PORT}" >&2
}

# Stop bootstrap / helpers first so the engine can exit cleanly
kill_pid_file "${AZL_RUN_DIR}/daemon.pid"
sleep 0.2
kill_pid_file "${AZL_RUN_DIR}/syswire.pid"
kill_pid_file "${AZL_RUN_DIR}/sysproxy.pid"

kill_listeners_on_port TERM
sleep 0.45
kill_listeners_on_port KILL

exit 0
