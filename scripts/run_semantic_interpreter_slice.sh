#!/usr/bin/env bash
# Run the P0 "interpreter slice" on the semantic spine (Python minimal_runtime, parity-gated vs C).
# Full azl_interpreter.azl is widened incrementally; this fixture is the first boot-shaped step.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
export AZL_RUNTIME_SPINE=azl_interpreter
export PYTHONPATH="${ROOT_DIR}/tools${PYTHONPATH:+:${PYTHONPATH}}"
SLICE="${ROOT_DIR}/azl/tests/p0_semantic_interpreter_slice.azl"
exec env AZL_COMBINED_PATH="$SLICE" AZL_ENTRY=boot.entry python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py"
