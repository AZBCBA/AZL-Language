#!/usr/bin/env bash
set -euo pipefail

echo "AZME foreground daemon moved to native runtime path."
exec bash scripts/start_azl_native_mode.sh

