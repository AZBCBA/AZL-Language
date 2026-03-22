#!/usr/bin/env bash
# Developer convenience: same checks as scripts/verify_azl_core_engine.sh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$ROOT_DIR/scripts/verify_azl_core_engine.sh"
