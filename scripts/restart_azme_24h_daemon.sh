#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVICE_NAME="azme-24h.service"

if [ "${AZME_FORCE_LEGACY_DAEMON:-0}" != "1" ] && command -v systemctl >/dev/null 2>&1; then
  if systemctl --user list-unit-files | rg -q "^${SERVICE_NAME}\\s"; then
    systemctl --user restart "$SERVICE_NAME"
    systemctl --user status "$SERVICE_NAME" --no-pager || true
    exit 0
  fi
fi

"$ROOT_DIR/scripts/stop_azme_24h_daemon.sh" || true
sleep 1
"$ROOT_DIR/scripts/start_azme_24h_daemon.sh"
"$ROOT_DIR/scripts/status_azme_24h_daemon.sh"
