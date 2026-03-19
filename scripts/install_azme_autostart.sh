#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REAL_HOME="$(getent passwd "$USER" | cut -d: -f6 || true)"
if [ -z "$REAL_HOME" ]; then
  REAL_HOME="$HOME"
fi
USER_SYSTEMD_DIR="${REAL_HOME}/.config/systemd/user"
SERVICE_NAME="azme-24h.service"
SERVICE_TEMPLATE="$ROOT_DIR/scripts/systemd/azme-24h.service.template"
SERVICE_DEST="$USER_SYSTEMD_DIR/$SERVICE_NAME"

if [ "${AZL_NATIVE_ONLY:-1}" = "1" ] && [ "${AZL_ENABLE_LEGACY_HOST:-0}" != "1" ]; then
  echo "ERROR: Native-only mode blocks installing Python azme-24h autostart service."
  echo "Use native startup path instead: bash scripts/start_azl_native_mode.sh"
  exit 64
fi

if [ ! -f "$SERVICE_TEMPLATE" ]; then
  echo "ERROR: missing systemd service template: $SERVICE_TEMPLATE"
  exit 1
fi

mkdir -p "$USER_SYSTEMD_DIR"

escaped_root="$(printf '%s' "$ROOT_DIR" | sed 's/[\/&]/\\&/g')"
sed "s/__AZME_ROOT__/$escaped_root/g" "$SERVICE_TEMPLATE" > "$SERVICE_DEST"

if ! command -v systemctl >/dev/null 2>&1; then
  echo "ERROR: systemctl is required but not found"
  exit 1
fi

systemctl --user daemon-reload
systemctl --user enable "$SERVICE_NAME"
systemctl --user restart "$SERVICE_NAME"
systemctl --user status "$SERVICE_NAME" --no-pager || true

echo ""
echo "AZME autostart installed."
echo "Service: $SERVICE_DEST"
echo "Check:   systemctl --user status $SERVICE_NAME --no-pager"
echo "Logs:    journalctl --user -u $SERVICE_NAME -f"
echo "Dash:    http://127.0.0.1:${AZL_DASHBOARD_PORT:-8787}"

if command -v loginctl >/dev/null 2>&1; then
  echo ""
  echo "Optional (boot-time start without active login):"
  echo "  sudo loginctl enable-linger $USER"
fi

