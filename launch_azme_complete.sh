#!/usr/bin/env bash
# Canonical production entry for the full native enterprise stack.
# Historical "azl run …" multi-file launchers are non-canonical (see docs/CONNECTIVITY_AUDIT.md).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

if [ ! -f "scripts/start_azl_native_mode.sh" ]; then
  echo "ERROR[LAUNCH_AZME_COMPLETE]: missing scripts/start_azl_native_mode.sh — run from repository root (current: ${ROOT_DIR})" >&2
  exit 64
fi

echo "AZME / AZL complete stack → native enterprise daemon (canonical)."
echo "Exec: bash scripts/start_azl_native_mode.sh"
echo ""

exec bash scripts/start_azl_native_mode.sh
