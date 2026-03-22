#!/usr/bin/env bash
# Tier B P0.1 — interpreter spec is azl_interpreter.azl; spine execution stays Python minimal_runtime (not C minimal).
# Fails if the azl_interpreter spine launcher or host stops delegating to tools/azl_semantic_engine.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 required for semantic spine owner contract" >&2
  exit 92
fi

HOST_PY="${ROOT_DIR}/tools/azl_runtime_spine_host.py"
LAUNCHER="${ROOT_DIR}/scripts/azl_azl_interpreter_runtime.sh"

if [ ! -f "$HOST_PY" ]; then
  echo "ERROR: missing $HOST_PY" >&2
  exit 97
fi
if [ ! -f "$LAUNCHER" ]; then
  echo "ERROR: missing $LAUNCHER" >&2
  exit 97
fi

set +e
probe_out="$(python3 "$HOST_PY" --semantic-owner 2>&1)"
probe_rc=$?
set -e
if [ "$probe_rc" -ne 0 ]; then
  echo "ERROR: spine host --semantic-owner must exit 0, got rc=$probe_rc out=$probe_out" >&2
  exit 97
fi
expected=$'AZL_SEMANTIC_SPEC_OWNER=azl/runtime/interpreter/azl_interpreter.azl\nAZL_SPINE_EXEC_OWNER=minimal_runtime_python'
if [ "$probe_out" != "$expected" ]; then
  echo "ERROR: spine host --semantic-owner must print exactly (two lines, this order):" >&2
  printf '%s\n' "$expected" >&2
  printf '%s\n' "$probe_out" >&2
  exit 98
fi

if ! rg -q '^exec python3' "$LAUNCHER"; then
  echo "ERROR: $LAUNCHER must exec python3 spine host (semantic owner is not C minimal)" >&2
  exit 99
fi
if ! rg -q 'azl_runtime_spine_host\.py' "$LAUNCHER"; then
  echo "ERROR: $LAUNCHER must invoke azl_runtime_spine_host.py" >&2
  exit 99
fi
if ! rg -q 'from azl_semantic_engine\.minimal_runtime import run_file' "$HOST_PY"; then
  echo "ERROR: $HOST_PY must import run_file from azl_semantic_engine.minimal_runtime" >&2
  exit 100
fi

echo "semantic-spine-owner-contract-ok"
