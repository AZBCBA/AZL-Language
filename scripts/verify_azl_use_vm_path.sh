#!/usr/bin/env bash
# Static verification: AZL_USE_VM wiring documented and present in interpreter + daemon.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! rg -q "AZL_USE_VM" docs/AZL_NATIVE_RUNTIME_CONTRACT.md; then
  echo "ERROR: docs/AZL_NATIVE_RUNTIME_CONTRACT.md must document AZL_USE_VM" >&2
  exit 80
fi
if ! rg -q "vm_compile_ast" azl/runtime/interpreter/azl_interpreter.azl; then
  echo "ERROR: azl/runtime/interpreter/azl_interpreter.azl must define vm_compile_ast" >&2
  exit 81
fi
if ! rg -q "vm_run_bytecode_program" azl/runtime/interpreter/azl_interpreter.azl; then
  echo "ERROR: interpreter missing vm_run_bytecode_program" >&2
  exit 82
fi
if ! rg -q "AZL_USE_VM" scripts/run_enterprise_daemon.sh; then
  echo "ERROR: scripts/run_enterprise_daemon.sh should reference AZL_USE_VM when set" >&2
  exit 83
fi

echo "azl-use-vm-contract-ok"
