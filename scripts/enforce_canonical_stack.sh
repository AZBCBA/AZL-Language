#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

canonical_files=(
  "azl/runtime/interpreter/azl_interpreter.azl"
  "azl/runtime/vm/azl_vm.azl"
  "azl/system/http_server.azl"
  "azl/system/azl_system_interface.azl"
  "azl/core/compiler/azl_parser.azl"
  "azl/core/compiler/azl_compiler.azl"
  "azl/core/compiler/azl_bytecode.azl"
  "tools/azl_native_engine.c"
  "tools/sysproxy.c"
)

for f in "${canonical_files[@]}"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: canonical file missing: $f" >&2
    exit 101
  fi
done

# Enforce that legacy bootstrap paths are blocked in native-only mode.
if ! rg -q "blocked by AZL_NATIVE_ONLY=1" scripts/azl; then
  echo "ERROR: scripts/azl missing native-only guard" >&2
  exit 110
fi

echo "canonical-stack-enforcement: ok"
