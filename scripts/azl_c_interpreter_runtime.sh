#!/usr/bin/env bash
# Phase 1: Run minimal C interpreter as runtime (optional alternative to shell loop)
# Requires: build_azl_interpreter_minimal.sh to have been run
# Env: AZL_COMBINED_PATH, AZL_ENTRY (set by native engine)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

INTERP="${AZL_INTERPRETER_BIN:-.azl/bin/azl-interpreter-minimal}"
if [ ! -x "$INTERP" ]; then
  bash scripts/build_azl_interpreter_minimal.sh
fi

export AZL_INTERPRETER_DAEMON=1
exec "$INTERP"
