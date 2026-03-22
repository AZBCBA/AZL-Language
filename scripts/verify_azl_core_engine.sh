#!/usr/bin/env bash
# Native core engine: compile tools/azl_core_engine.c + bytecode + compiler selftests.
# Verifies JSON bytecode (vm_hello_world.json + vm_emit_var.json), AZL compile (vm_hello.azl + vm_branch.azl), and VM exec.
# Native bytecode subset: no call/listen op names in JSON; VM rejects legacy opcode slots 4–5.
# Exit codes: docs/ERROR_SYSTEM.md § Native core engine selftest (627–632, 903).
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

# Native engine: compile-subset .azl (non-bootstrap) must default to in-process compile/vm lane without --use-native-core.
NATIVE_BIN="${ROOT_DIR}/.azl/bin/azl-native-engine"
if ! gcc -O2 -Wall -Wextra -pthread -I"${ROOT_DIR}/tools" \
  -o "$NATIVE_BIN" "${ROOT_DIR}/tools/azl_native_engine.c" "${ROOT_DIR}/tools/azl_core_engine.c" \
  "${ROOT_DIR}/tools/azl_native_engine_core_host.c" "${ROOT_DIR}/tools/azl_bytecode.c" \
  "${ROOT_DIR}/tools/azl_compiler.c"; then
  echo "ERROR[AZL_CORE_ENGINE_VERIFY]: azl-native-engine link failed" >&2
  exit 631
fi
chmod +x "$NATIVE_BIN"
VM_HELLO="${ROOT_DIR}/tools/testdata/vm_hello.azl"
if [ ! -f "$VM_HELLO" ]; then
  echo "ERROR[AZL_CORE_ENGINE_VERIFY]: missing $VM_HELLO" >&2
  exit 632
fi
LANE_LOG="${ROOT_DIR}/.azl/core_engine_lane_probe.log"
rm -f "$LANE_LOG"
set +e
if command -v timeout >/dev/null 2>&1; then
  AZL_BUILD_API_PORT=19988 timeout 2 "$NATIVE_BIN" "$VM_HELLO" 2>"$LANE_LOG"
else
  AZL_BUILD_API_PORT=19988 "$NATIVE_BIN" "$VM_HELLO" 2>"$LANE_LOG" &
  _npid=$!
  sleep 1
  kill -TERM "$_npid" 2>/dev/null || true
  wait "$_npid" 2>/dev/null || true
fi
set -e
if ! grep -Fq 'execution_lane=native_compile_vm' "$LANE_LOG"; then
  echo "ERROR[AZL_CORE_ENGINE_VERIFY]: expected stderr execution_lane=native_compile_vm for raw compile-subset .azl" >&2
  cat "$LANE_LOG" >&2 || true
  exit 903
fi

echo "verify_azl_core_engine: ok"
