#!/usr/bin/env bash
set -euo pipefail

echo "AZME 24h legacy daemon moved to native runtime path."
echo "Starting canonical native mode..."
exec bash scripts/start_azl_native_mode.sh
