#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PID_FILE="$ROOT_DIR/.azl/azme_24h.pid"
SERVICE_NAME="azme-24h.service"

if [ "${AZME_FORCE_LEGACY_DAEMON:-0}" != "1" ] && command -v systemctl >/dev/null 2>&1; then
  if systemctl --user list-unit-files | rg -q "^${SERVICE_NAME}\\s"; then
    systemctl --user stop "$SERVICE_NAME"
    echo "AZME 24h service stopped: $SERVICE_NAME"
    exit 0
  fi
fi

if [ ! -f "$PID_FILE" ]; then
  echo "AZME 24h daemon already stopped (no pid file)"
  exit 0
fi

pid="$(cat "$PID_FILE" || true)"
if [ -z "$pid" ]; then
  rm -f "$PID_FILE"
  echo "AZME 24h daemon stopped (empty pid file removed)"
  exit 0
fi

if ! kill -0 "$pid" 2>/dev/null; then
  rm -f "$PID_FILE"
  echo "AZME 24h daemon stopped (stale pid removed: $pid)"
  exit 0
fi

echo "Stopping AZME 24h daemon PID $pid..."
kill "$pid"

for _ in $(seq 1 15); do
  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$PID_FILE"
    echo "AZME 24h daemon stopped cleanly"
    exit 0
  fi
  sleep 1
done

echo "Process did not stop gracefully; forcing kill..."
kill -9 "$pid" 2>/dev/null || true
rm -f "$PID_FILE"
echo "AZME 24h daemon force stopped"
