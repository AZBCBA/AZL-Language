#!/usr/bin/env bash
# Verifies runtime spine wiring: resolver, semantic launcher, host error surface.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

chmod +x scripts/azl_resolve_native_runtime_cmd.sh scripts/azl_azl_interpreter_runtime.sh 2>/dev/null || true

def="$(bash scripts/azl_resolve_native_runtime_cmd.sh)"
if [ "$def" != "bash scripts/azl_c_interpreter_runtime.sh" ]; then
  echo "ERROR: default AZL_RUNTIME_SPINE must resolve to C minimal, got: $def" >&2
  exit 90
fi

export AZL_RUNTIME_SPINE=azl_interpreter
sem="$(bash scripts/azl_resolve_native_runtime_cmd.sh)"
if [ "$sem" != "bash scripts/azl_azl_interpreter_runtime.sh" ]; then
  echo "ERROR: AZL_RUNTIME_SPINE=azl_interpreter must resolve to semantic launcher, got: $sem" >&2
  exit 91
fi
unset AZL_RUNTIME_SPINE

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 required for spine host contract check" >&2
  exit 92
fi

set +e
out="$(AZL_COMBINED_PATH=/nonexistent/combined.azl AZL_ENTRY='::boot.entry' python3 tools/azl_runtime_spine_host.py 2>&1)"
rc=$?
set -e
if [ "$rc" -ne 71 ]; then
  echo "ERROR: spine host must exit 71 for invalid combined path, got rc=$rc out=$out" >&2
  exit 93
fi
if ! printf '%s\n' "$out" | rg -q 'ERR_AZL_COMBINED_PATH_INVALID'; then
  echo "ERROR: spine host stderr must mention ERR_AZL_COMBINED_PATH_INVALID" >&2
  printf '%s\n' "$out" >&2
  exit 94
fi

FIXTURE="${ROOT_DIR}/azl/tests/c_minimal_link_ping.azl"
set +e
out2="$(AZL_COMBINED_PATH="$FIXTURE" AZL_ENTRY='boot.entry' python3 tools/azl_runtime_spine_host.py 2>&1)"
rc2=$?
set -e
if [ "$rc2" -ne 78 ]; then
  echo "ERROR: spine host must exit 78 (unimplemented) for valid env until executor ships, got rc=$rc2 out=$out2" >&2
  exit 95
fi
if ! printf '%s\n' "$out2" | rg -q 'ERR_AZL_SEMANTIC_HOST_UNIMPLEMENTED'; then
  echo "ERROR: expected ERR_AZL_SEMANTIC_HOST_UNIMPLEMENTED in stderr" >&2
  printf '%s\n' "$out2" >&2
  exit 96
fi

echo "runtime-spine-contract-ok"
