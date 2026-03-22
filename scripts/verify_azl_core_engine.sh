#!/usr/bin/env bash
# Native core engine: compile tools/azl_core_engine.c + bytecode + compiler selftests.
# Verifies JSON bytecode (vm_hello_world.json), AZL compile (vm_hello.azl + vm_branch.azl), and VM exec.
# Exit codes: docs/ERROR_SYSTEM.md § Native core engine selftest.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [ ! -f "Makefile" ] || [ ! -f "tools/azl_core_engine.c" ]; then
  echo "ERROR[AZL_CORE_ENGINE_VERIFY]: must run from repository root (tools/azl_core_engine.c missing)" >&2
  exit 627
fi

if ! command -v gcc >/dev/null 2>&1; then
  echo "ERROR[AZL_CORE_ENGINE_VERIFY]: gcc not found" >&2
  exit 628
fi

mkdir -p .azl
if ! gcc -std=c11 -Wall -Wextra -Werror -O2 -pthread -I"${ROOT_DIR}/tools" \
  -DAZL_CORE_ENGINE_SELFTEST \
  tools/azl_core_engine.c tools/azl_bytecode.c tools/azl_compiler.c -o .azl/azl_core_engine_selftest; then
  echo "ERROR[AZL_CORE_ENGINE_VERIFY]: compile failed" >&2
  exit 629
fi

if ! ./.azl/azl_core_engine_selftest; then
  echo "ERROR[AZL_CORE_ENGINE_VERIFY]: selftest failed" >&2
  exit 630
fi

echo "verify_azl_core_engine: ok"
