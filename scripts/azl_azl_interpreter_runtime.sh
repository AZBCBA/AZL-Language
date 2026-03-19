#!/usr/bin/env bash
# Runtime child for AZL_RUNTIME_SPINE=azl_interpreter | semantic
# Invokes tools/azl_runtime_spine_host.py — integration point for full AZL-in-AZL semantics.
# Env (from native engine): AZL_COMBINED_PATH, AZL_ENTRY, AZL_BOOTSTRAP_BUNDLE, AZL_INTERPRETER_DAEMON
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v python3 >/dev/null 2>&1; then
  echo "azl_azl_interpreter_runtime: ERROR: python3 required for semantic spine host" >&2
  exit 69
fi

HOST_PY="${ROOT_DIR}/tools/azl_runtime_spine_host.py"
if [ ! -f "$HOST_PY" ]; then
  echo "azl_azl_interpreter_runtime: ERROR: missing $HOST_PY" >&2
  exit 70
fi

export AZL_INTERPRETER_DAEMON="${AZL_INTERPRETER_DAEMON:-1}"
exec python3 "$HOST_PY"
