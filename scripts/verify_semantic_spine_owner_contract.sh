#!/usr/bin/env bash
# Gate G2 — semantic spine *owner contract* (docs: RUNTIME_SPINE_DECISION.md, AZL_NATIVE_RUNTIME_CONTRACT.md).
#
# Target (steady state): C orchestrates process/orchestration; AZL (azl_interpreter.azl) owns full meaning.
# Current (transitional): default enterprise child = C minimal on combined bundle; semantic launcher only
#   (AZL_RUNTIME_SPINE=azl_interpreter|semantic) uses Python minimal_runtime as exec carrier for .azl sources.
#
# Probe stdout (fixed order, exact match):
#   Line 1  AZL_SEMANTIC_SPEC_OWNER   = intended spec anchor (.azl path), not “already shipped full depth.”
#   Line 2  AZL_SPINE_EXEC_OWNER      = exec carrier on semantic launcher path today (minimal_runtime_python).
# G2 does not flip default spine, retire C minimal, or fake transition to target state.
# Fails if the semantic spine launcher/host stops delegating to tools/azl_semantic_engine/minimal_runtime.
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
  echo "ERROR: spine host --semantic-owner stdout must match exactly (spec anchor, then spine exec carrier):" >&2
  printf '%s\n' "$expected" >&2
  printf '%s\n' "$probe_out" >&2
  exit 98
fi

if ! rg -q '^exec python3' "$LAUNCHER"; then
  echo "ERROR: $LAUNCHER must exec python3 spine host (semantic launcher must not become C minimal)" >&2
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

echo "semantic-spine-owner-contract-ok (target=C-orchestrates-AZL-interprets; current=default-C-minimal semantic-launcher=minimal_runtime_python)"
