#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PID_FILE="$ROOT_DIR/.azl/azme_24h.pid"
OUT_FILE="$ROOT_DIR/.azl/logs/azme_24h.out"
DASHBOARD_URL="http://${AZL_DASHBOARD_HOST:-127.0.0.1}:${AZL_DASHBOARD_PORT:-8787}"
SERVICE_NAME="azme-24h.service"

if command -v systemctl >/dev/null 2>&1 && systemctl --user list-unit-files | rg -q "^${SERVICE_NAME}\\s"; then
  set +e
  systemctl --user is-active --quiet "$SERVICE_NAME"
  active_rc=$?
  set -e
  if [ "$active_rc" -eq 0 ]; then
    echo "AZME 24h service: RUNNING ($SERVICE_NAME)"
    echo "Dashboard: $DASHBOARD_URL"
    set +e
    health="$(curl -sS --max-time 3 "$DASHBOARD_URL/healthz")"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
      echo "Dashboard health: $health"
    else
      echo "Dashboard health: UNREACHABLE"
    fi
    exit 0
  fi
  echo "AZME 24h service: STOPPED ($SERVICE_NAME)"
  exit 1
fi

if [ ! -f "$PID_FILE" ]; then
  echo "AZME 24h daemon: STOPPED (no pid file)"
  exit 1
fi

pid="$(cat "$PID_FILE" || true)"
if [ -z "$pid" ]; then
  echo "AZME 24h daemon: STOPPED (empty pid file)"
  exit 1
fi

if ! kill -0 "$pid" 2>/dev/null; then
  echo "AZME 24h daemon: STOPPED (stale pid $pid)"
  exit 1
fi

echo "AZME 24h daemon: RUNNING"
echo "PID: $pid"
echo "Log: $OUT_FILE"
echo "Dashboard: $DASHBOARD_URL"

set +e
health="$(curl -sS --max-time 3 "$DASHBOARD_URL/healthz")"
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  echo "Dashboard health: $health"
else
  echo "Dashboard health: UNREACHABLE"
fi
