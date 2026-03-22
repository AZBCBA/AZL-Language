#!/usr/bin/env bash
# Native core engine: compile tools/azl_core_engine.c + bytecode + compiler selftests.
# Verifies JSON bytecode (vm_hello_world.json + vm_emit_var.json), AZL compile (vm_hello.azl + vm_branch.azl), VM exec,
# and native_vm_negative_and_edge_suite inside azl_compiler_selftest:
#   (1) compile fail: unknown var in if condition (compile_bad_cond_unknown.azl)
#   (2) compile fail: unknown var in emit payload (compile_bad_emit_unknown.azl)
#   (3) compile fail: if missing ')' (compile_bad_if_no_paren.azl)
#   (4) compile fail: if missing '{' (compile_bad_if_no_brace.azl)
#   (5) compile fail: emit map missing ':' (compile_bad_emit_no_colon.azl)
#   (6) compile fail: emit map missing '}' (compile_bad_emit_no_rbrace.azl)
#   (7) compile fail: set missing '=' / rhs (compile_bad_set_no_eq.azl, compile_bad_set_no_rhs.azl)
#   (8) vm_exec fail: jump_if_false target out of range (vm_bad_jump_target.json)
#   (9) vm_exec fail: load_var unset, emit_var unset slot, store_var slot out of range (vm_bad_*.json)
#   (10) else path: failure event + result=no, success must not fire (vm_branch_else.azl)
# Native bytecode subset: no call/listen op names in JSON; VM rejects legacy opcode slots 4–5.
# Exit codes: docs/ERROR_SYSTEM.md — Native core engine selftest (627–632, 903–904).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

err() {
  echo "ERROR[AZL_CORE_ENGINE_VERIFY]: $*" >&2
}

require_testdata() {
  local f="$ROOT_DIR/tools/testdata/$1"
  if [ ! -f "$f" ]; then
    err "missing required native-vm testdata: tools/testdata/$1"
    exit 904
  fi
}

if [ ! -f "Makefile" ] || [ ! -f "tools/azl_core_engine.c" ]; then
  err "must run from repository root (tools/azl_core_engine.c missing)"
  exit 627
fi

if ! command -v gcc >/dev/null 2>&1; then
  err "gcc not found"
  exit 628
fi

mkdir -p .azl
if ! gcc -std=c11 -Wall -Wextra -Werror -O2 -pthread -I"${ROOT_DIR}/tools" \
  -DAZL_CORE_ENGINE_SELFTEST \
  tools/azl_core_engine.c tools/azl_bytecode.c tools/azl_compiler.c -o .azl/azl_core_engine_selftest; then
  err "compile failed"
  exit 629
fi

for _td in \
  vm_branch_else.azl \
  compile_bad_cond_unknown.azl \
  compile_bad_emit_unknown.azl \
  compile_bad_if_no_paren.azl \
  compile_bad_if_no_brace.azl \
  compile_bad_emit_no_colon.azl \
  compile_bad_emit_no_rbrace.azl \
  compile_bad_set_no_eq.azl \
  compile_bad_set_no_rhs.azl \
  vm_bad_jump_target.json \
  vm_bad_load_unset.json \
  vm_bad_emit_var_unset.json \
  vm_bad_store_slot.json; do
  require_testdata "$_td"
done

SELFLOG="${ROOT_DIR}/.azl/core_engine_selftest.log"
rm -f "$SELFLOG"
set +e
./.azl/azl_core_engine_selftest >"$SELFLOG" 2>&1
_st=$?
set -e
if [ "$_st" -ne 0 ]; then
  err "azl_core_engine_selftest exited $_st"
  cat "$SELFLOG" >&2 || true
  exit 630
fi
if ! grep -Fq 'native_vm_negative_and_edge_suite: ok' "$SELFLOG"; then
  err "selftest log missing native_vm_negative_and_edge_suite: ok (negative suite not run?)"
  cat "$SELFLOG" >&2 || true
  exit 630
fi

# Native engine: compile-subset .azl (non-bootstrap) must default to in-process compile/vm lane without --use-native-core.
NATIVE_BIN="${ROOT_DIR}/.azl/bin/azl-native-engine"
if ! gcc -O2 -Wall -Wextra -pthread -I"${ROOT_DIR}/tools" \
  -o "$NATIVE_BIN" "${ROOT_DIR}/tools/azl_native_engine.c" "${ROOT_DIR}/tools/azl_core_engine.c" \
  "${ROOT_DIR}/tools/azl_native_engine_core_host.c" "${ROOT_DIR}/tools/azl_bytecode.c" \
  "${ROOT_DIR}/tools/azl_compiler.c"; then
  err "azl-native-engine link failed"
  exit 631
fi
chmod +x "$NATIVE_BIN"
VM_HELLO="${ROOT_DIR}/tools/testdata/vm_hello.azl"
if [ ! -f "$VM_HELLO" ]; then
  err "missing $VM_HELLO"
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
  err "expected stderr execution_lane=native_compile_vm for raw compile-subset .azl"
  cat "$LANE_LOG" >&2 || true
  exit 903
fi

echo "verify_azl_core_engine: ok"
exit 0
