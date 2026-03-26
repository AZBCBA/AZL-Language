#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "[gate] 0: release helper scripts (GitHub release path; bash -n + tag policy)"
bash scripts/self_check_release_helpers.sh

echo "[gate] A: native-only guard checks"
if ! rg -q "AZL_NATIVE_ONLY" scripts/start_azl_native_mode.sh; then
  echo "ERROR: start_azl_native_mode.sh is missing AZL_NATIVE_ONLY guard"
  exit 10
fi
echo "[gate] B: native script contract checks"
if [ ! -x "scripts/verify_native_runtime_live.sh" ]; then
  echo "ERROR: scripts/verify_native_runtime_live.sh is not executable"
  exit 12
fi
if [ ! -x "scripts/verify_enterprise_native_http_live.sh" ]; then
  echo "ERROR: scripts/verify_enterprise_native_http_live.sh is not executable"
  exit 16
fi
if [ ! -x "scripts/verify_quantum_lha3_stack.sh" ]; then
  echo "ERROR: scripts/verify_quantum_lha3_stack.sh is not executable"
  exit 13
fi
if [ ! -x "scripts/verify_azl_grammar_conformance.sh" ]; then
  echo "ERROR: scripts/verify_azl_grammar_conformance.sh is not executable"
  exit 14
fi
if [ ! -x "scripts/verify_azl_literal_codec_container_doc_contract.sh" ]; then
  echo "ERROR: scripts/verify_azl_literal_codec_container_doc_contract.sh is not executable"
  exit 15
fi
if [ ! -x "scripts/verify_azl_literal_codec_roundtrip.sh" ]; then
  echo "ERROR: scripts/verify_azl_literal_codec_roundtrip.sh is not executable"
  exit 39
fi

echo "[gate] C: compiler/vm contract checks"
required_tokens=(
  "JumpIfFalse"
  "Jump"
  "Call"
  "Return"
  "Store"
  "Pop"
  "Add"
  "Sub"
  "Mul"
  "Div"
)
for tok in "${required_tokens[@]}"; do
  if ! rg -q "$tok" "azl/runtime/vm/azl_vm.azl"; then
    echo "ERROR: VM contract missing opcode token: $tok"
    exit 19
  fi
done
echo "vm-opcodes-ok"

echo "[gate] D: native engine build + runtime command contract"
NATIVE_BIN="$(bash scripts/build_azl_native_engine.sh)"
if [ ! -x "$NATIVE_BIN" ]; then
  echo "ERROR: native engine binary was not built"
  exit 20
fi
if ! rg -q "missing AZL_NATIVE_RUNTIME_CMD" tools/azl_native_engine.c; then
  echo "ERROR: native engine is not enforcing AZL_NATIVE_RUNTIME_CMD"
  exit 21
fi
if ! rg -q "/api/llm/capabilities" tools/azl_native_engine.c; then
  echo "ERROR: native engine missing GET /api/llm/capabilities (native LLM honesty contract)"
  exit 22
fi

echo "[gate] F: C minimal interpreter — link, unquoted emit, listener dispatch"
bash scripts/build_azl_interpreter_minimal.sh >/dev/null
MINI_BIN="${ROOT_DIR}/.azl/bin/azl-interpreter-minimal"
if [ ! -x "$MINI_BIN" ]; then
  echo "ERROR: azl-interpreter-minimal not built at $MINI_BIN"
  exit 23
fi
set +e
MINI_OUT="$("$MINI_BIN" azl/tests/c_minimal_link_ping.azl boot.entry 2>&1)"
mini_rc=$?
set -e
if [ "$mini_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal c_minimal_link_ping exited $mini_rc: $MINI_OUT"
  exit 24
fi
if ! printf '%s\n' "$MINI_OUT" | rg -q 'C_MINIMAL_LINK_PING_OK'; then
  echo "ERROR: azl-interpreter-minimal expected C_MINIMAL_LINK_PING_OK in output, got: $MINI_OUT"
  exit 25
fi

echo "[gate] F2: Python semantic engine parity vs C minimal (same fixture)"
export PYTHONPATH="${ROOT_DIR}/tools${PYTHONPATH:+:${PYTHONPATH}}"
set +e
PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="${ROOT_DIR}/azl/tests/c_minimal_link_ping.azl" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
py_rc=$?
set -e
if [ "$py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host c_minimal_link_ping exited $py_rc: $PY_OUT"
  exit 26
fi
if [ "$MINI_OUT" != "$PY_OUT" ]; then
  echo "ERROR: C vs Python semantic output mismatch" >&2
  echo "C:    $MINI_OUT" >&2
  echo "Py:   $PY_OUT" >&2
  exit 27
fi

echo "[gate] F3: C vs Python — P0 interpreter slice (set + expr + if + [] + {} + link + say)"
SLICE="${ROOT_DIR}/azl/tests/p0_semantic_interpreter_slice.azl"
set +e
SLICE_C_OUT="$("$MINI_BIN" "$SLICE" boot.entry 2>&1)"
slice_c_rc=$?
set -e
if [ "$slice_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_interpreter_slice exited $slice_c_rc: $SLICE_C_OUT"
  exit 28
fi
if ! printf '%s\n' "$SLICE_C_OUT" | rg -q 'P0_SEMANTIC_INTERPRETER_SLICE_OK'; then
  echo "ERROR: expected P0_SEMANTIC_INTERPRETER_SLICE_OK in C output, got: $SLICE_C_OUT"
  exit 28
fi
set +e
SLICE_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$SLICE" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
slice_py_rc=$?
set -e
if [ "$slice_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_interpreter_slice exited $slice_py_rc: $SLICE_PY_OUT"
  exit 29
fi
if [ "$SLICE_C_OUT" != "$SLICE_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_interpreter_slice" >&2
  echo "C:  $SLICE_C_OUT" >&2
  echo "Py: $SLICE_PY_OUT" >&2
  exit 30
fi

echo "[gate] F4: C vs Python — nested listen in listener + emit flush (P0 interpret-shaped dispatch)"
NESTED="${ROOT_DIR}/azl/tests/p0_nested_listen_emit_chain.azl"
set +e
NESTED_C_OUT="$("$MINI_BIN" "$NESTED" boot.entry 2>&1)"
nested_c_rc=$?
set -e
if [ "$nested_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_nested_listen_emit_chain exited $nested_c_rc: $NESTED_C_OUT"
  exit 32
fi
if ! printf '%s\n' "$NESTED_C_OUT" | rg -q 'P0_NESTED_LISTEN_EMIT_CHAIN_OK'; then
  echo "ERROR: expected P0_NESTED_LISTEN_EMIT_CHAIN_OK in C output, got: $NESTED_C_OUT"
  exit 32
fi
set +e
NESTED_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$NESTED" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
nested_py_rc=$?
set -e
if [ "$nested_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_nested_listen_emit_chain exited $nested_py_rc: $NESTED_PY_OUT"
  exit 33
fi
if [ "$NESTED_C_OUT" != "$NESTED_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_nested_listen_emit_chain" >&2
  echo "C:  $NESTED_C_OUT" >&2
  echo "Py: $NESTED_PY_OUT" >&2
  exit 34
fi

echo "[gate] F5: C vs Python — P0 var alias (set ::dst = ::src, say ::dst)"
ALIAS="${ROOT_DIR}/azl/tests/p0_semantic_var_alias.azl"
set +e
ALIAS_C_OUT="$("$MINI_BIN" "$ALIAS" boot.entry 2>&1)"
alias_c_rc=$?
set -e
if [ "$alias_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_var_alias exited $alias_c_rc: $ALIAS_C_OUT"
  exit 35
fi
if ! printf '%s\n' "$ALIAS_C_OUT" | rg -q 'P0_SEMANTIC_VAR_ALIAS_OK'; then
  echo "ERROR: expected P0_SEMANTIC_VAR_ALIAS_OK in C output, got: $ALIAS_C_OUT"
  exit 35
fi
set +e
ALIAS_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$ALIAS" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
alias_py_rc=$?
set -e
if [ "$alias_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_var_alias exited $alias_py_rc: $ALIAS_PY_OUT"
  exit 36
fi
if [ "$ALIAS_C_OUT" != "$ALIAS_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_var_alias" >&2
  echo "C:  $ALIAS_C_OUT" >&2
  echo "Py: $ALIAS_PY_OUT" >&2
  exit 37
fi

echo "[gate] F6: C vs Python — P0 additive expressions (+) and == on sums"
PLUS="${ROOT_DIR}/azl/tests/p0_semantic_expr_plus_chain.azl"
set +e
PLUS_C_OUT="$("$MINI_BIN" "$PLUS" boot.entry 2>&1)"
plus_c_rc=$?
set -e
if [ "$plus_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_expr_plus_chain exited $plus_c_rc: $PLUS_C_OUT"
  exit 40
fi
if ! printf '%s\n' "$PLUS_C_OUT" | rg -q 'P0_SEMANTIC_EXPR_PLUS_OK'; then
  echo "ERROR: expected P0_SEMANTIC_EXPR_PLUS_OK in C output, got: $PLUS_C_OUT"
  exit 40
fi
set +e
PLUS_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$PLUS" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
plus_py_rc=$?
set -e
if [ "$plus_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_expr_plus_chain exited $plus_py_rc: $PLUS_PY_OUT"
  exit 41
fi
if [ "$PLUS_C_OUT" != "$PLUS_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_expr_plus_chain" >&2
  echo "C:  $PLUS_C_OUT" >&2
  echo "Py: $PLUS_PY_OUT" >&2
  exit 42
fi

echo "[gate] F7: C vs Python — dotted :: paths as single global key (perf.stats.tok_hits)"
DOT="${ROOT_DIR}/azl/tests/p0_semantic_dotted_counter.azl"
set +e
DOT_C_OUT="$("$MINI_BIN" "$DOT" boot.entry 2>&1)"
dot_c_rc=$?
set -e
if [ "$dot_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_dotted_counter exited $dot_c_rc: $DOT_C_OUT"
  exit 61
fi
if ! printf '%s\n' "$DOT_C_OUT" | rg -q 'P0_SEMANTIC_DOTTED_COUNTER_OK'; then
  echo "ERROR: expected P0_SEMANTIC_DOTTED_COUNTER_OK in C output, got: $DOT_C_OUT"
  exit 61
fi
set +e
DOT_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$DOT" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
dot_py_rc=$?
set -e
if [ "$dot_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_dotted_counter exited $dot_py_rc: $DOT_PY_OUT"
  exit 62
fi
if [ "$DOT_C_OUT" != "$DOT_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_dotted_counter" >&2
  echo "C:  $DOT_C_OUT" >&2
  echo "Py: $DOT_PY_OUT" >&2
  exit 63
fi

echo "[gate] F8: C vs Python — behavior listen for \"interpret\" + emit (interpreter-shaped)"
BEH="${ROOT_DIR}/azl/tests/p0_semantic_behavior_interpret_listen.azl"
set +e
BEH_C_OUT="$("$MINI_BIN" "$BEH" boot.entry 2>&1)"
beh_c_rc=$?
set -e
if [ "$beh_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_behavior_interpret_listen exited $beh_c_rc: $BEH_C_OUT"
  exit 64
fi
if ! printf '%s\n' "$BEH_C_OUT" | rg -q 'P0_SEMANTIC_BEHAVIOR_INTERPRET_OK'; then
  echo "ERROR: expected P0_SEMANTIC_BEHAVIOR_INTERPRET_OK in C output, got: $BEH_C_OUT"
  exit 64
fi
set +e
BEH_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$BEH" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
beh_py_rc=$?
set -e
if [ "$beh_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_behavior_interpret_listen exited $beh_py_rc: $BEH_PY_OUT"
  exit 65
fi
if [ "$BEH_C_OUT" != "$BEH_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_behavior_interpret_listen" >&2
  echo "C:  $BEH_C_OUT" >&2
  echo "Py: $BEH_PY_OUT" >&2
  exit 66
fi

echo "[gate] F9: C vs Python — behavior listen for \"interpret\" then { … }"
THEN="${ROOT_DIR}/azl/tests/p0_semantic_behavior_listen_then.azl"
set +e
THEN_C_OUT="$("$MINI_BIN" "$THEN" boot.entry 2>&1)"
then_c_rc=$?
set -e
if [ "$then_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_behavior_listen_then exited $then_c_rc: $THEN_C_OUT"
  exit 67
fi
if ! printf '%s\n' "$THEN_C_OUT" | rg -q 'P0_SEMANTIC_LISTEN_THEN_OK'; then
  echo "ERROR: expected P0_SEMANTIC_LISTEN_THEN_OK in C output, got: $THEN_C_OUT"
  exit 67
fi
set +e
THEN_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$THEN" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
then_py_rc=$?
set -e
if [ "$then_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_behavior_listen_then exited $then_py_rc: $THEN_PY_OUT"
  exit 68
fi
if [ "$THEN_C_OUT" != "$THEN_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_behavior_listen_then" >&2
  echo "C:  $THEN_C_OUT" >&2
  echo "Py: $THEN_PY_OUT" >&2
  exit 59
fi

echo "[gate] F10: C vs Python — emit with { … } → ::event.data.* in listener"
PLOAD="${ROOT_DIR}/azl/tests/p0_semantic_emit_event_payload.azl"
set +e
PLOAD_C_OUT="$("$MINI_BIN" "$PLOAD" boot.entry 2>&1)"
pload_c_rc=$?
set -e
if [ "$pload_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_emit_event_payload exited $pload_c_rc: $PLOAD_C_OUT"
  exit 111
fi
if ! printf '%s\n' "$PLOAD_C_OUT" | rg -q 'P0_SEMANTIC_EMIT_PAYLOAD_OK'; then
  echo "ERROR: expected P0_SEMANTIC_EMIT_PAYLOAD_OK in C output, got: $PLOAD_C_OUT"
  exit 111
fi
if ! printf '%s\n' "$PLOAD_C_OUT" | rg -q 'spine-f10'; then
  echo "ERROR: expected payload trace spine-f10 in C output, got: $PLOAD_C_OUT"
  exit 111
fi
set +e
PLOAD_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$PLOAD" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
pload_py_rc=$?
set -e
if [ "$pload_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_emit_event_payload exited $pload_py_rc: $PLOAD_PY_OUT"
  exit 112
fi
if [ "$PLOAD_C_OUT" != "$PLOAD_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_emit_event_payload" >&2
  echo "C:  $PLOAD_C_OUT" >&2
  echo "Py: $PLOAD_PY_OUT" >&2
  exit 113
fi

echo "[gate] F11: C vs Python — emit with { k: v, k2: v2 } (multi-key payload)"
MULTI="${ROOT_DIR}/azl/tests/p0_semantic_emit_multi_payload.azl"
set +e
MULTI_C_OUT="$("$MINI_BIN" "$MULTI" boot.entry 2>&1)"
multi_c_rc=$?
set -e
if [ "$multi_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_emit_multi_payload exited $multi_c_rc: $MULTI_C_OUT"
  exit 114
fi
if ! printf '%s\n' "$MULTI_C_OUT" | rg -q 'P0_SEMANTIC_EMIT_MULTI_OK'; then
  echo "ERROR: expected P0_SEMANTIC_EMIT_MULTI_OK in C output, got: $MULTI_C_OUT"
  exit 114
fi
if ! printf '%s\n' "$MULTI_C_OUT" | rg -q 'spine-f11a'; then
  echo "ERROR: expected payload trace spine-f11a in C output, got: $MULTI_C_OUT"
  exit 114
fi
if ! printf '%s\n' "$MULTI_C_OUT" | rg -q 'spine-f11b'; then
  echo "ERROR: expected payload job spine-f11b in C output, got: $MULTI_C_OUT"
  exit 114
fi
set +e
MULTI_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$MULTI" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
multi_py_rc=$?
set -e
if [ "$multi_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_emit_multi_payload exited $multi_py_rc: $MULTI_PY_OUT"
  exit 115
fi
if [ "$MULTI_C_OUT" != "$MULTI_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_emit_multi_payload" >&2
  echo "C:  $MULTI_C_OUT" >&2
  echo "Py: $MULTI_PY_OUT" >&2
  exit 116
fi

echo "[gate] F12: C vs Python — two emits with payloads in one init (queue order)"
QUEUED="${ROOT_DIR}/azl/tests/p0_semantic_emit_queued_payloads.azl"
set +e
QUEUED_C_OUT="$("$MINI_BIN" "$QUEUED" boot.entry 2>&1)"
queued_c_rc=$?
set -e
if [ "$queued_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_emit_queued_payloads exited $queued_c_rc: $QUEUED_C_OUT"
  exit 117
fi
if ! printf '%s\n' "$QUEUED_C_OUT" | rg -q 'P0_SEMANTIC_EMIT_QUEUED_OK'; then
  echo "ERROR: expected P0_SEMANTIC_EMIT_QUEUED_OK in C output, got: $QUEUED_C_OUT"
  exit 117
fi
if ! printf '%s\n' "$QUEUED_C_OUT" | rg -q 'spine-f12a'; then
  echo "ERROR: expected first payload spine-f12a in C output, got: $QUEUED_C_OUT"
  exit 117
fi
if ! printf '%s\n' "$QUEUED_C_OUT" | rg -q 'spine-f12b'; then
  echo "ERROR: expected second payload spine-f12b in C output, got: $QUEUED_C_OUT"
  exit 117
fi
if ! printf '%s\n' "$QUEUED_C_OUT" | rg -q 'P12_AFTER_FIRST'; then
  echo "ERROR: expected P12_AFTER_FIRST in C output, got: $QUEUED_C_OUT"
  exit 117
fi
if ! printf '%s\n' "$QUEUED_C_OUT" | rg -q 'P12_AFTER_SECOND'; then
  echo "ERROR: expected P12_AFTER_SECOND in C output, got: $QUEUED_C_OUT"
  exit 117
fi
set +e
QUEUED_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$QUEUED" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
queued_py_rc=$?
set -e
if [ "$queued_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_emit_queued_payloads exited $queued_py_rc: $QUEUED_PY_OUT"
  exit 118
fi
if [ "$QUEUED_C_OUT" != "$QUEUED_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_emit_queued_payloads" >&2
  echo "C:  $QUEUED_C_OUT" >&2
  echo "Py: $QUEUED_PY_OUT" >&2
  exit 119
fi

echo "[gate] F13: C vs Python — ::event.data.* in set RHS (+ chain) in listener"
PEX="${ROOT_DIR}/azl/tests/p0_semantic_payload_expr_chain.azl"
set +e
PEX_C_OUT="$("$MINI_BIN" "$PEX" boot.entry 2>&1)"
pex_c_rc=$?
set -e
if [ "$pex_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_payload_expr_chain exited $pex_c_rc: $PEX_C_OUT"
  exit 120
fi
if ! printf '%s\n' "$PEX_C_OUT" | rg -q 'P0_SEMANTIC_PAYLOAD_EXPR_OK'; then
  echo "ERROR: expected P0_SEMANTIC_PAYLOAD_EXPR_OK in C output, got: $PEX_C_OUT"
  exit 120
fi
if ! printf '%s\n' "$PEX_C_OUT" | rg -q 'spine-f13-sfx'; then
  echo "ERROR: expected concat line spine-f13-sfx in C output, got: $PEX_C_OUT"
  exit 120
fi
set +e
PEX_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$PEX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
pex_py_rc=$?
set -e
if [ "$pex_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_payload_expr_chain exited $pex_py_rc: $PEX_PY_OUT"
  exit 121
fi
if [ "$PEX_C_OUT" != "$PEX_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_payload_expr_chain" >&2
  echo "C:  $PEX_C_OUT" >&2
  echo "Py: $PEX_PY_OUT" >&2
  exit 122
fi

echo "[gate] F14: C vs Python — if condition uses ::event.data.* (listener)"
PIF="${ROOT_DIR}/azl/tests/p0_semantic_payload_if_branch.azl"
set +e
PIF_C_OUT="$("$MINI_BIN" "$PIF" boot.entry 2>&1)"
pif_c_rc=$?
set -e
if [ "$pif_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_payload_if_branch exited $pif_c_rc: $PIF_C_OUT"
  exit 123
fi
if ! printf '%s\n' "$PIF_C_OUT" | rg -q 'P0_SEMANTIC_PAYLOAD_IF_OK'; then
  echo "ERROR: expected P0_SEMANTIC_PAYLOAD_IF_OK in C output, got: $PIF_C_OUT"
  exit 123
fi
if ! printf '%s\n' "$PIF_C_OUT" | rg -q 'branch-strict'; then
  echo "ERROR: expected branch-strict in C output, got: $PIF_C_OUT"
  exit 123
fi
set +e
PIF_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$PIF" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
pif_py_rc=$?
set -e
if [ "$pif_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_payload_if_branch exited $pif_py_rc: $PIF_PY_OUT"
  exit 124
fi
if [ "$PIF_C_OUT" != "$PIF_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_payload_if_branch" >&2
  echo "C:  $PIF_C_OUT" >&2
  echo "Py: $PIF_PY_OUT" >&2
  exit 125
fi

echo "[gate] F15: C vs Python — nested emit + inner with { }; outer payload other keys survive"
NEST="${ROOT_DIR}/azl/tests/p0_semantic_nested_emit_payload.azl"
set +e
NEST_C_OUT="$("$MINI_BIN" "$NEST" boot.entry 2>&1)"
nest_c_rc=$?
set -e
if [ "$nest_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_nested_emit_payload exited $nest_c_rc: $NEST_C_OUT"
  exit 126
fi
if ! printf '%s\n' "$NEST_C_OUT" | rg -q 'P0_SEMANTIC_NESTED_EMIT_OK'; then
  echo "ERROR: expected P0_SEMANTIC_NESTED_EMIT_OK in C output, got: $NEST_C_OUT"
  exit 126
fi
if ! printf '%s\n' "$NEST_C_OUT" | rg -q 'nested-val'; then
  echo "ERROR: expected nested-val in C output, got: $NEST_C_OUT"
  exit 126
fi
if ! printf '%s\n' "$NEST_C_OUT" | rg -q 'hold'; then
  echo "ERROR: expected outer stage hold in C output, got: $NEST_C_OUT"
  exit 126
fi
set +e
NEST_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$NEST" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
nest_py_rc=$?
set -e
if [ "$nest_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_nested_emit_payload exited $nest_py_rc: $NEST_PY_OUT"
  exit 127
fi
if [ "$NEST_C_OUT" != "$NEST_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_nested_emit_payload" >&2
  echo "C:  $NEST_C_OUT" >&2
  echo "Py: $NEST_PY_OUT" >&2
  exit 128
fi

echo "[gate] F16: C vs Python — emit \"ev\" with { … } (quoted event name + payload)"
QEM="${ROOT_DIR}/azl/tests/p0_semantic_quoted_emit_with_payload.azl"
set +e
QEM_C_OUT="$("$MINI_BIN" "$QEM" boot.entry 2>&1)"
qem_c_rc=$?
set -e
if [ "$qem_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_quoted_emit_with_payload exited $qem_c_rc: $QEM_C_OUT"
  exit 129
fi
if ! printf '%s\n' "$QEM_C_OUT" | rg -q 'P0_SEMANTIC_QUOTED_EMIT_OK'; then
  echo "ERROR: expected P0_SEMANTIC_QUOTED_EMIT_OK in C output, got: $QEM_C_OUT"
  exit 129
fi
if ! printf '%s\n' "$QEM_C_OUT" | rg -q 'quoted-id'; then
  echo "ERROR: expected quoted-id in C output, got: $QEM_C_OUT"
  exit 129
fi
set +e
QEM_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$QEM" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
qem_py_rc=$?
set -e
if [ "$qem_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_quoted_emit_with_payload exited $qem_py_rc: $QEM_PY_OUT"
  exit 130
fi
if [ "$QEM_C_OUT" != "$QEM_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_quoted_emit_with_payload" >&2
  echo "C:  $QEM_C_OUT" >&2
  echo "Py: $QEM_PY_OUT" >&2
  exit 131
fi

echo "[gate] F17: C vs Python — if ::event.data.* != literal"
PNE="${ROOT_DIR}/azl/tests/p0_semantic_payload_ne_branch.azl"
set +e
PNE_C_OUT="$("$MINI_BIN" "$PNE" boot.entry 2>&1)"
pne_c_rc=$?
set -e
if [ "$pne_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_payload_ne_branch exited $pne_c_rc: $PNE_C_OUT"
  exit 132
fi
if ! printf '%s\n' "$PNE_C_OUT" | rg -q 'P0_SEMANTIC_PAYLOAD_NE_OK'; then
  echo "ERROR: expected P0_SEMANTIC_PAYLOAD_NE_OK in C output, got: $PNE_C_OUT"
  exit 132
fi
if ! printf '%s\n' "$PNE_C_OUT" | rg -q 'not-loose'; then
  echo "ERROR: expected not-loose in C output, got: $PNE_C_OUT"
  exit 132
fi
set +e
PNE_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$PNE" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
pne_py_rc=$?
set -e
if [ "$pne_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_payload_ne_branch exited $pne_py_rc: $PNE_PY_OUT"
  exit 133
fi
if [ "$PNE_C_OUT" != "$PNE_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_payload_ne_branch" >&2
  echo "C:  $PNE_C_OUT" >&2
  echo "Py: $PNE_PY_OUT" >&2
  exit 134
fi

echo "[gate] F18: C vs Python — ::event.data missing key + or fallback in set"
POR="${ROOT_DIR}/azl/tests/p0_semantic_payload_or_fallback.azl"
set +e
POR_C_OUT="$("$MINI_BIN" "$POR" boot.entry 2>&1)"
por_c_rc=$?
set -e
if [ "$por_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_payload_or_fallback exited $por_c_rc: $POR_C_OUT"
  exit 135
fi
if ! printf '%s\n' "$POR_C_OUT" | rg -q 'P0_SEMANTIC_PAYLOAD_OR_OK'; then
  echo "ERROR: expected P0_SEMANTIC_PAYLOAD_OR_OK in C output, got: $POR_C_OUT"
  exit 135
fi
if ! printf '%s\n' "$POR_C_OUT" | rg -q 'fallback'; then
  echo "ERROR: expected fallback in C output, got: $POR_C_OUT"
  exit 135
fi
set +e
POR_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$POR" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
por_py_rc=$?
set -e
if [ "$por_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_payload_or_fallback exited $por_py_rc: $POR_PY_OUT"
  exit 136
fi
if [ "$POR_C_OUT" != "$POR_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_payload_or_fallback" >&2
  echo "C:  $POR_C_OUT" >&2
  echo "Py: $POR_PY_OUT" >&2
  exit 137
fi

echo "[gate] F19: C vs Python — emit with { } (empty payload)"
EWITH="${ROOT_DIR}/azl/tests/p0_semantic_emit_empty_with.azl"
set +e
EWITH_C_OUT="$("$MINI_BIN" "$EWITH" boot.entry 2>&1)"
ewith_c_rc=$?
set -e
if [ "$ewith_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_emit_empty_with exited $ewith_c_rc: $EWITH_C_OUT"
  exit 138
fi
if ! printf '%s\n' "$EWITH_C_OUT" | rg -q 'P0_SEMANTIC_EMPTY_WITH_OK'; then
  echo "ERROR: expected P0_SEMANTIC_EMPTY_WITH_OK in C output, got: $EWITH_C_OUT"
  exit 138
fi
set +e
EWITH_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$EWITH" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
ewith_py_rc=$?
set -e
if [ "$ewith_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_emit_empty_with exited $ewith_py_rc: $EWITH_PY_OUT"
  exit 139
fi
if [ "$EWITH_C_OUT" != "$EWITH_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_emit_empty_with" >&2
  echo "C:  $EWITH_C_OUT" >&2
  echo "Py: $EWITH_PY_OUT" >&2
  exit 140
fi

echo "[gate] F20: C vs Python — payload value in single quotes"
SQ="${ROOT_DIR}/azl/tests/p0_semantic_payload_single_quote.azl"
set +e
SQ_C_OUT="$("$MINI_BIN" "$SQ" boot.entry 2>&1)"
sq_c_rc=$?
set -e
if [ "$sq_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_payload_single_quote exited $sq_c_rc: $SQ_C_OUT"
  exit 141
fi
if ! printf '%s\n' "$SQ_C_OUT" | rg -q 'P0_SEMANTIC_SQUOTE_PAYLOAD_OK'; then
  echo "ERROR: expected P0_SEMANTIC_SQUOTE_PAYLOAD_OK in C output, got: $SQ_C_OUT"
  exit 141
fi
if ! printf '%s\n' "$SQ_C_OUT" | rg -q 'sq-val'; then
  echo "ERROR: expected sq-val in C output, got: $SQ_C_OUT"
  exit 141
fi
set +e
SQ_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$SQ" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
sq_py_rc=$?
set -e
if [ "$sq_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_payload_single_quote exited $sq_py_rc: $SQ_PY_OUT"
  exit 142
fi
if [ "$SQ_C_OUT" != "$SQ_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_payload_single_quote" >&2
  echo "C:  $SQ_C_OUT" >&2
  echo "Py: $SQ_PY_OUT" >&2
  exit 143
fi

echo "[gate] F21: C vs Python — same payload key outer/inner (trace overwrite + clear)"
COLL="${ROOT_DIR}/azl/tests/p0_semantic_payload_key_collide.azl"
set +e
COLL_C_OUT="$("$MINI_BIN" "$COLL" boot.entry 2>&1)"
coll_c_rc=$?
set -e
if [ "$coll_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_payload_key_collide exited $coll_c_rc: $COLL_C_OUT"
  exit 144
fi
if ! printf '%s\n' "$COLL_C_OUT" | rg -q 'P0_SEMANTIC_PAYLOAD_KEY_COLLIDE_OK'; then
  echo "ERROR: expected P0_SEMANTIC_PAYLOAD_KEY_COLLIDE_OK in C output, got: $COLL_C_OUT"
  exit 144
fi
if ! printf '%s\n' "$COLL_C_OUT" | rg -q 'outer-val'; then
  echo "ERROR: expected outer-val in C output, got: $COLL_C_OUT"
  exit 144
fi
if ! printf '%s\n' "$COLL_C_OUT" | rg -q 'inner-val'; then
  echo "ERROR: expected inner-val in C output, got: $COLL_C_OUT"
  exit 144
fi
set +e
COLL_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$COLL" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
coll_py_rc=$?
set -e
if [ "$coll_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_payload_key_collide exited $coll_py_rc: $COLL_PY_OUT"
  exit 145
fi
if [ "$COLL_C_OUT" != "$COLL_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_payload_key_collide" >&2
  echo "C:  $COLL_C_OUT" >&2
  echo "Py: $COLL_PY_OUT" >&2
  exit 146
fi

echo "[gate] F22: C vs Python — nested listen in listener + emit with payload"
NLIS="${ROOT_DIR}/azl/tests/p0_semantic_nested_listen_emit_payload.azl"
set +e
NLIS_C_OUT="$("$MINI_BIN" "$NLIS" boot.entry 2>&1)"
nlis_c_rc=$?
set -e
if [ "$nlis_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_nested_listen_emit_payload exited $nlis_c_rc: $NLIS_C_OUT"
  exit 147
fi
if ! printf '%s\n' "$NLIS_C_OUT" | rg -q 'P0_SEMANTIC_NESTED_LISTEN_PAYLOAD_OK'; then
  echo "ERROR: expected P0_SEMANTIC_NESTED_LISTEN_PAYLOAD_OK in C output, got: $NLIS_C_OUT"
  exit 147
fi
if ! printf '%s\n' "$NLIS_C_OUT" | rg -q 'nested-reg'; then
  echo "ERROR: expected nested-reg in C output, got: $NLIS_C_OUT"
  exit 147
fi
if ! printf '%s\n' "$NLIS_C_OUT" | rg -q 'P22_CHILD_OK'; then
  echo "ERROR: expected P22_CHILD_OK in C output, got: $NLIS_C_OUT"
  exit 147
fi
set +e
NLIS_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$NLIS" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
nlis_py_rc=$?
set -e
if [ "$nlis_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_nested_listen_emit_payload exited $nlis_py_rc: $NLIS_PY_OUT"
  exit 148
fi
if [ "$NLIS_C_OUT" != "$NLIS_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_nested_listen_emit_payload" >&2
  echo "C:  $NLIS_C_OUT" >&2
  echo "Py: $NLIS_PY_OUT" >&2
  exit 149
fi

echo "[gate] F23: C vs Python — nested listen … then + emit with payload"
NTHEN="${ROOT_DIR}/azl/tests/p0_semantic_nested_listen_then_payload.azl"
set +e
NTHEN_C_OUT="$("$MINI_BIN" "$NTHEN" boot.entry 2>&1)"
nthen_c_rc=$?
set -e
if [ "$nthen_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_nested_listen_then_payload exited $nthen_c_rc: $NTHEN_C_OUT"
  exit 150
fi
if ! printf '%s\n' "$NTHEN_C_OUT" | rg -q 'P0_SEMANTIC_NESTED_LISTEN_THEN_OK'; then
  echo "ERROR: expected P0_SEMANTIC_NESTED_LISTEN_THEN_OK in C output, got: $NTHEN_C_OUT"
  exit 150
fi
if ! printf '%s\n' "$NTHEN_C_OUT" | rg -q 'then-payload'; then
  echo "ERROR: expected then-payload in C output, got: $NTHEN_C_OUT"
  exit 150
fi
set +e
NTHEN_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$NTHEN" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
nthen_py_rc=$?
set -e
if [ "$nthen_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_nested_listen_then_payload exited $nthen_py_rc: $NTHEN_PY_OUT"
  exit 151
fi
if [ "$NTHEN_C_OUT" != "$NTHEN_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_nested_listen_then_payload" >&2
  echo "C:  $NTHEN_C_OUT" >&2
  echo "Py: $NTHEN_PY_OUT" >&2
  exit 152
fi

echo "[gate] F24: C vs Python — payload bare integer value"
PNUM="${ROOT_DIR}/azl/tests/p0_semantic_payload_numeric_value.azl"
set +e
PNUM_C_OUT="$("$MINI_BIN" "$PNUM" boot.entry 2>&1)"
pnum_c_rc=$?
set -e
if [ "$pnum_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_payload_numeric_value exited $pnum_c_rc: $PNUM_C_OUT"
  exit 153
fi
if ! printf '%s\n' "$PNUM_C_OUT" | rg -q 'P0_SEMANTIC_PAYLOAD_NUM_OK'; then
  echo "ERROR: expected P0_SEMANTIC_PAYLOAD_NUM_OK in C output, got: $PNUM_C_OUT"
  exit 153
fi
if ! printf '%s\n' "$PNUM_C_OUT" | rg -q '^42$'; then
  echo "ERROR: expected line 42 in C output, got: $PNUM_C_OUT"
  exit 153
fi
set +e
PNUM_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$PNUM" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
pnum_py_rc=$?
set -e
if [ "$pnum_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_payload_numeric_value exited $pnum_py_rc: $PNUM_PY_OUT"
  exit 154
fi
if [ "$PNUM_C_OUT" != "$PNUM_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_payload_numeric_value" >&2
  echo "C:  $PNUM_C_OUT" >&2
  echo "Py: $PNUM_PY_OUT" >&2
  exit 155
fi

echo "[gate] F25: C vs Python — link from inside listener"
LKL="${ROOT_DIR}/azl/tests/p0_semantic_link_in_listener.azl"
set +e
LKL_C_OUT="$("$MINI_BIN" "$LKL" boot.entry 2>&1)"
lkl_c_rc=$?
set -e
if [ "$lkl_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_link_in_listener exited $lkl_c_rc: $LKL_C_OUT"
  exit 156
fi
if ! printf '%s\n' "$LKL_C_OUT" | rg -q 'P0_SEMANTIC_LINK_IN_LISTENER_OK'; then
  echo "ERROR: expected P0_SEMANTIC_LINK_IN_LISTENER_OK in C output, got: $LKL_C_OUT"
  exit 156
fi
if ! printf '%s\n' "$LKL_C_OUT" | rg -q 'F25_LINKED_INIT'; then
  echo "ERROR: expected F25_LINKED_INIT in C output, got: $LKL_C_OUT"
  exit 156
fi
if ! printf '%s\n' "$LKL_C_OUT" | rg -q 'F25_H_OK'; then
  echo "ERROR: expected F25_H_OK in C output, got: $LKL_C_OUT"
  exit 156
fi
set +e
LKL_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$LKL" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
lkl_py_rc=$?
set -e
if [ "$lkl_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_link_in_listener exited $lkl_py_rc: $LKL_PY_OUT"
  exit 157
fi
if [ "$LKL_C_OUT" != "$LKL_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_link_in_listener" >&2
  echo "C:  $LKL_C_OUT" >&2
  echo "Py: $LKL_PY_OUT" >&2
  exit 158
fi

echo "[gate] F26: C vs Python — payload bare boolean true"
PBT="${ROOT_DIR}/azl/tests/p0_semantic_payload_bool_true.azl"
set +e
PBT_C_OUT="$("$MINI_BIN" "$PBT" boot.entry 2>&1)"
pbt_c_rc=$?
set -e
if [ "$pbt_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_payload_bool_true exited $pbt_c_rc: $PBT_C_OUT"
  exit 159
fi
if ! printf '%s\n' "$PBT_C_OUT" | rg -q 'P0_SEMANTIC_PAYLOAD_BOOL_TRUE_OK'; then
  echo "ERROR: expected P0_SEMANTIC_PAYLOAD_BOOL_TRUE_OK in C output, got: $PBT_C_OUT"
  exit 159
fi
if ! printf '%s\n' "$PBT_C_OUT" | rg -q '^true$'; then
  echo "ERROR: expected line true in C output, got: $PBT_C_OUT"
  exit 159
fi
set +e
PBT_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$PBT" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
pbt_py_rc=$?
set -e
if [ "$pbt_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_payload_bool_true exited $pbt_py_rc: $PBT_PY_OUT"
  exit 160
fi
if [ "$PBT_C_OUT" != "$PBT_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_payload_bool_true" >&2
  echo "C:  $PBT_C_OUT" >&2
  echo "Py: $PBT_PY_OUT" >&2
  exit 161
fi

echo "[gate] F27: C vs Python — nested listen + inner emit with two keys"
NMK="${ROOT_DIR}/azl/tests/p0_semantic_nested_multikey_payload.azl"
set +e
NMK_C_OUT="$("$MINI_BIN" "$NMK" boot.entry 2>&1)"
nmk_c_rc=$?
set -e
if [ "$nmk_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_nested_multikey_payload exited $nmk_c_rc: $NMK_C_OUT"
  exit 162
fi
if ! printf '%s\n' "$NMK_C_OUT" | rg -q 'P0_SEMANTIC_NESTED_MULTIKEY_OK'; then
  echo "ERROR: expected P0_SEMANTIC_NESTED_MULTIKEY_OK in C output, got: $NMK_C_OUT"
  exit 162
fi
if ! printf '%s\n' "$NMK_C_OUT" | rg -q 'P27_INNER_OK'; then
  echo "ERROR: expected P27_INNER_OK in C output, got: $NMK_C_OUT"
  exit 162
fi
if ! printf '%s\n' "$NMK_C_OUT" | rg -q '^one$'; then
  echo "ERROR: expected line one in C output, got: $NMK_C_OUT"
  exit 162
fi
if ! printf '%s\n' "$NMK_C_OUT" | rg -q '^two$'; then
  echo "ERROR: expected line two in C output, got: $NMK_C_OUT"
  exit 162
fi
set +e
NMK_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$NMK" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
nmk_py_rc=$?
set -e
if [ "$nmk_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_nested_multikey_payload exited $nmk_py_rc: $NMK_PY_OUT"
  exit 163
fi
if [ "$NMK_C_OUT" != "$NMK_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_nested_multikey_payload" >&2
  echo "C:  $NMK_C_OUT" >&2
  echo "Py: $NMK_PY_OUT" >&2
  exit 164
fi

echo "[gate] F28: C vs Python — payload bare boolean false"
PBF="${ROOT_DIR}/azl/tests/p0_semantic_payload_bool_false.azl"
set +e
PBF_C_OUT="$("$MINI_BIN" "$PBF" boot.entry 2>&1)"
pbf_c_rc=$?
set -e
if [ "$pbf_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_payload_bool_false exited $pbf_c_rc: $PBF_C_OUT"
  exit 165
fi
if ! printf '%s\n' "$PBF_C_OUT" | rg -q 'P0_SEMANTIC_PAYLOAD_BOOL_FALSE_OK'; then
  echo "ERROR: expected P0_SEMANTIC_PAYLOAD_BOOL_FALSE_OK in C output, got: $PBF_C_OUT"
  exit 165
fi
if ! printf '%s\n' "$PBF_C_OUT" | rg -q '^false$'; then
  echo "ERROR: expected line false in C output, got: $PBF_C_OUT"
  exit 165
fi
set +e
PBF_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$PBF" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
pbf_py_rc=$?
set -e
if [ "$pbf_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_payload_bool_false exited $pbf_py_rc: $PBF_PY_OUT"
  exit 166
fi
if [ "$PBF_C_OUT" != "$PBF_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_payload_bool_false" >&2
  echo "C:  $PBF_C_OUT" >&2
  echo "Py: $PBF_PY_OUT" >&2
  exit 167
fi

echo "[gate] F29: C vs Python — payload bare null (literal null line)"
PNV="${ROOT_DIR}/azl/tests/p0_semantic_payload_null_value.azl"
set +e
PNV_C_OUT="$("$MINI_BIN" "$PNV" boot.entry 2>&1)"
pnv_c_rc=$?
set -e
if [ "$pnv_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_payload_null_value exited $pnv_c_rc: $PNV_C_OUT"
  exit 168
fi
if ! printf '%s\n' "$PNV_C_OUT" | rg -q 'P0_SEMANTIC_PAYLOAD_NULL_OK'; then
  echo "ERROR: expected P0_SEMANTIC_PAYLOAD_NULL_OK in C output, got: $PNV_C_OUT"
  exit 168
fi
if ! printf '%s\n' "$PNV_C_OUT" | rg -q '^null$'; then
  echo "ERROR: expected line null in C output, got: $PNV_C_OUT"
  exit 168
fi
set +e
PNV_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$PNV" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
pnv_py_rc=$?
set -e
if [ "$pnv_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_payload_null_value exited $pnv_py_rc: $PNV_PY_OUT"
  exit 169
fi
if [ "$PNV_C_OUT" != "$PNV_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_payload_null_value" >&2
  echo "C:  $PNV_C_OUT" >&2
  echo "Py: $PNV_PY_OUT" >&2
  exit 170
fi

echo "[gate] F30: C vs Python — duplicate listen for same event (first wins)"
FML="${ROOT_DIR}/azl/tests/p0_semantic_first_matching_listener.azl"
set +e
FML_C_OUT="$("$MINI_BIN" "$FML" boot.entry 2>&1)"
fml_c_rc=$?
set -e
if [ "$fml_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_first_matching_listener exited $fml_c_rc: $FML_C_OUT"
  exit 171
fi
if ! printf '%s\n' "$FML_C_OUT" | rg -q 'P0_SEMANTIC_FIRST_LISTENER_OK'; then
  echo "ERROR: expected P0_SEMANTIC_FIRST_LISTENER_OK in C output, got: $FML_C_OUT"
  exit 171
fi
if ! printf '%s\n' "$FML_C_OUT" | rg -q '^FIRST$'; then
  echo "ERROR: expected line FIRST in C output, got: $FML_C_OUT"
  exit 171
fi
if printf '%s\n' "$FML_C_OUT" | rg -q '^SECOND$'; then
  echo "ERROR: did not expect SECOND (second listener must not run), got: $FML_C_OUT"
  exit 171
fi
set +e
FML_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$FML" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
fml_py_rc=$?
set -e
if [ "$fml_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_first_matching_listener exited $fml_py_rc: $FML_PY_OUT"
  exit 172
fi
if [ "$FML_C_OUT" != "$FML_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_first_matching_listener" >&2
  echo "C:  $FML_C_OUT" >&2
  echo "Py: $FML_PY_OUT" >&2
  exit 173
fi

echo "[gate] F31: C vs Python — payload bare float"
PFV="${ROOT_DIR}/azl/tests/p0_semantic_payload_float_value.azl"
set +e
PFV_C_OUT="$("$MINI_BIN" "$PFV" boot.entry 2>&1)"
pfv_c_rc=$?
set -e
if [ "$pfv_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_payload_float_value exited $pfv_c_rc: $PFV_C_OUT"
  exit 174
fi
if ! printf '%s\n' "$PFV_C_OUT" | rg -q 'P0_SEMANTIC_PAYLOAD_FLOAT_OK'; then
  echo "ERROR: expected P0_SEMANTIC_PAYLOAD_FLOAT_OK in C output, got: $PFV_C_OUT"
  exit 174
fi
if ! printf '%s\n' "$PFV_C_OUT" | rg -q '^3\.14$'; then
  echo "ERROR: expected line 3.14 in C output, got: $PFV_C_OUT"
  exit 174
fi
set +e
PFV_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$PFV" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
pfv_py_rc=$?
set -e
if [ "$pfv_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_payload_float_value exited $pfv_py_rc: $PFV_PY_OUT"
  exit 175
fi
if [ "$PFV_C_OUT" != "$PFV_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_payload_float_value" >&2
  echo "C:  $PFV_C_OUT" >&2
  echo "Py: $PFV_PY_OUT" >&2
  exit 176
fi

echo "[gate] F32: C vs Python — absent payload key == null in listener"
PMN="${ROOT_DIR}/azl/tests/p0_semantic_payload_missing_eq_null.azl"
set +e
PMN_C_OUT="$("$MINI_BIN" "$PMN" boot.entry 2>&1)"
pmn_c_rc=$?
set -e
if [ "$pmn_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_payload_missing_eq_null exited $pmn_c_rc: $PMN_C_OUT"
  exit 177
fi
if ! printf '%s\n' "$PMN_C_OUT" | rg -q 'F32_ABSENT_EQ_NULL'; then
  echo "ERROR: expected F32_ABSENT_EQ_NULL in C output, got: $PMN_C_OUT"
  exit 177
fi
if ! printf '%s\n' "$PMN_C_OUT" | rg -q 'P0_SEMANTIC_PAYLOAD_MISSING_EQ_NULL_OK'; then
  echo "ERROR: expected P0_SEMANTIC_PAYLOAD_MISSING_EQ_NULL_OK in C output, got: $PMN_C_OUT"
  exit 177
fi
set +e
PMN_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$PMN" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
pmn_py_rc=$?
set -e
if [ "$pmn_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_payload_missing_eq_null exited $pmn_py_rc: $PMN_PY_OUT"
  exit 178
fi
if [ "$PMN_C_OUT" != "$PMN_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_payload_missing_eq_null" >&2
  echo "C:  $PMN_C_OUT" >&2
  echo "Py: $PMN_PY_OUT" >&2
  exit 179
fi

echo "[gate] F33: C vs Python — payload multi-digit bare integer"
PBI="${ROOT_DIR}/azl/tests/p0_semantic_payload_big_int.azl"
set +e
PBI_C_OUT="$("$MINI_BIN" "$PBI" boot.entry 2>&1)"
pbi_c_rc=$?
set -e
if [ "$pbi_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_payload_big_int exited $pbi_c_rc: $PBI_C_OUT"
  exit 180
fi
if ! printf '%s\n' "$PBI_C_OUT" | rg -q 'P0_SEMANTIC_PAYLOAD_BIG_INT_OK'; then
  echo "ERROR: expected P0_SEMANTIC_PAYLOAD_BIG_INT_OK in C output, got: $PBI_C_OUT"
  exit 180
fi
if ! printf '%s\n' "$PBI_C_OUT" | rg -q '^65535$'; then
  echo "ERROR: expected line 65535 in C output, got: $PBI_C_OUT"
  exit 180
fi
set +e
PBI_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$PBI" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
pbi_py_rc=$?
set -e
if [ "$pbi_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_payload_big_int exited $pbi_py_rc: $PBI_PY_OUT"
  exit 181
fi
if [ "$PBI_C_OUT" != "$PBI_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_payload_big_int" >&2
  echo "C:  $PBI_C_OUT" >&2
  echo "Py: $PBI_PY_OUT" >&2
  exit 182
fi

echo "[gate] F34: C vs Python — set global from ::event.data in listener"
SFP="${ROOT_DIR}/azl/tests/p0_semantic_set_from_payload.azl"
set +e
SFP_C_OUT="$("$MINI_BIN" "$SFP" boot.entry 2>&1)"
sfp_c_rc=$?
set -e
if [ "$sfp_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_set_from_payload exited $sfp_c_rc: $SFP_C_OUT"
  exit 183
fi
if ! printf '%s\n' "$SFP_C_OUT" | rg -q 'P0_SEMANTIC_SET_FROM_PAYLOAD_OK'; then
  echo "ERROR: expected P0_SEMANTIC_SET_FROM_PAYLOAD_OK in C output, got: $SFP_C_OUT"
  exit 183
fi
if ! printf '%s\n' "$SFP_C_OUT" | rg -q '^cloned$'; then
  echo "ERROR: expected line cloned in C output, got: $SFP_C_OUT"
  exit 183
fi
set +e
SFP_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$SFP" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
sfp_py_rc=$?
set -e
if [ "$sfp_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_set_from_payload exited $sfp_py_rc: $SFP_PY_OUT"
  exit 184
fi
if [ "$SFP_C_OUT" != "$SFP_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_set_from_payload" >&2
  echo "C:  $SFP_C_OUT" >&2
  echo "Py: $SFP_PY_OUT" >&2
  exit 185
fi

echo "[gate] F35: C vs Python — present payload field != null"
PNP="${ROOT_DIR}/azl/tests/p0_semantic_payload_present_ne_null.azl"
set +e
PNP_C_OUT="$("$MINI_BIN" "$PNP" boot.entry 2>&1)"
pnp_c_rc=$?
set -e
if [ "$pnp_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_payload_present_ne_null exited $pnp_c_rc: $PNP_C_OUT"
  exit 186
fi
if ! printf '%s\n' "$PNP_C_OUT" | rg -q 'F35_PRES_NOT_NULL'; then
  echo "ERROR: expected F35_PRES_NOT_NULL in C output, got: $PNP_C_OUT"
  exit 186
fi
if ! printf '%s\n' "$PNP_C_OUT" | rg -q 'P0_SEMANTIC_PAYLOAD_NE_NULL_OK'; then
  echo "ERROR: expected P0_SEMANTIC_PAYLOAD_NE_NULL_OK in C output, got: $PNP_C_OUT"
  exit 186
fi
set +e
PNP_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$PNP" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
pnp_py_rc=$?
set -e
if [ "$pnp_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_payload_present_ne_null exited $pnp_py_rc: $PNP_PY_OUT"
  exit 187
fi
if [ "$PNP_C_OUT" != "$PNP_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_payload_present_ne_null" >&2
  echo "C:  $PNP_C_OUT" >&2
  echo "Py: $PNP_PY_OUT" >&2
  exit 188
fi

echo "[gate] F36: C vs Python — payload quoted string negative (\"-7\")"
PQN="${ROOT_DIR}/azl/tests/p0_semantic_payload_quoted_negative.azl"
set +e
PQN_C_OUT="$("$MINI_BIN" "$PQN" boot.entry 2>&1)"
pqn_c_rc=$?
set -e
if [ "$pqn_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_payload_quoted_negative exited $pqn_c_rc: $PQN_C_OUT"
  exit 189
fi
if ! printf '%s\n' "$PQN_C_OUT" | rg -q 'P0_SEMANTIC_PAYLOAD_QUOTED_NEG_OK'; then
  echo "ERROR: expected P0_SEMANTIC_PAYLOAD_QUOTED_NEG_OK in C output, got: $PQN_C_OUT"
  exit 189
fi
if ! printf '%s\n' "$PQN_C_OUT" | rg -q '^-7$'; then
  echo "ERROR: expected line -7 in C output, got: $PQN_C_OUT"
  exit 189
fi
set +e
PQN_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$PQN" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
pqn_py_rc=$?
set -e
if [ "$pqn_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_payload_quoted_negative exited $pqn_py_rc: $PQN_PY_OUT"
  exit 190
fi
if [ "$PQN_C_OUT" != "$PQN_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_payload_quoted_negative" >&2
  echo "C:  $PQN_C_OUT" >&2
  echo "Py: $PQN_PY_OUT" >&2
  exit 191
fi

echo "[gate] F37: C vs Python — emit from listener (nested dispatch order)"
EFC="${ROOT_DIR}/azl/tests/p0_semantic_emit_from_listener_chain.azl"
set +e
EFC_C_OUT="$("$MINI_BIN" "$EFC" boot.entry 2>&1)"
efc_c_rc=$?
set -e
if [ "$efc_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_emit_from_listener_chain exited $efc_c_rc: $EFC_C_OUT"
  exit 192
fi
if ! printf '%s\n' "$EFC_C_OUT" | rg -q 'P37_IN_B'; then
  echo "ERROR: expected P37_IN_B in C output, got: $EFC_C_OUT"
  exit 192
fi
if ! printf '%s\n' "$EFC_C_OUT" | rg -q 'P37_AFTER_EMIT_B'; then
  echo "ERROR: expected P37_AFTER_EMIT_B in C output, got: $EFC_C_OUT"
  exit 192
fi
if ! printf '%s\n' "$EFC_C_OUT" | rg -q 'P0_SEMANTIC_EMIT_FROM_LISTENER_OK'; then
  echo "ERROR: expected P0_SEMANTIC_EMIT_FROM_LISTENER_OK in C output, got: $EFC_C_OUT"
  exit 192
fi
if ! printf '%s\n' "$EFC_C_OUT" | awk 'NR==1{if($0!="P37_IN_B")exit 1} NR==2{if($0!="P37_AFTER_EMIT_B")exit 1} NR==3{if($0!="P0_SEMANTIC_EMIT_FROM_LISTENER_OK")exit 1} END{if(NR!=3)exit 1}'; then
  echo "ERROR: expected stdout order P37_IN_B, P37_AFTER_EMIT_B, P0_SEMANTIC_EMIT_FROM_LISTENER_OK, got: $EFC_C_OUT"
  exit 192
fi
set +e
EFC_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$EFC" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
efc_py_rc=$?
set -e
if [ "$efc_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_emit_from_listener_chain exited $efc_py_rc: $EFC_PY_OUT"
  exit 193
fi
if [ "$EFC_C_OUT" != "$EFC_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_emit_from_listener_chain" >&2
  echo "C:  $EFC_C_OUT" >&2
  echo "Py: $EFC_PY_OUT" >&2
  exit 194
fi

echo "[gate] F38: C vs Python — payload key token ending with ':' (traceid:)"
PTC="${ROOT_DIR}/azl/tests/p0_semantic_payload_trailing_colon_key.azl"
set +e
PTC_C_OUT="$("$MINI_BIN" "$PTC" boot.entry 2>&1)"
ptc_c_rc=$?
set -e
if [ "$ptc_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_payload_trailing_colon_key exited $ptc_c_rc: $PTC_C_OUT"
  exit 195
fi
if ! printf '%s\n' "$PTC_C_OUT" | rg -q 'P0_SEMANTIC_PAYLOAD_TRAILING_COLON_KEY_OK'; then
  echo "ERROR: expected P0_SEMANTIC_PAYLOAD_TRAILING_COLON_KEY_OK in C output, got: $PTC_C_OUT"
  exit 195
fi
if ! printf '%s\n' "$PTC_C_OUT" | rg -q '^z9$'; then
  echo "ERROR: expected line z9 in C output, got: $PTC_C_OUT"
  exit 195
fi
set +e
PTC_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$PTC" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
ptc_py_rc=$?
set -e
if [ "$ptc_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_payload_trailing_colon_key exited $ptc_py_rc: $PTC_PY_OUT"
  exit 196
fi
if [ "$PTC_C_OUT" != "$PTC_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_payload_trailing_colon_key" >&2
  echo "C:  $PTC_C_OUT" >&2
  echo "Py: $PTC_PY_OUT" >&2
  exit 197
fi

echo "[gate] F39: C vs Python — if (true) in listener"
ITL="${ROOT_DIR}/azl/tests/p0_semantic_if_true_literal_listener.azl"
set +e
ITL_C_OUT="$("$MINI_BIN" "$ITL" boot.entry 2>&1)"
itl_c_rc=$?
set -e
if [ "$itl_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_if_true_literal_listener exited $itl_c_rc: $ITL_C_OUT"
  exit 198
fi
if ! printf '%s\n' "$ITL_C_OUT" | rg -q 'F39_TRUE_BRANCH'; then
  echo "ERROR: expected F39_TRUE_BRANCH in C output, got: $ITL_C_OUT"
  exit 198
fi
if ! printf '%s\n' "$ITL_C_OUT" | rg -q 'P0_SEMANTIC_IF_TRUE_LITERAL_OK'; then
  echo "ERROR: expected P0_SEMANTIC_IF_TRUE_LITERAL_OK in C output, got: $ITL_C_OUT"
  exit 198
fi
set +e
ITL_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$ITL" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
itl_py_rc=$?
set -e
if [ "$itl_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_if_true_literal_listener exited $itl_py_rc: $ITL_PY_OUT"
  exit 199
fi
if [ "$ITL_C_OUT" != "$ITL_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_if_true_literal_listener" >&2
  echo "C:  $ITL_C_OUT" >&2
  echo "Py: $ITL_PY_OUT" >&2
  exit 200
fi

echo "[gate] F40: C vs Python — if (false) in listener (branch skipped)"
IFL="${ROOT_DIR}/azl/tests/p0_semantic_if_false_literal_listener.azl"
set +e
IFL_C_OUT="$("$MINI_BIN" "$IFL" boot.entry 2>&1)"
ifl_c_rc=$?
set -e
if [ "$ifl_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_if_false_literal_listener exited $ifl_c_rc: $IFL_C_OUT"
  exit 201
fi
if printf '%s\n' "$IFL_C_OUT" | rg -q 'F40_BAD'; then
  echo "ERROR: did not expect F40_BAD (false branch must not run), got: $IFL_C_OUT"
  exit 201
fi
if ! printf '%s\n' "$IFL_C_OUT" | rg -q 'P0_SEMANTIC_IF_FALSE_LITERAL_OK'; then
  echo "ERROR: expected P0_SEMANTIC_IF_FALSE_LITERAL_OK in C output, got: $IFL_C_OUT"
  exit 201
fi
set +e
IFL_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$IFL" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
ifl_py_rc=$?
set -e
if [ "$ifl_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_if_false_literal_listener exited $ifl_py_rc: $IFL_PY_OUT"
  exit 202
fi
if [ "$IFL_C_OUT" != "$IFL_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_if_false_literal_listener" >&2
  echo "C:  $IFL_C_OUT" >&2
  echo "Py: $IFL_PY_OUT" >&2
  exit 203
fi

echo "[gate] F41: C vs Python — listen in init then emit"
LIE="${ROOT_DIR}/azl/tests/p0_semantic_listen_in_init_emit.azl"
set +e
LIE_C_OUT="$("$MINI_BIN" "$LIE" boot.entry 2>&1)"
lie_c_rc=$?
set -e
if [ "$lie_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_listen_in_init_emit exited $lie_c_rc: $LIE_C_OUT"
  exit 204
fi
if ! printf '%s\n' "$LIE_C_OUT" | rg -q 'F41_DYN_OK'; then
  echo "ERROR: expected F41_DYN_OK in C output, got: $LIE_C_OUT"
  exit 204
fi
if ! printf '%s\n' "$LIE_C_OUT" | rg -q 'P0_SEMANTIC_LISTEN_IN_INIT_OK'; then
  echo "ERROR: expected P0_SEMANTIC_LISTEN_IN_INIT_OK in C output, got: $LIE_C_OUT"
  exit 204
fi
if ! printf '%s\n' "$LIE_C_OUT" | awk 'NR==1{if($0!="F41_DYN_OK")exit 1} NR==2{if($0!="P0_SEMANTIC_LISTEN_IN_INIT_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected stdout order F41_DYN_OK, P0_SEMANTIC_LISTEN_IN_INIT_OK, got: $LIE_C_OUT"
  exit 204
fi
set +e
LIE_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$LIE" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
lie_py_rc=$?
set -e
if [ "$lie_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_listen_in_init_emit exited $lie_py_rc: $LIE_PY_OUT"
  exit 205
fi
if [ "$LIE_C_OUT" != "$LIE_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_listen_in_init_emit" >&2
  echo "C:  $LIE_C_OUT" >&2
  echo "Py: $LIE_PY_OUT" >&2
  exit 206
fi

echo "[gate] F42: C vs Python — payload single-quoted value with space"
PSS="${ROOT_DIR}/azl/tests/p0_semantic_payload_squote_space.azl"
set +e
PSS_C_OUT="$("$MINI_BIN" "$PSS" boot.entry 2>&1)"
pss_c_rc=$?
set -e
if [ "$pss_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_payload_squote_space exited $pss_c_rc: $PSS_C_OUT"
  exit 207
fi
if ! printf '%s\n' "$PSS_C_OUT" | rg -q 'P0_SEMANTIC_PAYLOAD_SQUOTE_SPACE_OK'; then
  echo "ERROR: expected P0_SEMANTIC_PAYLOAD_SQUOTE_SPACE_OK in C output, got: $PSS_C_OUT"
  exit 207
fi
if ! printf '%s\n' "$PSS_C_OUT" | rg -q '^a b$'; then
  echo "ERROR: expected line 'a b' in C output, got: $PSS_C_OUT"
  exit 207
fi
set +e
PSS_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$PSS" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
pss_py_rc=$?
set -e
if [ "$pss_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_payload_squote_space exited $pss_py_rc: $PSS_PY_OUT"
  exit 208
fi
if [ "$PSS_C_OUT" != "$PSS_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_payload_squote_space" >&2
  echo "C:  $PSS_C_OUT" >&2
  echo "Py: $PSS_PY_OUT" >&2
  exit 209
fi

echo "[gate] F43: C vs Python — sequential emits, distinct payloads per event"
SPE="${ROOT_DIR}/azl/tests/p0_semantic_sequential_payload_events.azl"
set +e
SPE_C_OUT="$("$MINI_BIN" "$SPE" boot.entry 2>&1)"
spe_c_rc=$?
set -e
if [ "$spe_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_sequential_payload_events exited $spe_c_rc: $SPE_C_OUT"
  exit 210
fi
if ! printf '%s\n' "$SPE_C_OUT" | rg -q 'P0_SEMANTIC_TWO_EVENTS_TWO_PAYLOADS_OK'; then
  echo "ERROR: expected P0_SEMANTIC_TWO_EVENTS_TWO_PAYLOADS_OK in C output, got: $SPE_C_OUT"
  exit 210
fi
if ! printf '%s\n' "$SPE_C_OUT" | awk 'NR==1{if($0!="one")exit 1} NR==2{if($0!="two")exit 1} NR==3{if($0!="P0_SEMANTIC_TWO_EVENTS_TWO_PAYLOADS_OK")exit 1} END{if(NR!=3)exit 1}'; then
  echo "ERROR: expected stdout order one, two, P0_SEMANTIC_TWO_EVENTS_TWO_PAYLOADS_OK, got: $SPE_C_OUT"
  exit 210
fi
set +e
SPE_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$SPE" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
spe_py_rc=$?
set -e
if [ "$spe_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_sequential_payload_events exited $spe_py_rc: $SPE_PY_OUT"
  exit 211
fi
if [ "$SPE_C_OUT" != "$SPE_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_sequential_payload_events" >&2
  echo "C:  $SPE_C_OUT" >&2
  echo "Py: $SPE_PY_OUT" >&2
  exit 212
fi

echo "[gate] F44: C vs Python — if (1) in listener"
ION="${ROOT_DIR}/azl/tests/p0_semantic_if_one_literal_listener.azl"
set +e
ION_C_OUT="$("$MINI_BIN" "$ION" boot.entry 2>&1)"
ion_c_rc=$?
set -e
if [ "$ion_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_if_one_literal_listener exited $ion_c_rc: $ION_C_OUT"
  exit 213
fi
if ! printf '%s\n' "$ION_C_OUT" | rg -q 'F44_ONE_BRANCH'; then
  echo "ERROR: expected F44_ONE_BRANCH in C output, got: $ION_C_OUT"
  exit 213
fi
if ! printf '%s\n' "$ION_C_OUT" | rg -q 'P0_SEMANTIC_IF_ONE_LITERAL_OK'; then
  echo "ERROR: expected P0_SEMANTIC_IF_ONE_LITERAL_OK in C output, got: $ION_C_OUT"
  exit 213
fi
set +e
ION_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$ION" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
ion_py_rc=$?
set -e
if [ "$ion_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_if_one_literal_listener exited $ion_py_rc: $ION_PY_OUT"
  exit 214
fi
if [ "$ION_C_OUT" != "$ION_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_if_one_literal_listener" >&2
  echo "C:  $ION_C_OUT" >&2
  echo "Py: $ION_PY_OUT" >&2
  exit 215
fi

echo "[gate] F45: C vs Python — emit quoted event name only (no with)"
EQO="${ROOT_DIR}/azl/tests/p0_semantic_emit_quoted_event_only.azl"
set +e
EQO_C_OUT="$("$MINI_BIN" "$EQO" boot.entry 2>&1)"
eqo_c_rc=$?
set -e
if [ "$eqo_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_emit_quoted_event_only exited $eqo_c_rc: $EQO_C_OUT"
  exit 216
fi
if ! printf '%s\n' "$EQO_C_OUT" | rg -q 'F45_QUOTED_EMIT_NO_WITH_OK'; then
  echo "ERROR: expected F45_QUOTED_EMIT_NO_WITH_OK in C output, got: $EQO_C_OUT"
  exit 216
fi
set +e
EQO_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$EQO" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
eqo_py_rc=$?
set -e
if [ "$eqo_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_emit_quoted_event_only exited $eqo_py_rc: $EQO_PY_OUT"
  exit 217
fi
if [ "$EQO_C_OUT" != "$EQO_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_emit_quoted_event_only" >&2
  echo "C:  $EQO_C_OUT" >&2
  echo "Py: $EQO_PY_OUT" >&2
  exit 218
fi

echo "[gate] F46: C vs Python — say unset ::path → blank line"
SUB="${ROOT_DIR}/azl/tests/p0_semantic_say_unset_blank_line.azl"
set +e
SUB_C_OUT="$("$MINI_BIN" "$SUB" boot.entry 2>&1)"
sub_c_rc=$?
set -e
if [ "$sub_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_say_unset_blank_line exited $sub_c_rc: $SUB_C_OUT"
  exit 219
fi
if ! printf '%s\n' "$SUB_C_OUT" | rg -q 'P0_SEMANTIC_SAY_UNSET_BLANK_OK'; then
  echo "ERROR: expected P0_SEMANTIC_SAY_UNSET_BLANK_OK in C output, got: $SUB_C_OUT"
  exit 219
fi
if ! printf '%s\n' "$SUB_C_OUT" | awk 'NR==1{if(length($0)!=0)exit 1} NR==2{if($0!="P0_SEMANTIC_SAY_UNSET_BLANK_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected blank first line then P0_SEMANTIC_SAY_UNSET_BLANK_OK, got: $SUB_C_OUT"
  exit 219
fi
set +e
SUB_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$SUB" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
sub_py_rc=$?
set -e
if [ "$sub_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_say_unset_blank_line exited $sub_py_rc: $SUB_PY_OUT"
  exit 220
fi
if [ "$SUB_C_OUT" != "$SUB_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_say_unset_blank_line" >&2
  echo "C:  $SUB_C_OUT" >&2
  echo "Py: $SUB_PY_OUT" >&2
  exit 221
fi

echo "[gate] F47: C vs Python — set ::global from payload then if (::global)"
IGP="${ROOT_DIR}/azl/tests/p0_semantic_if_global_from_payload.azl"
set +e
IGP_C_OUT="$("$MINI_BIN" "$IGP" boot.entry 2>&1)"
igp_c_rc=$?
set -e
if [ "$igp_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_if_global_from_payload exited $igp_c_rc: $IGP_C_OUT"
  exit 222
fi
if ! printf '%s\n' "$IGP_C_OUT" | rg -q 'F47_FLAG_BRANCH'; then
  echo "ERROR: expected F47_FLAG_BRANCH in C output, got: $IGP_C_OUT"
  exit 222
fi
if ! printf '%s\n' "$IGP_C_OUT" | rg -q 'P0_SEMANTIC_IF_GLOBAL_FROM_PAYLOAD_OK'; then
  echo "ERROR: expected P0_SEMANTIC_IF_GLOBAL_FROM_PAYLOAD_OK in C output, got: $IGP_C_OUT"
  exit 222
fi
set +e
IGP_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$IGP" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
igp_py_rc=$?
set -e
if [ "$igp_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_if_global_from_payload exited $igp_py_rc: $IGP_PY_OUT"
  exit 223
fi
if [ "$IGP_C_OUT" != "$IGP_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_if_global_from_payload" >&2
  echo "C:  $IGP_C_OUT" >&2
  echo "Py: $IGP_PY_OUT" >&2
  exit 224
fi

echo "[gate] F48: C vs Python — if (0) in listener (branch skipped)"
IZL="${ROOT_DIR}/azl/tests/p0_semantic_if_zero_literal_listener.azl"
set +e
IZL_C_OUT="$("$MINI_BIN" "$IZL" boot.entry 2>&1)"
izl_c_rc=$?
set -e
if [ "$izl_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_if_zero_literal_listener exited $izl_c_rc: $IZL_C_OUT"
  exit 225
fi
if printf '%s\n' "$IZL_C_OUT" | rg -q 'F48_BAD'; then
  echo "ERROR: did not expect F48_BAD (zero branch must not run), got: $IZL_C_OUT"
  exit 225
fi
if ! printf '%s\n' "$IZL_C_OUT" | rg -q 'P0_SEMANTIC_IF_ZERO_LITERAL_OK'; then
  echo "ERROR: expected P0_SEMANTIC_IF_ZERO_LITERAL_OK in C output, got: $IZL_C_OUT"
  exit 225
fi
set +e
IZL_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$IZL" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
izl_py_rc=$?
set -e
if [ "$izl_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_if_zero_literal_listener exited $izl_py_rc: $IZL_PY_OUT"
  exit 226
fi
if [ "$IZL_C_OUT" != "$IZL_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_if_zero_literal_listener" >&2
  echo "C:  $IZL_C_OUT" >&2
  echo "Py: $IZL_PY_OUT" >&2
  exit 227
fi

echo "[gate] F49: C vs Python — emit unquoted event name only (no with)"
EUO="${ROOT_DIR}/azl/tests/p0_semantic_emit_unquoted_event_only.azl"
set +e
EUO_C_OUT="$("$MINI_BIN" "$EUO" boot.entry 2>&1)"
euo_c_rc=$?
set -e
if [ "$euo_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_emit_unquoted_event_only exited $euo_c_rc: $EUO_C_OUT"
  exit 228
fi
if ! printf '%s\n' "$EUO_C_OUT" | rg -q 'F49_UNQUOTED_EMIT_OK'; then
  echo "ERROR: expected F49_UNQUOTED_EMIT_OK in C output, got: $EUO_C_OUT"
  exit 228
fi
set +e
EUO_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$EUO" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
euo_py_rc=$?
set -e
if [ "$euo_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_emit_unquoted_event_only exited $euo_py_rc: $EUO_PY_OUT"
  exit 229
fi
if [ "$EUO_C_OUT" != "$EUO_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_emit_unquoted_event_only" >&2
  echo "C:  $EUO_C_OUT" >&2
  echo "Py: $EUO_PY_OUT" >&2
  exit 230
fi

echo "[gate] F50: C vs Python — say ::global empty string → blank line"
SEG="${ROOT_DIR}/azl/tests/p0_semantic_say_empty_string_global.azl"
set +e
SEG_C_OUT="$("$MINI_BIN" "$SEG" boot.entry 2>&1)"
seg_c_rc=$?
set -e
if [ "$seg_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_say_empty_string_global exited $seg_c_rc: $SEG_C_OUT"
  exit 231
fi
if ! printf '%s\n' "$SEG_C_OUT" | rg -q 'P0_SEMANTIC_SAY_EMPTY_STRING_OK'; then
  echo "ERROR: expected P0_SEMANTIC_SAY_EMPTY_STRING_OK in C output, got: $SEG_C_OUT"
  exit 231
fi
if ! printf '%s\n' "$SEG_C_OUT" | awk 'NR==1{if(length($0)!=0)exit 1} NR==2{if($0!="P0_SEMANTIC_SAY_EMPTY_STRING_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected blank first line then P0_SEMANTIC_SAY_EMPTY_STRING_OK, got: $SEG_C_OUT"
  exit 231
fi
set +e
SEG_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$SEG" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
seg_py_rc=$?
set -e
if [ "$seg_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_say_empty_string_global exited $seg_py_rc: $SEG_PY_OUT"
  exit 232
fi
if [ "$SEG_C_OUT" != "$SEG_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_say_empty_string_global" >&2
  echo "C:  $SEG_C_OUT" >&2
  echo "Py: $SEG_PY_OUT" >&2
  exit 233
fi

echo "[gate] F51: C vs Python — if (::flag) false when flag is string false from payload"
ISF="${ROOT_DIR}/azl/tests/p0_semantic_if_string_false_from_payload.azl"
set +e
ISF_C_OUT="$("$MINI_BIN" "$ISF" boot.entry 2>&1)"
isf_c_rc=$?
set -e
if [ "$isf_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_if_string_false_from_payload exited $isf_c_rc: $ISF_C_OUT"
  exit 234
fi
if printf '%s\n' "$ISF_C_OUT" | rg -q 'F51_BAD'; then
  echo "ERROR: did not expect F51_BAD (string false must not run if branch), got: $ISF_C_OUT"
  exit 234
fi
if ! printf '%s\n' "$ISF_C_OUT" | rg -q 'P0_SEMANTIC_IF_STRING_FALSE_OK'; then
  echo "ERROR: expected P0_SEMANTIC_IF_STRING_FALSE_OK in C output, got: $ISF_C_OUT"
  exit 234
fi
set +e
ISF_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$ISF" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
isf_py_rc=$?
set -e
if [ "$isf_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_if_string_false_from_payload exited $isf_py_rc: $ISF_PY_OUT"
  exit 235
fi
if [ "$ISF_C_OUT" != "$ISF_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_if_string_false_from_payload" >&2
  echo "C:  $ISF_C_OUT" >&2
  echo "Py: $ISF_PY_OUT" >&2
  exit 236
fi

echo "[gate] F52: C vs Python — if (::t) when ::t is string \"true\""
IVT="${ROOT_DIR}/azl/tests/p0_semantic_if_var_true_string.azl"
set +e
IVT_C_OUT="$("$MINI_BIN" "$IVT" boot.entry 2>&1)"
ivt_c_rc=$?
set -e
if [ "$ivt_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_if_var_true_string exited $ivt_c_rc: $IVT_C_OUT"
  exit 237
fi
if ! printf '%s\n' "$IVT_C_OUT" | rg -q 'F52_TRUE_STRING_VAR'; then
  echo "ERROR: expected F52_TRUE_STRING_VAR in C output, got: $IVT_C_OUT"
  exit 237
fi
if ! printf '%s\n' "$IVT_C_OUT" | rg -q 'P0_SEMANTIC_IF_VAR_TRUE_STRING_OK'; then
  echo "ERROR: expected P0_SEMANTIC_IF_VAR_TRUE_STRING_OK in C output, got: $IVT_C_OUT"
  exit 237
fi
set +e
IVT_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$IVT" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
ivt_py_rc=$?
set -e
if [ "$ivt_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_if_var_true_string exited $ivt_py_rc: $IVT_PY_OUT"
  exit 238
fi
if [ "$IVT_C_OUT" != "$IVT_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_if_var_true_string" >&2
  echo "C:  $IVT_C_OUT" >&2
  echo "Py: $IVT_PY_OUT" >&2
  exit 239
fi

echo "[gate] F53: C vs Python — same event name twice, different payloads (queue)"
SET="${ROOT_DIR}/azl/tests/p0_semantic_same_event_twice_payload.azl"
set +e
SET_C_OUT="$("$MINI_BIN" "$SET" boot.entry 2>&1)"
set_c_rc=$?
set -e
if [ "$set_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_same_event_twice_payload exited $set_c_rc: $SET_C_OUT"
  exit 240
fi
if ! printf '%s\n' "$SET_C_OUT" | rg -q 'P0_SEMANTIC_SAME_EVENT_TWICE_OK'; then
  echo "ERROR: expected P0_SEMANTIC_SAME_EVENT_TWICE_OK in C output, got: $SET_C_OUT"
  exit 240
fi
if ! printf '%s\n' "$SET_C_OUT" | awk 'NR==1{if($0!="first")exit 1} NR==2{if($0!="second")exit 1} NR==3{if($0!="P0_SEMANTIC_SAME_EVENT_TWICE_OK")exit 1} END{if(NR!=3)exit 1}'; then
  echo "ERROR: expected stdout order first, second, P0_SEMANTIC_SAME_EVENT_TWICE_OK, got: $SET_C_OUT"
  exit 240
fi
set +e
SET_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$SET" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
set_py_rc=$?
set -e
if [ "$set_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_same_event_twice_payload exited $set_py_rc: $SET_PY_OUT"
  exit 241
fi
if [ "$SET_C_OUT" != "$SET_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_same_event_twice_payload" >&2
  echo "C:  $SET_C_OUT" >&2
  echo "Py: $SET_PY_OUT" >&2
  exit 242
fi

echo "[gate] F54: C vs Python — listen + emit in boot.entry init"
LIB="${ROOT_DIR}/azl/tests/p0_semantic_listen_in_boot_entry.azl"
set +e
LIB_C_OUT="$("$MINI_BIN" "$LIB" boot.entry 2>&1)"
lib_c_rc=$?
set -e
if [ "$lib_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_listen_in_boot_entry exited $lib_c_rc: $LIB_C_OUT"
  exit 243
fi
if ! printf '%s\n' "$LIB_C_OUT" | rg -q 'F54_BOOT_LISTEN_OK'; then
  echo "ERROR: expected F54_BOOT_LISTEN_OK in C output, got: $LIB_C_OUT"
  exit 243
fi
if ! printf '%s\n' "$LIB_C_OUT" | rg -q 'P0_SEMANTIC_LISTEN_IN_BOOT_ENTRY_OK'; then
  echo "ERROR: expected P0_SEMANTIC_LISTEN_IN_BOOT_ENTRY_OK in C output, got: $LIB_C_OUT"
  exit 243
fi
if ! printf '%s\n' "$LIB_C_OUT" | awk 'NR==1{if($0!="F54_BOOT_LISTEN_OK")exit 1} NR==2{if($0!="P0_SEMANTIC_LISTEN_IN_BOOT_ENTRY_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected stdout order F54_BOOT_LISTEN_OK, P0_SEMANTIC_LISTEN_IN_BOOT_ENTRY_OK, got: $LIB_C_OUT"
  exit 243
fi
set +e
LIB_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$LIB" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
lib_py_rc=$?
set -e
if [ "$lib_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_listen_in_boot_entry exited $lib_py_rc: $LIB_PY_OUT"
  exit 244
fi
if [ "$LIB_C_OUT" != "$LIB_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_listen_in_boot_entry" >&2
  echo "C:  $LIB_C_OUT" >&2
  echo "Py: $LIB_PY_OUT" >&2
  exit 245
fi

echo "[gate] F55: C vs Python — if (::t) when ::t is string \"1\""
IVO="${ROOT_DIR}/azl/tests/p0_semantic_if_var_one_string.azl"
set +e
IVO_C_OUT="$("$MINI_BIN" "$IVO" boot.entry 2>&1)"
ivo_c_rc=$?
set -e
if [ "$ivo_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_if_var_one_string exited $ivo_c_rc: $IVO_C_OUT"
  exit 246
fi
if ! printf '%s\n' "$IVO_C_OUT" | rg -q 'F55_ONE_STRING_VAR'; then
  echo "ERROR: expected F55_ONE_STRING_VAR in C output, got: $IVO_C_OUT"
  exit 246
fi
if ! printf '%s\n' "$IVO_C_OUT" | rg -q 'P0_SEMANTIC_IF_VAR_ONE_STRING_OK'; then
  echo "ERROR: expected P0_SEMANTIC_IF_VAR_ONE_STRING_OK in C output, got: $IVO_C_OUT"
  exit 246
fi
set +e
IVO_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$IVO" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
ivo_py_rc=$?
set -e
if [ "$ivo_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_if_var_one_string exited $ivo_py_rc: $IVO_PY_OUT"
  exit 247
fi
if [ "$IVO_C_OUT" != "$IVO_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_if_var_one_string" >&2
  echo "C:  $IVO_C_OUT" >&2
  echo "Py: $IVO_PY_OUT" >&2
  exit 248
fi

echo "[gate] F56: C vs Python — if (::t) skips when ::t is string \"0\""
IVZ="${ROOT_DIR}/azl/tests/p0_semantic_if_var_zero_string.azl"
set +e
IVZ_C_OUT="$("$MINI_BIN" "$IVZ" boot.entry 2>&1)"
ivz_c_rc=$?
set -e
if [ "$ivz_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_if_var_zero_string exited $ivz_c_rc: $IVZ_C_OUT"
  exit 249
fi
if printf '%s\n' "$IVZ_C_OUT" | rg -q 'F56_BAD'; then
  echo "ERROR: did not expect F56_BAD (string 0 must not run if branch), got: $IVZ_C_OUT"
  exit 249
fi
if ! printf '%s\n' "$IVZ_C_OUT" | rg -q 'P0_SEMANTIC_IF_VAR_ZERO_STRING_OK'; then
  echo "ERROR: expected P0_SEMANTIC_IF_VAR_ZERO_STRING_OK in C output, got: $IVZ_C_OUT"
  exit 249
fi
set +e
IVZ_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$IVZ" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
ivz_py_rc=$?
set -e
if [ "$ivz_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_if_var_zero_string exited $ivz_py_rc: $IVZ_PY_OUT"
  exit 250
fi
if [ "$IVZ_C_OUT" != "$IVZ_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_if_var_zero_string" >&2
  echo "C:  $IVZ_C_OUT" >&2
  echo "Py: $IVZ_PY_OUT" >&2
  exit 251
fi

echo "[gate] F57: C vs Python — if (::t) skips when ::t is empty string"
IVE="${ROOT_DIR}/azl/tests/p0_semantic_if_var_empty_string.azl"
set +e
IVE_C_OUT="$("$MINI_BIN" "$IVE" boot.entry 2>&1)"
ive_c_rc=$?
set -e
if [ "$ive_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_if_var_empty_string exited $ive_c_rc: $IVE_C_OUT"
  exit 252
fi
if printf '%s\n' "$IVE_C_OUT" | rg -q 'F57_BAD'; then
  echo "ERROR: did not expect F57_BAD (empty string must not run if branch), got: $IVE_C_OUT"
  exit 252
fi
if ! printf '%s\n' "$IVE_C_OUT" | rg -q 'P0_SEMANTIC_IF_VAR_EMPTY_STRING_OK'; then
  echo "ERROR: expected P0_SEMANTIC_IF_VAR_EMPTY_STRING_OK in C output, got: $IVE_C_OUT"
  exit 252
fi
set +e
IVE_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$IVE" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
ive_py_rc=$?
set -e
if [ "$ive_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_if_var_empty_string exited $ive_py_rc: $IVE_PY_OUT"
  exit 253
fi
if [ "$IVE_C_OUT" != "$IVE_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_if_var_empty_string" >&2
  echo "C:  $IVE_C_OUT" >&2
  echo "Py: $IVE_PY_OUT" >&2
  exit 254
fi

echo "[gate] F58: C vs Python — duplicate event across components, first linked wins"
CCF="${ROOT_DIR}/azl/tests/p0_semantic_cross_component_first_listener.azl"
set +e
CCF_C_OUT="$("$MINI_BIN" "$CCF" boot.entry 2>&1)"
ccf_c_rc=$?
set -e
if [ "$ccf_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_cross_component_first_listener exited $ccf_c_rc: $CCF_C_OUT"
  exit 255
fi
if printf '%s\n' "$CCF_C_OUT" | rg -q 'F58_SECOND_BAD'; then
  echo "ERROR: did not expect F58_SECOND_BAD (second linked listener must not run), got: $CCF_C_OUT"
  exit 255
fi
if ! printf '%s\n' "$CCF_C_OUT" | rg -q 'F58_FIRST_LINKED'; then
  echo "ERROR: expected F58_FIRST_LINKED in C output, got: $CCF_C_OUT"
  exit 255
fi
if ! printf '%s\n' "$CCF_C_OUT" | rg -q 'P0_SEMANTIC_CROSS_COMP_FIRST_OK'; then
  echo "ERROR: expected P0_SEMANTIC_CROSS_COMP_FIRST_OK in C output, got: $CCF_C_OUT"
  exit 255
fi
if ! printf '%s\n' "$CCF_C_OUT" | awk 'NR==1{if($0!="F58_FIRST_LINKED")exit 1} NR==2{if($0!="P0_SEMANTIC_CROSS_COMP_FIRST_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected stdout order F58_FIRST_LINKED, P0_SEMANTIC_CROSS_COMP_FIRST_OK, got: $CCF_C_OUT"
  exit 255
fi
set +e
CCF_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$CCF" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
ccf_py_rc=$?
set -e
if [ "$ccf_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_cross_component_first_listener exited $ccf_py_rc: $CCF_PY_OUT"
  exit 256
fi
if [ "$CCF_C_OUT" != "$CCF_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_cross_component_first_listener" >&2
  echo "C:  $CCF_C_OUT" >&2
  echo "Py: $CCF_PY_OUT" >&2
  exit 257
fi

echo "[gate] F59: C vs Python — two emits same bare event, listener twice"
DES="${ROOT_DIR}/azl/tests/p0_semantic_double_emit_same_event.azl"
set +e
DES_C_OUT="$("$MINI_BIN" "$DES" boot.entry 2>&1)"
des_c_rc=$?
set -e
if [ "$des_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_double_emit_same_event exited $des_c_rc: $DES_C_OUT"
  exit 258
fi
if ! printf '%s\n' "$DES_C_OUT" | rg -q 'P0_SEMANTIC_DOUBLE_EMIT_SAME_OK'; then
  echo "ERROR: expected P0_SEMANTIC_DOUBLE_EMIT_SAME_OK in C output, got: $DES_C_OUT"
  exit 258
fi
if ! printf '%s\n' "$DES_C_OUT" | awk 'NR==1{if($0!="F59_TICK_HIT")exit 1} NR==2{if($0!="F59_TICK_HIT")exit 1} NR==3{if($0!="P0_SEMANTIC_DOUBLE_EMIT_SAME_OK")exit 1} END{if(NR!=3)exit 1}'; then
  echo "ERROR: expected stdout order F59_TICK_HIT, F59_TICK_HIT, P0_SEMANTIC_DOUBLE_EMIT_SAME_OK, got: $DES_C_OUT"
  exit 258
fi
set +e
DES_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$DES" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
des_py_rc=$?
set -e
if [ "$des_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_double_emit_same_event exited $des_py_rc: $DES_PY_OUT"
  exit 259
fi
if [ "$DES_C_OUT" != "$DES_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_double_emit_same_event" >&2
  echo "C:  $DES_C_OUT" >&2
  echo "Py: $DES_PY_OUT" >&2
  exit 260
fi

echo "[gate] F60: C vs Python — if (::a or \"1\") with empty ::a"
IOR="${ROOT_DIR}/azl/tests/p0_semantic_if_or_empty_then_one_string.azl"
set +e
IOR_C_OUT="$("$MINI_BIN" "$IOR" boot.entry 2>&1)"
ior_c_rc=$?
set -e
if [ "$ior_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_if_or_empty_then_one_string exited $ior_c_rc: $IOR_C_OUT"
  exit 261
fi
if ! printf '%s\n' "$IOR_C_OUT" | rg -q 'F60_OR_TRUE_BRANCH'; then
  echo "ERROR: expected F60_OR_TRUE_BRANCH in C output, got: $IOR_C_OUT"
  exit 261
fi
if ! printf '%s\n' "$IOR_C_OUT" | rg -q 'P0_SEMANTIC_IF_OR_EMPTY_ONE_OK'; then
  echo "ERROR: expected P0_SEMANTIC_IF_OR_EMPTY_ONE_OK in C output, got: $IOR_C_OUT"
  exit 261
fi
set +e
IOR_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$IOR" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
ior_py_rc=$?
set -e
if [ "$ior_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_if_or_empty_then_one_string exited $ior_py_rc: $IOR_PY_OUT"
  exit 262
fi
if [ "$IOR_C_OUT" != "$IOR_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_if_or_empty_then_one_string" >&2
  echo "C:  $IOR_C_OUT" >&2
  echo "Py: $IOR_PY_OUT" >&2
  exit 263
fi

echo "[gate] F61: C vs Python — if (::a == ::b) on equal string globals"
IGE="${ROOT_DIR}/azl/tests/p0_semantic_if_global_eq_globals.azl"
set +e
IGE_C_OUT="$("$MINI_BIN" "$IGE" boot.entry 2>&1)"
ige_c_rc=$?
set -e
if [ "$ige_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_if_global_eq_globals exited $ige_c_rc: $IGE_C_OUT"
  exit 264
fi
if ! printf '%s\n' "$IGE_C_OUT" | rg -q 'F61_EQ_TRUE_BRANCH'; then
  echo "ERROR: expected F61_EQ_TRUE_BRANCH in C output, got: $IGE_C_OUT"
  exit 264
fi
if ! printf '%s\n' "$IGE_C_OUT" | rg -q 'P0_SEMANTIC_IF_GLOBAL_EQ_OK'; then
  echo "ERROR: expected P0_SEMANTIC_IF_GLOBAL_EQ_OK in C output, got: $IGE_C_OUT"
  exit 264
fi
set +e
IGE_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$IGE" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
ige_py_rc=$?
set -e
if [ "$ige_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_if_global_eq_globals exited $ige_py_rc: $IGE_PY_OUT"
  exit 265
fi
if [ "$IGE_C_OUT" != "$IGE_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_if_global_eq_globals" >&2
  echo "C:  $IGE_C_OUT" >&2
  echo "Py: $IGE_PY_OUT" >&2
  exit 266
fi

echo "[gate] F62: C vs Python — if (::a != ::b) when globals differ"
IGN="${ROOT_DIR}/azl/tests/p0_semantic_if_global_ne_globals.azl"
set +e
IGN_C_OUT="$("$MINI_BIN" "$IGN" boot.entry 2>&1)"
ign_c_rc=$?
set -e
if [ "$ign_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_if_global_ne_globals exited $ign_c_rc: $IGN_C_OUT"
  exit 267
fi
if ! printf '%s\n' "$IGN_C_OUT" | rg -q 'F62_NEQ_BRANCH'; then
  echo "ERROR: expected F62_NEQ_BRANCH in C output, got: $IGN_C_OUT"
  exit 267
fi
if ! printf '%s\n' "$IGN_C_OUT" | rg -q 'P0_SEMANTIC_IF_GLOBAL_NE_OK'; then
  echo "ERROR: expected P0_SEMANTIC_IF_GLOBAL_NE_OK in C output, got: $IGN_C_OUT"
  exit 267
fi
set +e
IGN_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$IGN" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
ign_py_rc=$?
set -e
if [ "$ign_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_if_global_ne_globals exited $ign_py_rc: $IGN_PY_OUT"
  exit 268
fi
if [ "$IGN_C_OUT" != "$IGN_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_if_global_ne_globals" >&2
  echo "C:  $IGN_C_OUT" >&2
  echo "Py: $IGN_PY_OUT" >&2
  exit 269
fi

echo "[gate] F63: C vs Python — if (::a != ::b) skips when globals are equal"
INE="${ROOT_DIR}/azl/tests/p0_semantic_if_global_ne_equal_skip.azl"
set +e
INE_C_OUT="$("$MINI_BIN" "$INE" boot.entry 2>&1)"
ine_c_rc=$?
set -e
if [ "$ine_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_if_global_ne_equal_skip exited $ine_c_rc: $INE_C_OUT"
  exit 270
fi
if printf '%s\n' "$INE_C_OUT" | rg -q 'F63_BAD'; then
  echo "ERROR: did not expect F63_BAD (::a == ::b must skip != branch), got: $INE_C_OUT"
  exit 270
fi
if ! printf '%s\n' "$INE_C_OUT" | rg -q 'P0_SEMANTIC_IF_GLOBAL_NE_EQUAL_OK'; then
  echo "ERROR: expected P0_SEMANTIC_IF_GLOBAL_NE_EQUAL_OK in C output, got: $INE_C_OUT"
  exit 270
fi
set +e
INE_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$INE" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
ine_py_rc=$?
set -e
if [ "$ine_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_if_global_ne_equal_skip exited $ine_py_rc: $INE_PY_OUT"
  exit 272
fi
if [ "$INE_C_OUT" != "$INE_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_if_global_ne_equal_skip" >&2
  echo "C:  $INE_C_OUT" >&2
  echo "Py: $INE_PY_OUT" >&2
  exit 273
fi

echo "[gate] F64: C vs Python — set ::u = ::a + ::b (string concat)"
SGC="${ROOT_DIR}/azl/tests/p0_semantic_set_global_concat_globals.azl"
set +e
SGC_C_OUT="$("$MINI_BIN" "$SGC" boot.entry 2>&1)"
sgc_c_rc=$?
set -e
if [ "$sgc_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_set_global_concat_globals exited $sgc_c_rc: $SGC_C_OUT"
  exit 274
fi
if ! printf '%s\n' "$SGC_C_OUT" | rg -q '^hello$'; then
  echo "ERROR: expected literal hello line from say ::u, got: $SGC_C_OUT"
  exit 274
fi
if ! printf '%s\n' "$SGC_C_OUT" | rg -q 'P0_SEMANTIC_SET_GLOBAL_CONCAT_OK'; then
  echo "ERROR: expected P0_SEMANTIC_SET_GLOBAL_CONCAT_OK in C output, got: $SGC_C_OUT"
  exit 274
fi
if ! printf '%s\n' "$SGC_C_OUT" | awk 'NR==1{if($0!="hello")exit 1} NR==2{if($0!="P0_SEMANTIC_SET_GLOBAL_CONCAT_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected stdout order hello, P0_SEMANTIC_SET_GLOBAL_CONCAT_OK, got: $SGC_C_OUT"
  exit 274
fi
set +e
SGC_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$SGC" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
sgc_py_rc=$?
set -e
if [ "$sgc_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_set_global_concat_globals exited $sgc_py_rc: $SGC_PY_OUT"
  exit 275
fi
if [ "$SGC_C_OUT" != "$SGC_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_set_global_concat_globals" >&2
  echo "C:  $SGC_C_OUT" >&2
  echo "Py: $SGC_PY_OUT" >&2
  exit 276
fi

echo "[gate] F65: C vs Python — if (\"x\" == \"x\") string literals"
ILE="${ROOT_DIR}/azl/tests/p0_semantic_if_literal_eq_strings.azl"
set +e
ILE_C_OUT="$("$MINI_BIN" "$ILE" boot.entry 2>&1)"
ile_c_rc=$?
set -e
if [ "$ile_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_if_literal_eq_strings exited $ile_c_rc: $ILE_C_OUT"
  exit 277
fi
if ! printf '%s\n' "$ILE_C_OUT" | rg -q 'F65_LITERAL_EQ_BRANCH'; then
  echo "ERROR: expected F65_LITERAL_EQ_BRANCH in C output, got: $ILE_C_OUT"
  exit 277
fi
if ! printf '%s\n' "$ILE_C_OUT" | rg -q 'P0_SEMANTIC_IF_LITERAL_EQ_STRINGS_OK'; then
  echo "ERROR: expected P0_SEMANTIC_IF_LITERAL_EQ_STRINGS_OK in C output, got: $ILE_C_OUT"
  exit 277
fi
set +e
ILE_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$ILE" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
ile_py_rc=$?
set -e
if [ "$ile_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_if_literal_eq_strings exited $ile_py_rc: $ILE_PY_OUT"
  exit 278
fi
if [ "$ILE_C_OUT" != "$ILE_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_if_literal_eq_strings" >&2
  echo "C:  $ILE_C_OUT" >&2
  echo "Py: $ILE_PY_OUT" >&2
  exit 279
fi

echo "[gate] F66: C vs Python — if (\"a\" != \"b\") string literals"
ILN="${ROOT_DIR}/azl/tests/p0_semantic_if_literal_ne_strings.azl"
set +e
ILN_C_OUT="$("$MINI_BIN" "$ILN" boot.entry 2>&1)"
iln_c_rc=$?
set -e
if [ "$iln_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_if_literal_ne_strings exited $iln_c_rc: $ILN_C_OUT"
  exit 280
fi
if ! printf '%s\n' "$ILN_C_OUT" | rg -q 'F66_LITERAL_NE_BRANCH'; then
  echo "ERROR: expected F66_LITERAL_NE_BRANCH in C output, got: $ILN_C_OUT"
  exit 280
fi
if ! printf '%s\n' "$ILN_C_OUT" | rg -q 'P0_SEMANTIC_IF_LITERAL_NE_STRINGS_OK'; then
  echo "ERROR: expected P0_SEMANTIC_IF_LITERAL_NE_STRINGS_OK in C output, got: $ILN_C_OUT"
  exit 280
fi
set +e
ILN_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$ILN" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
iln_py_rc=$?
set -e
if [ "$iln_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_if_literal_ne_strings exited $iln_py_rc: $ILN_PY_OUT"
  exit 281
fi
if [ "$ILN_C_OUT" != "$ILN_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_if_literal_ne_strings" >&2
  echo "C:  $ILN_C_OUT" >&2
  echo "Py: $ILN_PY_OUT" >&2
  exit 282
fi

echo "[gate] F67: C vs Python — set ::out = \"pre\" + ::mid + \"post\""
STC="${ROOT_DIR}/azl/tests/p0_semantic_set_triple_concat_mixed.azl"
set +e
STC_C_OUT="$("$MINI_BIN" "$STC" boot.entry 2>&1)"
stc_c_rc=$?
set -e
if [ "$stc_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_set_triple_concat_mixed exited $stc_c_rc: $STC_C_OUT"
  exit 283
fi
if ! printf '%s\n' "$STC_C_OUT" | rg -q '^preMIDpost$'; then
  echo "ERROR: expected preMIDpost line from say ::out, got: $STC_C_OUT"
  exit 283
fi
if ! printf '%s\n' "$STC_C_OUT" | rg -q 'P0_SEMANTIC_SET_TRIPLE_CONCAT_OK'; then
  echo "ERROR: expected P0_SEMANTIC_SET_TRIPLE_CONCAT_OK in C output, got: $STC_C_OUT"
  exit 283
fi
if ! printf '%s\n' "$STC_C_OUT" | awk 'NR==1{if($0!="preMIDpost")exit 1} NR==2{if($0!="P0_SEMANTIC_SET_TRIPLE_CONCAT_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected stdout order preMIDpost, P0_SEMANTIC_SET_TRIPLE_CONCAT_OK, got: $STC_C_OUT"
  exit 283
fi
set +e
STC_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$STC" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
stc_py_rc=$?
set -e
if [ "$stc_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_set_triple_concat_mixed exited $stc_py_rc: $STC_PY_OUT"
  exit 284
fi
if [ "$STC_C_OUT" != "$STC_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_set_triple_concat_mixed" >&2
  echo "C:  $STC_C_OUT" >&2
  echo "Py: $STC_PY_OUT" >&2
  exit 285
fi

echo "[gate] F68: C vs Python — return inside if in listener (early exit listener body)"
RET="${ROOT_DIR}/azl/tests/p0_semantic_return_in_listener_if.azl"
set +e
RET_C_OUT="$("$MINI_BIN" "$RET" boot.entry 2>&1)"
ret_c_rc=$?
set -e
if [ "$ret_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_return_in_listener_if exited $ret_c_rc: $RET_C_OUT"
  exit 291
fi
if ! printf '%s\n' "$RET_C_OUT" | rg -q '^EARLY$'; then
  echo "ERROR: expected EARLY line from listener, got: $RET_C_OUT"
  exit 291
fi
if ! printf '%s\n' "$RET_C_OUT" | rg -q '^LATE$'; then
  echo "ERROR: expected LATE line from listener, got: $RET_C_OUT"
  exit 291
fi
if ! printf '%s\n' "$RET_C_OUT" | rg -q 'P0_SEMANTIC_RETURN_IN_LISTENER_OK'; then
  echo "ERROR: expected P0_SEMANTIC_RETURN_IN_LISTENER_OK in C output, got: $RET_C_OUT"
  exit 291
fi
if ! printf '%s\n' "$RET_C_OUT" | awk 'NR==1{if($0!="EARLY")exit 1} NR==2{if($0!="LATE")exit 1} NR==3{if($0!="P0_SEMANTIC_RETURN_IN_LISTENER_OK")exit 1} END{if(NR!=3)exit 1}'; then
  echo "ERROR: expected stdout order EARLY, LATE, P0_SEMANTIC_RETURN_IN_LISTENER_OK, got: $RET_C_OUT"
  exit 291
fi
set +e
RET_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$RET" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
ret_py_rc=$?
set -e
if [ "$ret_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_return_in_listener_if exited $ret_py_rc: $RET_PY_OUT"
  exit 292
fi
if [ "$RET_C_OUT" != "$RET_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_return_in_listener_if" >&2
  echo "C:  $RET_C_OUT" >&2
  echo "Py: $RET_PY_OUT" >&2
  exit 293
fi

echo "[gate] F69: C vs Python — ::var.split(\"delim\") + for-in listener line loop"
FSPL="${ROOT_DIR}/azl/tests/p0_semantic_for_split_line_loop.azl"
set +e
FSPL_C_OUT="$("$MINI_BIN" "$FSPL" boot.entry 2>&1)"
fspl_c_rc=$?
set -e
if [ "$fspl_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_for_split_line_loop exited $fspl_c_rc: $FSPL_C_OUT"
  exit 294
fi
if ! printf '%s\n' "$FSPL_C_OUT" | rg -q '^alpha$'; then
  echo "ERROR: expected alpha line from for/split listener, got: $FSPL_C_OUT"
  exit 294
fi
if ! printf '%s\n' "$FSPL_C_OUT" | rg -q '^beta$'; then
  echo "ERROR: expected beta line, got: $FSPL_C_OUT"
  exit 294
fi
if ! printf '%s\n' "$FSPL_C_OUT" | rg -q '^gamma$'; then
  echo "ERROR: expected gamma line, got: $FSPL_C_OUT"
  exit 294
fi
if ! printf '%s\n' "$FSPL_C_OUT" | rg -q 'P0_SEMANTIC_FOR_SPLIT_OK'; then
  echo "ERROR: expected P0_SEMANTIC_FOR_SPLIT_OK in C output, got: $FSPL_C_OUT"
  exit 294
fi
if ! printf '%s\n' "$FSPL_C_OUT" | awk 'NR==1{if($0!="alpha")exit 1} NR==2{if($0!="beta")exit 1} NR==3{if($0!="gamma")exit 1} NR==4{if($0!="P0_SEMANTIC_FOR_SPLIT_OK")exit 1} END{if(NR!=4)exit 1}'; then
  echo "ERROR: expected stdout order alpha, beta, gamma, P0_SEMANTIC_FOR_SPLIT_OK, got: $FSPL_C_OUT"
  exit 294
fi
set +e
FSPL_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$FSPL" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
fspl_py_rc=$?
set -e
if [ "$fspl_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_for_split_line_loop exited $fspl_py_rc: $FSPL_PY_OUT"
  exit 295
fi
if [ "$FSPL_C_OUT" != "$FSPL_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_for_split_line_loop" >&2
  echo "C:  $FSPL_C_OUT" >&2
  echo "Py: $FSPL_PY_OUT" >&2
  exit 296
fi

echo "[gate] F70: C vs Python — ::global.length in if / expressions"
DLEN="${ROOT_DIR}/azl/tests/p0_semantic_dot_length_global.azl"
set +e
DLEN_C_OUT="$("$MINI_BIN" "$DLEN" boot.entry 2>&1)"
dlen_c_rc=$?
set -e
if [ "$dlen_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_dot_length_global exited $dlen_c_rc: $DLEN_C_OUT"
  exit 297
fi
if ! printf '%s\n' "$DLEN_C_OUT" | rg -q '^ZERO$'; then
  echo "ERROR: expected ZERO line (unset .length == 0), got: $DLEN_C_OUT"
  exit 297
fi
if ! printf '%s\n' "$DLEN_C_OUT" | rg -q '^TWO$'; then
  echo "ERROR: expected TWO line, got: $DLEN_C_OUT"
  exit 297
fi
if ! printf '%s\n' "$DLEN_C_OUT" | rg -q 'P0_SEMANTIC_DOT_LENGTH_OK'; then
  echo "ERROR: expected P0_SEMANTIC_DOT_LENGTH_OK in C output, got: $DLEN_C_OUT"
  exit 297
fi
if ! printf '%s\n' "$DLEN_C_OUT" | awk 'NR==1{if($0!="ZERO")exit 1} NR==2{if($0!="TWO")exit 1} NR==3{if($0!="P0_SEMANTIC_DOT_LENGTH_OK")exit 1} END{if(NR!=3)exit 1}'; then
  echo "ERROR: expected stdout order ZERO, TWO, P0_SEMANTIC_DOT_LENGTH_OK, got: $DLEN_C_OUT"
  exit 297
fi
set +e
DLEN_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$DLEN" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
dlen_py_rc=$?
set -e
if [ "$dlen_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_dot_length_global exited $dlen_py_rc: $DLEN_PY_OUT"
  exit 298
fi
if [ "$DLEN_C_OUT" != "$DLEN_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_dot_length_global" >&2
  echo "C:  $DLEN_C_OUT" >&2
  echo "Py: $DLEN_PY_OUT" >&2
  exit 299
fi

echo "[gate] F71: C vs Python — ::line.split_chars() + for ::c in ::chars"
SCH="${ROOT_DIR}/azl/tests/p0_semantic_split_chars_for.azl"
set +e
SCH_C_OUT="$("$MINI_BIN" "$SCH" boot.entry 2>&1)"
sch_c_rc=$?
set -e
if [ "$sch_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_split_chars_for exited $sch_c_rc: $SCH_C_OUT"
  exit 311
fi
if ! printf '%s\n' "$SCH_C_OUT" | rg -q '^a$'; then
  echo "ERROR: expected a line from split_chars for-loop, got: $SCH_C_OUT"
  exit 311
fi
if ! printf '%s\n' "$SCH_C_OUT" | rg -q '^b$'; then
  echo "ERROR: expected b line, got: $SCH_C_OUT"
  exit 311
fi
if ! printf '%s\n' "$SCH_C_OUT" | rg -q 'P0_SEMANTIC_SPLIT_CHARS_OK'; then
  echo "ERROR: expected P0_SEMANTIC_SPLIT_CHARS_OK in C output, got: $SCH_C_OUT"
  exit 311
fi
if ! printf '%s\n' "$SCH_C_OUT" | awk 'NR==1{if($0!="a")exit 1} NR==2{if($0!="b")exit 1} NR==3{if($0!="P0_SEMANTIC_SPLIT_CHARS_OK")exit 1} END{if(NR!=3)exit 1}'; then
  echo "ERROR: expected stdout order a, b, P0_SEMANTIC_SPLIT_CHARS_OK, got: $SCH_C_OUT"
  exit 311
fi
set +e
SCH_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$SCH" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
sch_py_rc=$?
set -e
if [ "$sch_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_split_chars_for exited $sch_py_rc: $SCH_PY_OUT"
  exit 312
fi
if [ "$SCH_C_OUT" != "$SCH_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_split_chars_for" >&2
  echo "C:  $SCH_C_OUT" >&2
  echo "Py: $SCH_PY_OUT" >&2
  exit 313
fi

echo "[gate] F72: C vs Python — set ::buf.push + for ::row in ::buf"
PSH="${ROOT_DIR}/azl/tests/p0_semantic_push_string_listener.azl"
set +e
PSH_C_OUT="$("$MINI_BIN" "$PSH" boot.entry 2>&1)"
psh_c_rc=$?
set -e
if [ "$psh_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_push_string_listener exited $psh_c_rc: $PSH_C_OUT"
  exit 314
fi
if ! printf '%s\n' "$PSH_C_OUT" | rg -q '^P0_SEMANTIC_PUSH_INIT_OK$'; then
  echo "ERROR: expected P0_SEMANTIC_PUSH_INIT_OK in C output, got: $PSH_C_OUT"
  exit 314
fi
if ! printf '%s\n' "$PSH_C_OUT" | rg -q '^first$'; then
  echo "ERROR: expected first line from push+for, got: $PSH_C_OUT"
  exit 314
fi
if ! printf '%s\n' "$PSH_C_OUT" | rg -q '^second$'; then
  echo "ERROR: expected second line, got: $PSH_C_OUT"
  exit 314
fi
if ! printf '%s\n' "$PSH_C_OUT" | rg -q '^P0_SEMANTIC_PUSH_STRING_OK$'; then
  echo "ERROR: expected P0_SEMANTIC_PUSH_STRING_OK in C output, got: $PSH_C_OUT"
  exit 314
fi
if ! printf '%s\n' "$PSH_C_OUT" | awk 'NR==1{if($0!="P0_SEMANTIC_PUSH_INIT_OK")exit 1} NR==2{if($0!="first")exit 1} NR==3{if($0!="second")exit 1} NR==4{if($0!="P0_SEMANTIC_PUSH_STRING_OK")exit 1} END{if(NR!=4)exit 1}'; then
  echo "ERROR: expected stdout order init_ok, first, second, PUSH_STRING_OK, got: $PSH_C_OUT"
  exit 314
fi
set +e
PSH_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$PSH" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
psh_py_rc=$?
set -e
if [ "$psh_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_push_string_listener exited $psh_py_rc: $PSH_PY_OUT"
  exit 315
fi
if [ "$PSH_C_OUT" != "$PSH_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_push_string_listener" >&2
  echo "C:  $PSH_C_OUT" >&2
  echo "Py: $PSH_PY_OUT" >&2
  exit 316
fi

echo "[gate] F73: C vs Python — integer ::column - ::var.length (tokenize column)"
SUB="${ROOT_DIR}/azl/tests/p0_semantic_int_sub_column_length.azl"
set +e
SUB_C_OUT="$("$MINI_BIN" "$SUB" boot.entry 2>&1)"
sub_c_rc=$?
set -e
if [ "$sub_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_int_sub_column_length exited $sub_c_rc: $SUB_C_OUT"
  exit 317
fi
if ! printf '%s\n' "$SUB_C_OUT" | rg -q '^P0_SEMANTIC_INT_SUB_INIT_OK$'; then
  echo "ERROR: expected P0_SEMANTIC_INT_SUB_INIT_OK in C output, got: $SUB_C_OUT"
  exit 317
fi
if ! printf '%s\n' "$SUB_C_OUT" | rg -q '^3$'; then
  echo "ERROR: expected 3 (5 - len(ab)), got: $SUB_C_OUT"
  exit 317
fi
if ! printf '%s\n' "$SUB_C_OUT" | rg -q '^P0_SEMANTIC_INT_SUB_OK$'; then
  echo "ERROR: expected P0_SEMANTIC_INT_SUB_OK in C output, got: $SUB_C_OUT"
  exit 317
fi
if ! printf '%s\n' "$SUB_C_OUT" | awk 'NR==1{if($0!="P0_SEMANTIC_INT_SUB_INIT_OK")exit 1} NR==2{if($0!="3")exit 1} NR==3{if($0!="P0_SEMANTIC_INT_SUB_OK")exit 1} END{if(NR!=3)exit 1}'; then
  echo "ERROR: expected stdout order init_ok, 3, INT_SUB_OK, got: $SUB_C_OUT"
  exit 317
fi
set +e
SUB_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$SUB" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
sub_py_rc=$?
set -e
if [ "$sub_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_int_sub_column_length exited $sub_py_rc: $SUB_PY_OUT"
  exit 318
fi
if [ "$SUB_C_OUT" != "$SUB_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_int_sub_column_length" >&2
  echo "C:  $SUB_C_OUT" >&2
  echo "Py: $SUB_PY_OUT" >&2
  exit 319
fi

echo "[gate] F74: C vs Python — tokenize in_string + quote toggle + ::handled (split_chars loop)"
INS="${ROOT_DIR}/azl/tests/p0_semantic_tokenize_in_string_char.azl"
set +e
INS_C_OUT="$("$MINI_BIN" "$INS" boot.entry 2>&1)"
ins_c_rc=$?
set -e
if [ "$ins_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_tokenize_in_string_char exited $ins_c_rc: $INS_C_OUT"
  exit 323
fi
if ! printf '%s\n' "$INS_C_OUT" | rg -q '^P0_SEMANTIC_IN_STRING_INIT_OK$'; then
  echo "ERROR: expected P0_SEMANTIC_IN_STRING_INIT_OK in C output, got: $INS_C_OUT"
  exit 323
fi
if ! printf '%s\n' "$INS_C_OUT" | rg -q '^OUTSIDE$'; then
  echo "ERROR: expected OUTSIDE lines in C output, got: $INS_C_OUT"
  exit 323
fi
if ! printf '%s\n' "$INS_C_OUT" | rg -q '^STRING_START$'; then
  echo "ERROR: expected STRING_START in C output, got: $INS_C_OUT"
  exit 323
fi
if ! printf '%s\n' "$INS_C_OUT" | rg -q '^b$'; then
  echo "ERROR: expected literal b (in-string char) in C output, got: $INS_C_OUT"
  exit 323
fi
if ! printf '%s\n' "$INS_C_OUT" | rg -q '^STRING_END$'; then
  echo "ERROR: expected STRING_END in C output, got: $INS_C_OUT"
  exit 323
fi
if ! printf '%s\n' "$INS_C_OUT" | rg -q '^P0_SEMANTIC_IN_STRING_OK$'; then
  echo "ERROR: expected P0_SEMANTIC_IN_STRING_OK in C output, got: $INS_C_OUT"
  exit 323
fi
if ! printf '%s\n' "$INS_C_OUT" | awk 'NR==1{if($0!="P0_SEMANTIC_IN_STRING_INIT_OK")exit 1} NR==2{if($0!="OUTSIDE")exit 1} NR==3{if($0!="STRING_START")exit 1} NR==4{if($0!="b")exit 1} NR==5{if($0!="STRING_END")exit 1} NR==6{if($0!="OUTSIDE")exit 1} NR==7{if($0!="P0_SEMANTIC_IN_STRING_OK")exit 1} END{if(NR!=7)exit 1}'; then
  echo "ERROR: expected stdout order init_ok, OUTSIDE, STRING_START, b, STRING_END, OUTSIDE, IN_STRING_OK, got: $INS_C_OUT"
  exit 323
fi
set +e
INS_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$INS" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
ins_py_rc=$?
set -e
if [ "$ins_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_tokenize_in_string_char exited $ins_py_rc: $INS_PY_OUT"
  exit 324
fi
if [ "$INS_C_OUT" != "$INS_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_tokenize_in_string_char" >&2
  echo "C:  $INS_C_OUT" >&2
  echo "Py: $INS_PY_OUT" >&2
  exit 325
fi

echo "[gate] F75: C vs Python — .push({ type, value, line, column }) + ::acc.concat(::chunk)"
TTZ="${ROOT_DIR}/azl/tests/p0_semantic_tokens_push_tz_concat.azl"
set +e
TTZ_C_OUT="$("$MINI_BIN" "$TTZ" boot.entry 2>&1)"
ttz_c_rc=$?
set -e
if [ "$ttz_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_tokens_push_tz_concat exited $ttz_c_rc: $TTZ_C_OUT"
  exit 326
fi
if ! printf '%s\n' "$TTZ_C_OUT" | rg -q '^P0_SEMANTIC_TOK_TZ_INIT_OK$'; then
  echo "ERROR: expected P0_SEMANTIC_TOK_TZ_INIT_OK in C output, got: $TTZ_C_OUT"
  exit 326
fi
if ! printf '%s\n' "$TTZ_C_OUT" | rg -q '^tz\|eol\|;\|1\|0$'; then
  echo "ERROR: expected tz|eol|;|1|0 row in C output, got: $TTZ_C_OUT"
  exit 326
fi
if ! printf '%s\n' "$TTZ_C_OUT" | rg -q '^tz\|id\|x\|1\|1$'; then
  echo "ERROR: expected tz|id|x|1|1 row in C output, got: $TTZ_C_OUT"
  exit 326
fi
if ! printf '%s\n' "$TTZ_C_OUT" | rg -q '^P0_SEMANTIC_TOK_TZ_OK$'; then
  echo "ERROR: expected P0_SEMANTIC_TOK_TZ_OK in C output, got: $TTZ_C_OUT"
  exit 326
fi
if ! printf '%s\n' "$TTZ_C_OUT" | awk 'NR==1{if($0!="P0_SEMANTIC_TOK_TZ_INIT_OK")exit 1} NR==2{if($0!="tz|eol|;|1|0")exit 1} NR==3{if($0!="tz|id|x|1|1")exit 1} NR==4{if($0!="P0_SEMANTIC_TOK_TZ_OK")exit 1} END{if(NR!=4)exit 1}'; then
  echo "ERROR: expected stdout order init_ok, eol row, id row, TOK_TZ_OK, got: $TTZ_C_OUT"
  exit 326
fi
set +e
TTZ_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$TTZ" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
ttz_py_rc=$?
set -e
if [ "$ttz_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_tokens_push_tz_concat exited $ttz_py_rc: $TTZ_PY_OUT"
  exit 327
fi
if [ "$TTZ_C_OUT" != "$TTZ_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_tokens_push_tz_concat" >&2
  echo "C:  $TTZ_C_OUT" >&2
  echo "Py: $TTZ_PY_OUT" >&2
  exit 328
fi

echo "[gate] F76: C vs Python — ::line + 1 and ::current + ::c (tokenize_line loop)"
INC="${ROOT_DIR}/azl/tests/p0_semantic_tokenize_line_inc_concat.azl"
set +e
INC_C_OUT="$("$MINI_BIN" "$INC" boot.entry 2>&1)"
inc_c_rc=$?
set -e
if [ "$inc_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_tokenize_line_inc_concat exited $inc_c_rc: $INC_C_OUT"
  exit 329
fi
if ! printf '%s\n' "$INC_C_OUT" | rg -q '^P0_SEMANTIC_TOK_INCR_INIT_OK$'; then
  echo "ERROR: expected P0_SEMANTIC_TOK_INCR_INIT_OK in C output, got: $INC_C_OUT"
  exit 329
fi
if ! printf '%s\n' "$INC_C_OUT" | rg -q '^2$'; then
  echo "ERROR: expected 2 (::line + 1) in C output, got: $INC_C_OUT"
  exit 329
fi
if ! printf '%s\n' "$INC_C_OUT" | rg -q '^ab$'; then
  echo "ERROR: expected ab (::current + ::c loop) in C output, got: $INC_C_OUT"
  exit 329
fi
if ! printf '%s\n' "$INC_C_OUT" | rg -q '^P0_SEMANTIC_TOK_INCR_OK$'; then
  echo "ERROR: expected P0_SEMANTIC_TOK_INCR_OK in C output, got: $INC_C_OUT"
  exit 329
fi
if ! printf '%s\n' "$INC_C_OUT" | awk 'NR==1{if($0!="P0_SEMANTIC_TOK_INCR_INIT_OK")exit 1} NR==2{if($0!="2")exit 1} NR==3{if($0!="ab")exit 1} NR==4{if($0!="P0_SEMANTIC_TOK_INCR_OK")exit 1} END{if(NR!=4)exit 1}'; then
  echo "ERROR: expected stdout order init_ok, 2, ab, TOK_INCR_OK, got: $INC_C_OUT"
  exit 329
fi
set +e
INC_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$INC" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
inc_py_rc=$?
set -e
if [ "$inc_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_tokenize_line_inc_concat exited $inc_py_rc: $INC_PY_OUT"
  exit 330
fi
if [ "$INC_C_OUT" != "$INC_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_tokenize_line_inc_concat" >&2
  echo "C:  $INC_C_OUT" >&2
  echo "Py: $INC_PY_OUT" >&2
  exit 331
fi

echo "[gate] F77: C vs Python — tokenize outer loop (split \\n, for line, concat, eol push, ::var in object push)"
OUTL="${ROOT_DIR}/azl/tests/p0_semantic_tokenize_outer_line_loop.azl"
set +e
OUTL_C_OUT="$("$MINI_BIN" "$OUTL" boot.entry 2>&1)"
outl_c_rc=$?
set -e
if [ "$outl_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_tokenize_outer_line_loop exited $outl_c_rc: $OUTL_C_OUT"
  exit 332
fi
if ! printf '%s\n' "$OUTL_C_OUT" | rg -q '^P0_SEMANTIC_TOK_OUTER_INIT_OK$'; then
  echo "ERROR: expected P0_SEMANTIC_TOK_OUTER_INIT_OK in C output, got: $OUTL_C_OUT"
  exit 332
fi
if ! printf '%s\n' "$OUTL_C_OUT" | rg -q '^tz\|id\|x\|1\|1$'; then
  echo "ERROR: expected tz|id|x|1|1 in C output, got: $OUTL_C_OUT"
  exit 332
fi
if ! printf '%s\n' "$OUTL_C_OUT" | rg -q '^tz\|eol\|;\|1\|0$'; then
  echo "ERROR: expected tz|eol|;|1|0 in C output, got: $OUTL_C_OUT"
  exit 332
fi
if ! printf '%s\n' "$OUTL_C_OUT" | rg -q '^tz\|id\|y\|2\|1$'; then
  echo "ERROR: expected tz|id|y|2|1 in C output, got: $OUTL_C_OUT"
  exit 332
fi
if ! printf '%s\n' "$OUTL_C_OUT" | rg -q '^tz\|eol\|;\|2\|0$'; then
  echo "ERROR: expected tz|eol|;|2|0 in C output, got: $OUTL_C_OUT"
  exit 332
fi
if ! printf '%s\n' "$OUTL_C_OUT" | rg -q '^P0_SEMANTIC_TOK_OUTER_OK$'; then
  echo "ERROR: expected P0_SEMANTIC_TOK_OUTER_OK in C output, got: $OUTL_C_OUT"
  exit 332
fi
if ! printf '%s\n' "$OUTL_C_OUT" | awk 'NR==1{if($0!="P0_SEMANTIC_TOK_OUTER_INIT_OK")exit 1} NR==2{if($0!="tz|id|x|1|1")exit 1} NR==3{if($0!="tz|eol|;|1|0")exit 1} NR==4{if($0!="tz|id|y|2|1")exit 1} NR==5{if($0!="tz|eol|;|2|0")exit 1} NR==6{if($0!="P0_SEMANTIC_TOK_OUTER_OK")exit 1} END{if(NR!=6)exit 1}'; then
  echo "ERROR: expected stdout order for tokenize outer loop, got: $OUTL_C_OUT"
  exit 332
fi
set +e
OUTL_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$OUTL" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
outl_py_rc=$?
set -e
if [ "$outl_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_tokenize_outer_line_loop exited $outl_py_rc: $OUTL_PY_OUT"
  exit 333
fi
if [ "$OUTL_C_OUT" != "$OUTL_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_tokenize_outer_line_loop" >&2
  echo "C:  $OUTL_C_OUT" >&2
  echo "Py: $OUTL_PY_OUT" >&2
  exit 334
fi

echo "[gate] F78: C vs Python — say double-quoted ::path / ::path.length (single quotes literal)"
DIP="${ROOT_DIR}/azl/tests/p0_semantic_say_double_interpolate.azl"
set +e
DIP_C_OUT="$("$MINI_BIN" "$DIP" boot.entry 2>&1)"
dip_c_rc=$?
set -e
if [ "$dip_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_say_double_interpolate exited $dip_c_rc: $DIP_C_OUT"
  exit 335
fi
if ! printf '%s\n' "$DIP_C_OUT" | rg -q '^P0_SEM_SAY_DIP_INIT$'; then
  echo "ERROR: expected P0_SEM_SAY_DIP_INIT in C output, got: $DIP_C_OUT"
  exit 335
fi
if ! printf '%s\n' "$DIP_C_OUT" | rg -q '^V=ab$'; then
  echo "ERROR: expected V=ab in C output, got: $DIP_C_OUT"
  exit 335
fi
if ! printf '%s\n' "$DIP_C_OUT" | rg -q '^LEN=2$'; then
  echo "ERROR: expected LEN=2 in C output, got: $DIP_C_OUT"
  exit 335
fi
if ! printf '%s\n' "$DIP_C_OUT" | rg -q '^DOT=9$'; then
  echo "ERROR: expected DOT=9 in C output, got: $DIP_C_OUT"
  exit 335
fi
if ! printf '%s\n' "$DIP_C_OUT" | rg -q '^NONE=\|Z$'; then
  echo "ERROR: expected NONE=|Z in C output, got: $DIP_C_OUT"
  exit 335
fi
if ! printf '%s\n' "$DIP_C_OUT" | rg -q '^LIT=::msg$'; then
  echo "ERROR: expected LIT=::msg in C output, got: $DIP_C_OUT"
  exit 335
fi
if ! printf '%s\n' "$DIP_C_OUT" | rg -q '^P0_SEM_SAY_DIP_OK$'; then
  echo "ERROR: expected P0_SEM_SAY_DIP_OK in C output, got: $DIP_C_OUT"
  exit 335
fi
if ! printf '%s\n' "$DIP_C_OUT" | awk 'NR==1{if($0!="P0_SEM_SAY_DIP_INIT")exit 1} NR==2{if($0!="V=ab")exit 1} NR==3{if($0!="LEN=2")exit 1} NR==4{if($0!="DOT=9")exit 1} NR==5{if($0!="NONE=|Z")exit 1} NR==6{if($0!="LIT=::msg")exit 1} NR==7{if($0!="P0_SEM_SAY_DIP_OK")exit 1} END{if(NR!=7)exit 1}'; then
  echo "ERROR: expected stdout order for say double interpolate, got: $DIP_C_OUT"
  exit 335
fi
set +e
DIP_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$DIP" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
dip_py_rc=$?
set -e
if [ "$dip_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_say_double_interpolate exited $dip_py_rc: $DIP_PY_OUT"
  exit 336
fi
if [ "$DIP_C_OUT" != "$DIP_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_say_double_interpolate" >&2
  echo "C:  $DIP_C_OUT" >&2
  echo "Py: $DIP_PY_OUT" >&2
  exit 337
fi

echo "[gate] F79: C vs Python — emit with payload value ::var resolved at emit time"
EPV="${ROOT_DIR}/azl/tests/p0_semantic_emit_payload_var_bind.azl"
set +e
EPV_C_OUT="$("$MINI_BIN" "$EPV" boot.entry 2>&1)"
epv_c_rc=$?
set -e
if [ "$epv_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_emit_payload_var_bind exited $epv_c_rc: $EPV_C_OUT"
  exit 338
fi
if ! printf '%s\n' "$EPV_C_OUT" | rg -q '^carry-bytes$'; then
  echo "ERROR: expected carry-bytes in C output, got: $EPV_C_OUT"
  exit 338
fi
if ! printf '%s\n' "$EPV_C_OUT" | rg -q '^P0_SEMANTIC_EMIT_PAYLOAD_VAR_OK$'; then
  echo "ERROR: expected P0_SEMANTIC_EMIT_PAYLOAD_VAR_OK in C output, got: $EPV_C_OUT"
  exit 338
fi
if ! printf '%s\n' "$EPV_C_OUT" | awk 'NR==1{if($0!="carry-bytes")exit 1} NR==2{if($0!="P0_SEMANTIC_EMIT_PAYLOAD_VAR_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected stdout order for emit payload ::var bind, got: $EPV_C_OUT"
  exit 338
fi
set +e
EPV_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$EPV" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
epv_py_rc=$?
set -e
if [ "$epv_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_emit_payload_var_bind exited $epv_py_rc: $EPV_PY_OUT"
  exit 339
fi
if [ "$EPV_C_OUT" != "$EPV_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_emit_payload_var_bind" >&2
  echo "C:  $EPV_C_OUT" >&2
  echo "Py: $EPV_PY_OUT" >&2
  exit 340
fi

echo "[gate] F80: C vs Python — tokenize cache-miss branch (::cached_tok != null, tok_misses + 1)"
TCM="${ROOT_DIR}/azl/tests/p0_semantic_tokenize_cache_miss_branch.azl"
set +e
TCM_C_OUT="$("$MINI_BIN" "$TCM" boot.entry 2>&1)"
tcm_c_rc=$?
set -e
if [ "$tcm_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_tokenize_cache_miss_branch exited $tcm_c_rc: $TCM_C_OUT"
  exit 341
fi
if ! printf '%s\n' "$TCM_C_OUT" | rg -q '^CACHE_MISS$'; then
  echo "ERROR: expected CACHE_MISS in C output, got: $TCM_C_OUT"
  exit 341
fi
if ! printf '%s\n' "$TCM_C_OUT" | rg -q '^1$'; then
  echo "ERROR: expected 1 (tok_misses) in C output, got: $TCM_C_OUT"
  exit 341
fi
if ! printf '%s\n' "$TCM_C_OUT" | rg -q '^P0_SEM_TOK_CACHE_MISS_OK$'; then
  echo "ERROR: expected P0_SEM_TOK_CACHE_MISS_OK in C output, got: $TCM_C_OUT"
  exit 341
fi
if ! printf '%s\n' "$TCM_C_OUT" | awk 'NR==1{if($0!="CACHE_MISS")exit 1} NR==2{if($0!="1")exit 1} NR==3{if($0!="P0_SEM_TOK_CACHE_MISS_OK")exit 1} END{if(NR!=3)exit 1}'; then
  echo "ERROR: expected stdout order CACHE_MISS, 1, OK for tokenize cache miss branch, got: $TCM_C_OUT"
  exit 341
fi
set +e
TCM_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$TCM" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
tcm_py_rc=$?
set -e
if [ "$tcm_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_tokenize_cache_miss_branch exited $tcm_py_rc: $TCM_PY_OUT"
  exit 342
fi
if [ "$TCM_C_OUT" != "$TCM_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_tokenize_cache_miss_branch" >&2
  echo "C:  $TCM_C_OUT" >&2
  echo "Py: $TCM_PY_OUT" >&2
  exit 343
fi

echo "[gate] F81: C vs Python — tokenize cache-hit branch (tok_hits + 1, ::tokens = ::cached_tok, return)"
TCH="${ROOT_DIR}/azl/tests/p0_semantic_tokenize_cache_hit_branch.azl"
set +e
TCH_C_OUT="$("$MINI_BIN" "$TCH" boot.entry 2>&1)"
tch_c_rc=$?
set -e
if [ "$tch_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_tokenize_cache_hit_branch exited $tch_c_rc: $TCH_C_OUT"
  exit 344
fi
if ! printf '%s\n' "$TCH_C_OUT" | rg -q '^CACHE_HIT$'; then
  echo "ERROR: expected CACHE_HIT in C output, got: $TCH_C_OUT"
  exit 344
fi
if ! printf '%s\n' "$TCH_C_OUT" | rg -q '^1$'; then
  echo "ERROR: expected 1 (tok_hits) in C output, got: $TCH_C_OUT"
  exit 344
fi
if ! printf '%s\n' "$TCH_C_OUT" | rg -q '^hit-body$'; then
  echo "ERROR: expected hit-body (::tokens from cache) in C output, got: $TCH_C_OUT"
  exit 344
fi
if ! printf '%s\n' "$TCH_C_OUT" | rg -q '^P0_SEM_TOK_CACHE_HIT_OK$'; then
  echo "ERROR: expected P0_SEM_TOK_CACHE_HIT_OK in C output, got: $TCH_C_OUT"
  exit 344
fi
if ! printf '%s\n' "$TCH_C_OUT" | awk 'NR==1{if($0!="CACHE_HIT")exit 1} NR==2{if($0!="1")exit 1} NR==3{if($0!="hit-body")exit 1} NR==4{if($0!="P0_SEM_TOK_CACHE_HIT_OK")exit 1} END{if(NR!=4)exit 1}'; then
  echo "ERROR: expected stdout order CACHE_HIT, 1, hit-body, OK for tokenize cache hit branch, got: $TCH_C_OUT"
  exit 344
fi
set +e
TCH_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$TCH" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
tch_py_rc=$?
set -e
if [ "$tch_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_tokenize_cache_hit_branch exited $tch_py_rc: $TCH_PY_OUT"
  exit 345
fi
if [ "$TCH_C_OUT" != "$TCH_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_tokenize_cache_hit_branch" >&2
  echo "C:  $TCH_C_OUT" >&2
  echo "Py: $TCH_PY_OUT" >&2
  exit 346
fi

echo "[gate] F82: C vs Python — cache hit + emit tokenize_complete { tokens: ::tokens }"
THEC="${ROOT_DIR}/azl/tests/p0_semantic_tokenize_cache_hit_emit_complete.azl"
set +e
THEC_C_OUT="$("$MINI_BIN" "$THEC" boot.entry 2>&1)"
thec_c_rc=$?
set -e
if [ "$thec_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_tokenize_cache_hit_emit_complete exited $thec_c_rc: $THEC_C_OUT"
  exit 347
fi
if ! printf '%s\n' "$THEC_C_OUT" | rg -q '^CACHE_HIT$'; then
  echo "ERROR: expected CACHE_HIT in C output, got: $THEC_C_OUT"
  exit 347
fi
if ! printf '%s\n' "$THEC_C_OUT" | rg -q '^TC_INNER$'; then
  echo "ERROR: expected TC_INNER in C output, got: $THEC_C_OUT"
  exit 347
fi
if ! printf '%s\n' "$THEC_C_OUT" | rg -q '^hit-body$'; then
  echo "ERROR: expected hit-body (::event.data.tokens) in C output, got: $THEC_C_OUT"
  exit 347
fi
if ! printf '%s\n' "$THEC_C_OUT" | rg -q '^P0_SEM_F82_OK$'; then
  echo "ERROR: expected P0_SEM_F82_OK in C output, got: $THEC_C_OUT"
  exit 347
fi
if ! printf '%s\n' "$THEC_C_OUT" | awk 'NR==1{if($0!="CACHE_HIT")exit 1} NR==2{if($0!="TC_INNER")exit 1} NR==3{if($0!="hit-body")exit 1} NR==4{if($0!="P0_SEM_F82_OK")exit 1} END{if(NR!=4)exit 1}'; then
  echo "ERROR: expected stdout order CACHE_HIT, TC_INNER, hit-body, P0_SEM_F82_OK for F82, got: $THEC_C_OUT"
  exit 347
fi
set +e
THEC_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$THEC" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
thec_py_rc=$?
set -e
if [ "$thec_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_tokenize_cache_hit_emit_complete exited $thec_py_rc: $THEC_PY_OUT"
  exit 348
fi
if [ "$THEC_C_OUT" != "$THEC_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_tokenize_cache_hit_emit_complete" >&2
  echo "C:  $THEC_C_OUT" >&2
  echo "Py: $THEC_PY_OUT" >&2
  exit 349
fi

echo "[gate] F83: C vs Python — parse cache-miss (::tokens from payload, ast_misses + 1)"
PCM="${ROOT_DIR}/azl/tests/p0_semantic_parse_cache_miss_branch.azl"
set +e
PCM_C_OUT="$("$MINI_BIN" "$PCM" boot.entry 2>&1)"
pcm_c_rc=$?
set -e
if [ "$pcm_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_cache_miss_branch exited $pcm_c_rc: $PCM_C_OUT"
  exit 350
fi
if ! printf '%s\n' "$PCM_C_OUT" | rg -q '^seed-toks$'; then
  echo "ERROR: expected seed-toks in C output, got: $PCM_C_OUT"
  exit 350
fi
if ! printf '%s\n' "$PCM_C_OUT" | rg -q '^PARSE_MISS$'; then
  echo "ERROR: expected PARSE_MISS in C output, got: $PCM_C_OUT"
  exit 350
fi
if ! printf '%s\n' "$PCM_C_OUT" | rg -q '^1$'; then
  echo "ERROR: expected 1 (ast_misses) in C output, got: $PCM_C_OUT"
  exit 350
fi
if ! printf '%s\n' "$PCM_C_OUT" | rg -q '^P0_SEM_PARSE_CACHE_MISS_OK$'; then
  echo "ERROR: expected P0_SEM_PARSE_CACHE_MISS_OK in C output, got: $PCM_C_OUT"
  exit 350
fi
if ! printf '%s\n' "$PCM_C_OUT" | awk 'NR==1{if($0!="seed-toks")exit 1} NR==2{if($0!="PARSE_MISS")exit 1} NR==3{if($0!="1")exit 1} NR==4{if($0!="P0_SEM_PARSE_CACHE_MISS_OK")exit 1} END{if(NR!=4)exit 1}'; then
  echo "ERROR: expected stdout order for parse cache miss, got: $PCM_C_OUT"
  exit 350
fi
set +e
PCM_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$PCM" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
pcm_py_rc=$?
set -e
if [ "$pcm_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_cache_miss_branch exited $pcm_py_rc: $PCM_PY_OUT"
  exit 351
fi
if [ "$PCM_C_OUT" != "$PCM_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_cache_miss_branch" >&2
  echo "C:  $PCM_C_OUT" >&2
  echo "Py: $PCM_PY_OUT" >&2
  exit 352
fi

echo "[gate] F84: C vs Python — parse cache-hit (ast_hits + 1, ::ast = ::cached_ast, return)"
PCH="${ROOT_DIR}/azl/tests/p0_semantic_parse_cache_hit_branch.azl"
set +e
PCH_C_OUT="$("$MINI_BIN" "$PCH" boot.entry 2>&1)"
pch_c_rc=$?
set -e
if [ "$pch_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_cache_hit_branch exited $pch_c_rc: $PCH_C_OUT"
  exit 353
fi
if ! printf '%s\n' "$PCH_C_OUT" | awk 'NR==1{if($0!="seed-toks")exit 1} NR==2{if($0!="PARSE_HIT")exit 1} NR==3{if($0!="1")exit 1} NR==4{if($0!="ast-node")exit 1} NR==5{if($0!="P0_SEM_PARSE_CACHE_HIT_OK")exit 1} END{if(NR!=5)exit 1}'; then
  echo "ERROR: expected stdout order for parse cache hit branch, got: $PCH_C_OUT"
  exit 353
fi
set +e
PCH_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$PCH" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
pch_py_rc=$?
set -e
if [ "$pch_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_cache_hit_branch exited $pch_py_rc: $PCH_PY_OUT"
  exit 354
fi
if [ "$PCH_C_OUT" != "$PCH_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_cache_hit_branch" >&2
  echo "C:  $PCH_C_OUT" >&2
  echo "Py: $PCH_PY_OUT" >&2
  exit 355
fi

echo "[gate] F85: C vs Python — parse cache hit + emit parse_complete { ast: ::ast }"
PCE="${ROOT_DIR}/azl/tests/p0_semantic_parse_cache_hit_emit_complete.azl"
set +e
PCE_C_OUT="$("$MINI_BIN" "$PCE" boot.entry 2>&1)"
pce_c_rc=$?
set -e
if [ "$pce_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_cache_hit_emit_complete exited $pce_c_rc: $PCE_C_OUT"
  exit 356
fi
if ! printf '%s\n' "$PCE_C_OUT" | awk 'NR==1{if($0!="seed-toks")exit 1} NR==2{if($0!="PARSE_HIT")exit 1} NR==3{if($0!="PC_INNER")exit 1} NR==4{if($0!="ast-body")exit 1} NR==5{if($0!="P0_SEM_F85_OK")exit 1} END{if(NR!=5)exit 1}'; then
  echo "ERROR: expected stdout order for parse cache hit emit complete, got: $PCE_C_OUT"
  exit 356
fi
set +e
PCE_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$PCE" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
pce_py_rc=$?
set -e
if [ "$pce_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_cache_hit_emit_complete exited $pce_py_rc: $PCE_PY_OUT"
  exit 357
fi
if [ "$PCE_C_OUT" != "$PCE_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_cache_hit_emit_complete" >&2
  echo "C:  $PCE_C_OUT" >&2
  echo "Py: $PCE_PY_OUT" >&2
  exit 358
fi

echo "[gate] F86: C vs Python — execute ast/scope payload + emit execute_complete { result: ::result }"
EEC="${ROOT_DIR}/azl/tests/p0_semantic_execute_payload_emit_complete.azl"
set +e
EEC_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$EEC" boot.entry 2>&1)"
eec_c_rc=$?
set -e
if [ "$eec_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_payload_emit_complete exited $eec_c_rc: $EEC_C_OUT"
  exit 359
fi
if ! printf '%s\n' "$EEC_C_OUT" | awk 'NR==1{if($0!="ast-body")exit 1} NR==2{if($0!="scope-body")exit 1} NR==3{if($0!="EXEC_LINE")exit 1} NR==4{if($0!="EC_INNER")exit 1} NR==5{if($0!="tw-result")exit 1} NR==6{if($0!="P0_SEM_F86_OK")exit 1} END{if(NR!=6)exit 1}'; then
  echo "ERROR: expected stdout order for execute payload emit complete, got: $EEC_C_OUT"
  exit 359
fi
set +e
EEC_PY_OUT="$(env -u AZL_INTERPRETER_DAEMON -u AZL_USE_VM AZL_COMBINED_PATH="$EEC" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
eec_py_rc=$?
set -e
if [ "$eec_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_payload_emit_complete exited $eec_py_rc: $EEC_PY_OUT"
  exit 360
fi
if [ "$EEC_C_OUT" != "$EEC_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_payload_emit_complete" >&2
  echo "C:  $EEC_C_OUT" >&2
  echo "Py: $EEC_PY_OUT" >&2
  exit 361
fi

echo "[gate] F87: C vs Python — AZL_USE_VM env off branch ((env or \"\") == \"1\")"
UVO="${ROOT_DIR}/azl/tests/p0_semantic_execute_use_vm_env_off.azl"
set +e
UVO_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$UVO" boot.entry 2>&1)"
uvo_c_rc=$?
set -e
if [ "$uvo_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_use_vm_env_off exited $uvo_c_rc: $UVO_C_OUT"
  exit 362
fi
if ! printf '%s\n' "$UVO_C_OUT" | rg -q '^P0_SEM_USE_VM_OFF_OK$'; then
  echo "ERROR: expected P0_SEM_USE_VM_OFF_OK (AZL_USE_VM must be unset for F87), got: $UVO_C_OUT"
  exit 362
fi
if ! printf '%s\n' "$UVO_C_OUT" | awk 'NR==1{if($0!="P0_SEM_USE_VM_OFF_OK")exit 1} END{if(NR!=1)exit 1}'; then
  echo "ERROR: expected single-line stdout for use_vm env off probe, got: $UVO_C_OUT"
  exit 362
fi
set +e
UVO_PY_OUT="$(env -u AZL_INTERPRETER_DAEMON -u AZL_USE_VM AZL_COMBINED_PATH="$UVO" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
uvo_py_rc=$?
set -e
if [ "$uvo_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_use_vm_env_off exited $uvo_py_rc: $UVO_PY_OUT"
  exit 363
fi
if [ "$UVO_C_OUT" != "$UVO_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_use_vm_env_off" >&2
  echo "C:  $UVO_C_OUT" >&2
  echo "Py: $UVO_PY_OUT" >&2
  exit 364
fi

echo "[gate] F88: C vs Python — halt_execution listener (emit from listener, set ::halted = true)"
HALT88="${ROOT_DIR}/azl/tests/p0_semantic_halt_execution_listener.azl"
set +e
HALT88_C_OUT="$("$MINI_BIN" "$HALT88" boot.entry 2>&1)"
halt88_c_rc=$?
set -e
if [ "$halt88_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_halt_execution_listener exited $halt88_c_rc: $HALT88_C_OUT"
  exit 365
fi
if ! printf '%s\n' "$HALT88_C_OUT" | awk 'NR==1{if($0!="P0_HALT_SIGNAL_OK")exit 1} NR==2{if($0!="P0_SEM_F88_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected halt_execution stdout order (P0_HALT_SIGNAL_OK then P0_SEM_F88_OK), got: $HALT88_C_OUT"
  exit 365
fi
set +e
HALT88_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$HALT88" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
halt88_py_rc=$?
set -e
if [ "$halt88_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_halt_execution_listener exited $halt88_py_rc: $HALT88_PY_OUT"
  exit 366
fi
if [ "$HALT88_C_OUT" != "$HALT88_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_halt_execution_listener" >&2
  echo "C:  $HALT88_C_OUT" >&2
  echo "Py: $HALT88_PY_OUT" >&2
  exit 367
fi

echo "[gate] F89: C vs Python — execute preloop ::ast / ::ast.nodes guard (&&) + for-in nodes"
F89AST="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_nodes_preloop.azl"
set +e
F89_C_OUT="$("$MINI_BIN" "$F89AST" boot.entry 2>&1)"
f89_c_rc=$?
set -e
if [ "$f89_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_nodes_preloop exited $f89_c_rc: $F89_C_OUT"
  exit 368
fi
if ! printf '%s\n' "$F89_C_OUT" | awk 'NR==1{if($0!="P89_PRELOOP_ENTER")exit 1} NR==2{if($0!="import")exit 1} NR==3{if($0!="link")exit 1} NR==4{if($0!="P89_PRELOOP_DONE")exit 1} NR==5{if($0!="EXEC_F89")exit 1} NR==6{if($0!="EC89_INNER")exit 1} NR==7{if($0!="p89-tw")exit 1} NR==8{if($0!="P0_SEM_F89_OK")exit 1} END{if(NR!=8)exit 1}'; then
  echo "ERROR: expected F89 execute ast.nodes preloop stdout order, got: $F89_C_OUT"
  exit 368
fi
set +e
F89_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_COMBINED_PATH="$F89AST" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f89_py_rc=$?
set -e
if [ "$f89_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_nodes_preloop exited $f89_py_rc: $F89_PY_OUT"
  exit 369
fi
if [ "$F89_C_OUT" != "$F89_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_nodes_preloop" >&2
  echo "C:  $F89_C_OUT" >&2
  echo "Py: $F89_PY_OUT" >&2
  exit 370
fi

echo "[gate] F90: C vs Python — AZL_USE_VM=1 vm_compile_ast ok + vm_run_bytecode_program"
F90VM="${ROOT_DIR}/azl/tests/p0_semantic_execute_vm_path_ok.azl"
set +e
F90_C_OUT="$(AZL_USE_VM=1 "$MINI_BIN" "$F90VM" boot.entry 2>&1)"
f90_c_rc=$?
set -e
if [ "$f90_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_vm_path_ok exited $f90_c_rc: $F90_C_OUT"
  exit 371
fi
if ! printf '%s\n' "$F90_C_OUT" | awk 'NR==1{if($0!="VM_BRANCH")exit 1} NR==2{if($0!="VM_LINE")exit 1} NR==3{if($0!="EC90_INNER")exit 1} NR==4{if($0!="P0_VM_EXEC_OK")exit 1} NR==5{if($0!="P0_SEM_F90_VM_OK")exit 1} END{if(NR!=5)exit 1}'; then
  echo "ERROR: expected F90 VM ok-path stdout (5 lines), got: $F90_C_OUT"
  exit 371
fi
set +e
F90_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_USE_VM=1 AZL_COMBINED_PATH="$F90VM" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f90_py_rc=$?
set -e
if [ "$f90_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_vm_path_ok exited $f90_py_rc: $F90_PY_OUT"
  exit 372
fi
if [ "$F90_C_OUT" != "$F90_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_vm_path_ok" >&2
  echo "C:  $F90_C_OUT" >&2
  echo "Py: $F90_PY_OUT" >&2
  exit 373
fi

echo "[gate] F91: C vs Python — AZL_USE_VM=1 vm_compile_ast failure branch"
F91VM="${ROOT_DIR}/azl/tests/p0_semantic_execute_vm_compile_error.azl"
set +e
F91_C_OUT="$(AZL_USE_VM=1 "$MINI_BIN" "$F91VM" boot.entry 2>&1)"
f91_c_rc=$?
set -e
if [ "$f91_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_vm_compile_error exited $f91_c_rc: $F91_C_OUT"
  exit 374
fi
if ! printf '%s\n' "$F91_C_OUT" | awk 'NR==1{if($0!="F91_COMPILE_FAIL")exit 1} NR==2{if($0!="EC91_INNER")exit 1} NR==3{if($0!="vm_compile_error:compile_failed")exit 1} NR==4{if($0!="P0_SEM_F91_VM_OK")exit 1} END{if(NR!=4)exit 1}'; then
  echo "ERROR: expected F91 VM compile-error stdout (4 lines), got: $F91_C_OUT"
  exit 374
fi
set +e
F91_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_USE_VM=1 AZL_COMBINED_PATH="$F91VM" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f91_py_rc=$?
set -e
if [ "$f91_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_vm_compile_error exited $f91_py_rc: $F91_PY_OUT"
  exit 375
fi
if [ "$F91_C_OUT" != "$F91_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_vm_compile_error" >&2
  echo "C:  $F91_C_OUT" >&2
  echo "Py: $F91_PY_OUT" >&2
  exit 376
fi

echo "[gate] F92: C vs Python — AZL_USE_VM=1 vm empty bytecode branch"
F92VM="${ROOT_DIR}/azl/tests/p0_semantic_execute_vm_empty_bytecode.azl"
set +e
F92_C_OUT="$(AZL_USE_VM=1 "$MINI_BIN" "$F92VM" boot.entry 2>&1)"
f92_c_rc=$?
set -e
if [ "$f92_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_vm_empty_bytecode exited $f92_c_rc: $F92_C_OUT"
  exit 377
fi
if ! printf '%s\n' "$F92_C_OUT" | awk 'NR==1{if($0!="F92_EMPTY_BRANCH")exit 1} NR==2{if($0!="EC92_INNER")exit 1} NR==3{if($0!="vm_compile_error:vm_compile_empty")exit 1} NR==4{if($0!="P0_SEM_F92_VM_OK")exit 1} END{if(NR!=4)exit 1}'; then
  echo "ERROR: expected F92 VM empty-bytecode stdout (4 lines), got: $F92_C_OUT"
  exit 377
fi
set +e
F92_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; AZL_USE_VM=1 AZL_COMBINED_PATH="$F92VM" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f92_py_rc=$?
set -e
if [ "$f92_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_vm_empty_bytecode exited $f92_py_rc: $F92_PY_OUT"
  exit 378
fi
if [ "$F92_C_OUT" != "$F92_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_vm_empty_bytecode" >&2
  echo "C:  $F92_C_OUT" >&2
  echo "Py: $F92_PY_OUT" >&2
  exit 379
fi

echo "[gate] F93: C vs Python — execute_ast tree-walk (AZL_USE_VM off, ::ast.nodes say| steps)"
F93EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_tree_walk.azl"
F93_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F93EX" boot.entry 2>&1)"
f93_c_rc=$?
if [ "$f93_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_tree_walk exited $f93_c_rc: $F93_C_OUT"
  exit 380
fi
if ! printf '%s\n' "$F93_C_OUT" | awk 'NR==1{if($0!="TREE_BRANCH")exit 1} NR==2{if($0!="F93_LINE_A")exit 1} NR==3{if($0!="F93_LINE_B")exit 1} NR==4{if($0!="EX93_POST")exit 1} NR==5{if($0!="Said: F93_LINE_B")exit 1} NR==6{if($0!="EC93_INNER")exit 1} NR==7{if($0!="Said: F93_LINE_B")exit 1} NR==8{if($0!="P0_SEM_F93_OK")exit 1} END{if(NR!=8)exit 1}'; then
  echo "ERROR: expected F93 execute_ast stdout (8 lines), got: $F93_C_OUT"
  exit 380
fi
F93_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F93EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f93_py_rc=$?
if [ "$f93_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_tree_walk exited $f93_py_rc: $F93_PY_OUT"
  exit 381
fi
if [ "$F93_C_OUT" != "$F93_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_tree_walk" >&2
  echo "C:  $F93_C_OUT" >&2
  echo "Py: $F93_PY_OUT" >&2
  exit 382
fi

echo "[gate] F94: C vs Python — execute_ast emit| step (bare emit + listener drain)"
F94EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_emit_step.azl"
F94_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F94EX" boot.entry 2>&1)"
f94_c_rc=$?
if [ "$f94_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_emit_step exited $f94_c_rc: $F94_C_OUT"
  exit 383
fi
if ! printf '%s\n' "$F94_C_OUT" | awk 'NR==1{if($0!="F94_TREE")exit 1} NR==2{if($0!="F94_A")exit 1} NR==3{if($0!="F94_INNER_BODY")exit 1} NR==4{if($0!="EX94_POST")exit 1} NR==5{if($0!="Emitted: f94_inner")exit 1} NR==6{if($0!="EC94_INNER")exit 1} NR==7{if($0!="Emitted: f94_inner")exit 1} NR==8{if($0!="P0_SEM_F94_OK")exit 1} END{if(NR!=8)exit 1}'; then
  echo "ERROR: expected F94 execute_ast emit stdout (8 lines), got: $F94_C_OUT"
  exit 383
fi
F94_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F94EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f94_py_rc=$?
if [ "$f94_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_emit_step exited $f94_py_rc: $F94_PY_OUT"
  exit 384
fi
if [ "$F94_C_OUT" != "$F94_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_emit_step" >&2
  echo "C:  $F94_C_OUT" >&2
  echo "Py: $F94_PY_OUT" >&2
  exit 385
fi

echo "[gate] F95: C vs Python — execute_ast set|::global|value step"
F95EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_set_step.azl"
F95_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F95EX" boot.entry 2>&1)"
f95_c_rc=$?
if [ "$f95_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_set_step exited $f95_c_rc: $F95_C_OUT"
  exit 386
fi
if ! printf '%s\n' "$F95_C_OUT" | awk 'NR==1{if($0!="F95_TREE")exit 1} NR==2{if($0!="F95_SAYLINE")exit 1} NR==3{if($0!="F95_CELL")exit 1} NR==4{if($0!="EX95_POST")exit 1} NR==5{if($0!="Said: F95_SAYLINE")exit 1} NR==6{if($0!="EC95_INNER")exit 1} NR==7{if($0!="Said: F95_SAYLINE")exit 1} NR==8{if($0!="P0_SEM_F95_OK")exit 1} END{if(NR!=8)exit 1}'; then
  echo "ERROR: expected F95 execute_ast set stdout (8 lines), got: $F95_C_OUT"
  exit 386
fi
F95_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F95EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f95_py_rc=$?
if [ "$f95_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_set_step exited $f95_py_rc: $F95_PY_OUT"
  exit 387
fi
if [ "$F95_C_OUT" != "$F95_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_set_step" >&2
  echo "C:  $F95_C_OUT" >&2
  echo "Py: $F95_PY_OUT" >&2
  exit 388
fi

echo "[gate] F96: C vs Python — execute_ast emit|…|with|key|value step"
F96EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_emit_with_step.azl"
F96_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F96EX" boot.entry 2>&1)"
f96_c_rc=$?
if [ "$f96_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_emit_with_step exited $f96_c_rc: $F96_C_OUT"
  exit 389
fi
if ! printf '%s\n' "$F96_C_OUT" | awk 'NR==1{if($0!="F96_TREE")exit 1} NR==2{if($0!="F96_A")exit 1} NR==3{if($0!="F96_PAYLOAD")exit 1} NR==4{if($0!="EX96_POST")exit 1} NR==5{if($0!="Emitted: f96_inner")exit 1} NR==6{if($0!="EC96_INNER")exit 1} NR==7{if($0!="Emitted: f96_inner")exit 1} NR==8{if($0!="P0_SEM_F96_OK")exit 1} END{if(NR!=8)exit 1}'; then
  echo "ERROR: expected F96 execute_ast emit|with stdout (8 lines), got: $F96_C_OUT"
  exit 389
fi
F96_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F96EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f96_py_rc=$?
if [ "$f96_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_emit_with_step exited $f96_py_rc: $F96_PY_OUT"
  exit 390
fi
if [ "$F96_C_OUT" != "$F96_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_emit_with_step" >&2
  echo "C:  $F96_C_OUT" >&2
  echo "Py: $F96_PY_OUT" >&2
  exit 391
fi

echo "[gate] F97: C vs Python — execute_ast emit|…|with multi key|value pairs"
F97EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_emit_multi_with_step.azl"
F97_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F97EX" boot.entry 2>&1)"
f97_c_rc=$?
if [ "$f97_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_emit_multi_with_step exited $f97_c_rc: $F97_C_OUT"
  exit 392
fi
if ! printf '%s\n' "$F97_C_OUT" | awk 'NR==1{if($0!="F97_TREE")exit 1} NR==2{if($0!="F97_A")exit 1} NR==3{if($0!="F97_ONE")exit 1} NR==4{if($0!="F97_TWO")exit 1} NR==5{if($0!="EX97_POST")exit 1} NR==6{if($0!="Emitted: f97_inner")exit 1} NR==7{if($0!="EC97_INNER")exit 1} NR==8{if($0!="Emitted: f97_inner")exit 1} NR==9{if($0!="P0_SEM_F97_OK")exit 1} END{if(NR!=9)exit 1}'; then
  echo "ERROR: expected F97 execute_ast emit|with multi stdout (9 lines), got: $F97_C_OUT"
  exit 392
fi
F97_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F97EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f97_py_rc=$?
if [ "$f97_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_emit_multi_with_step exited $f97_py_rc: $F97_PY_OUT"
  exit 393
fi
if [ "$F97_C_OUT" != "$F97_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_emit_multi_with_step" >&2
  echo "C:  $F97_C_OUT" >&2
  echo "Py: $F97_PY_OUT" >&2
  exit 394
fi

echo "[gate] F98: C vs Python — execute_ast import|/link| preloop (shallow stub + link side-effect)"
F98EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_import_link_preloop.azl"
F98_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F98EX" boot.entry 2>&1)"
f98_c_rc=$?
if [ "$f98_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_import_link_preloop exited $f98_c_rc: $F98_C_OUT"
  exit 395
fi
if ! printf '%s\n' "$F98_C_OUT" | awk 'NR==1{if($0!="F98_TREE")exit 1} NR==2{if($0!="P98_LINK_SID")exit 1} NR==3{if($0!="F98_PRE")exit 1} NR==4{if($0!="F98_POST")exit 1} NR==5{if($0!="p98_mod_name")exit 1} NR==6{if($0!="EX98_POST")exit 1} NR==7{if($0!="Said: F98_POST")exit 1} NR==8{if($0!="EC98_INNER")exit 1} NR==9{if($0!="Said: F98_POST")exit 1} NR==10{if($0!="P0_SEM_F98_OK")exit 1} END{if(NR!=10)exit 1}'; then
  echo "ERROR: expected F98 execute_ast import/link preloop stdout (10 lines), got: $F98_C_OUT"
  exit 395
fi
F98_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F98EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f98_py_rc=$?
if [ "$f98_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_import_link_preloop exited $f98_py_rc: $F98_PY_OUT"
  exit 396
fi
if [ "$F98_C_OUT" != "$F98_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_import_link_preloop" >&2
  echo "C:  $F98_C_OUT" >&2
  echo "Py: $F98_PY_OUT" >&2
  exit 397
fi

echo "[gate] F99: C vs Python — execute_ast component| + listen|…|say|… stub dispatch"
F99EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_component_listen_step.azl"
F99_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F99EX" boot.entry 2>&1)"
f99_c_rc=$?
if [ "$f99_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_component_listen_step exited $f99_c_rc: $F99_C_OUT"
  exit 398
fi
if ! printf '%s\n' "$F99_C_OUT" | awk 'NR==1{if($0!="F99_TREE")exit 1} NR==2{if($0!="P99_COMP_INIT")exit 1} NR==3{if($0!="P99_LISTEN_CB")exit 1} NR==4{if($0!="F99_TAIL")exit 1} NR==5{if($0!="EX99_POST")exit 1} NR==6{if($0!="Said: F99_TAIL")exit 1} NR==7{if($0!="EC99_INNER")exit 1} NR==8{if($0!="Said: F99_TAIL")exit 1} NR==9{if($0!="P0_SEM_F99_OK")exit 1} END{if(NR!=9)exit 1}'; then
  echo "ERROR: expected F99 execute_ast component/listen stdout (9 lines), got: $F99_C_OUT"
  exit 398
fi
F99_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F99EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f99_py_rc=$?
if [ "$f99_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_component_listen_step exited $f99_py_rc: $F99_PY_OUT"
  exit 399
fi
if [ "$F99_C_OUT" != "$F99_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_component_listen_step" >&2
  echo "C:  $F99_C_OUT" >&2
  echo "Py: $F99_PY_OUT" >&2
  exit 400
fi

echo "[gate] F100: C vs Python — execute_ast listen|…|emit|… stub (nested event)"
F100EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_listen_emit_stub.azl"
F100_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F100EX" boot.entry 2>&1)"
f100_c_rc=$?
if [ "$f100_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_listen_emit_stub exited $f100_c_rc: $F100_C_OUT"
  exit 401
fi
if ! printf '%s\n' "$F100_C_OUT" | awk 'NR==1{if($0!="F100_TREE")exit 1} NR==2{if($0!="P100_COMP_INIT")exit 1} NR==3{if($0!="F100_INNER_CB")exit 1} NR==4{if($0!="F100_TAIL")exit 1} NR==5{if($0!="EX100_POST")exit 1} NR==6{if($0!="Said: F100_TAIL")exit 1} NR==7{if($0!="EC100_INNER")exit 1} NR==8{if($0!="Said: F100_TAIL")exit 1} NR==9{if($0!="P0_SEM_F100_OK")exit 1} END{if(NR!=9)exit 1}'; then
  echo "ERROR: expected F100 execute_ast listen|emit stub stdout (9 lines), got: $F100_C_OUT"
  exit 401
fi
F100_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F100EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f100_py_rc=$?
if [ "$f100_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_listen_emit_stub exited $f100_py_rc: $F100_PY_OUT"
  exit 402
fi
if [ "$F100_C_OUT" != "$F100_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_listen_emit_stub" >&2
  echo "C:  $F100_C_OUT" >&2
  echo "Py: $F100_PY_OUT" >&2
  exit 403
fi

echo "[gate] F101: C vs Python — execute_ast listen|…|set|::global|value stub"
F101EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_listen_set_stub.azl"
F101_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F101EX" boot.entry 2>&1)"
f101_c_rc=$?
if [ "$f101_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_listen_set_stub exited $f101_c_rc: $F101_C_OUT"
  exit 404
fi
if ! printf '%s\n' "$F101_C_OUT" | awk 'NR==1{if($0!="F101_TREE")exit 1} NR==2{if($0!="F101_SAYLINE")exit 1} NR==3{if($0!="F101_CELL")exit 1} NR==4{if($0!="EX101_POST")exit 1} NR==5{if($0!="Said: F101_SAYLINE")exit 1} NR==6{if($0!="EC101_INNER")exit 1} NR==7{if($0!="Said: F101_SAYLINE")exit 1} NR==8{if($0!="P0_SEM_F101_OK")exit 1} END{if(NR!=8)exit 1}'; then
  echo "ERROR: expected F101 execute_ast listen|set stub stdout (8 lines), got: $F101_C_OUT"
  exit 404
fi
F101_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F101EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f101_py_rc=$?
if [ "$f101_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_listen_set_stub exited $f101_py_rc: $F101_PY_OUT"
  exit 405
fi
if [ "$F101_C_OUT" != "$F101_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_listen_set_stub" >&2
  echo "C:  $F101_C_OUT" >&2
  echo "Py: $F101_PY_OUT" >&2
  exit 406
fi

echo "[gate] F102: C vs Python — execute_ast listen|…|emit|…|with|key|value stub"
F102EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_listen_emit_with_stub.azl"
F102_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F102EX" boot.entry 2>&1)"
f102_c_rc=$?
if [ "$f102_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_listen_emit_with_stub exited $f102_c_rc: $F102_C_OUT"
  exit 407
fi
if ! printf '%s\n' "$F102_C_OUT" | awk 'NR==1{if($0!="F102_TREE")exit 1} NR==2{if($0!="F102_STUB_PAYLOAD")exit 1} NR==3{if($0!="F102_TAIL")exit 1} NR==4{if($0!="EX102_POST")exit 1} NR==5{if($0!="Said: F102_TAIL")exit 1} NR==6{if($0!="EC102_INNER")exit 1} NR==7{if($0!="Said: F102_TAIL")exit 1} NR==8{if($0!="P0_SEM_F102_OK")exit 1} END{if(NR!=8)exit 1}'; then
  echo "ERROR: expected F102 execute_ast listen|emit|with stub stdout (8 lines), got: $F102_C_OUT"
  exit 407
fi
F102_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F102EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f102_py_rc=$?
if [ "$f102_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_listen_emit_with_stub exited $f102_py_rc: $F102_PY_OUT"
  exit 408
fi
if [ "$F102_C_OUT" != "$F102_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_listen_emit_with_stub" >&2
  echo "C:  $F102_C_OUT" >&2
  echo "Py: $F102_PY_OUT" >&2
  exit 409
fi

echo "[gate] F103: C vs Python — execute_ast listen|…|emit|…|with multi key|value stub"
F103EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_listen_emit_multi_with_stub.azl"
F103_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F103EX" boot.entry 2>&1)"
f103_c_rc=$?
if [ "$f103_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_listen_emit_multi_with_stub exited $f103_c_rc: $F103_C_OUT"
  exit 410
fi
if ! printf '%s\n' "$F103_C_OUT" | awk 'NR==1{if($0!="F103_TREE")exit 1} NR==2{if($0!="F103_ONE")exit 1} NR==3{if($0!="F103_TWO")exit 1} NR==4{if($0!="F103_TAIL")exit 1} NR==5{if($0!="EX103_POST")exit 1} NR==6{if($0!="Said: F103_TAIL")exit 1} NR==7{if($0!="EC103_INNER")exit 1} NR==8{if($0!="Said: F103_TAIL")exit 1} NR==9{if($0!="P0_SEM_F103_OK")exit 1} END{if(NR!=9)exit 1}'; then
  echo "ERROR: expected F103 execute_ast listen|emit|with multi stub stdout (9 lines), got: $F103_C_OUT"
  exit 410
fi
F103_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F103EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f103_py_rc=$?
if [ "$f103_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_listen_emit_multi_with_stub exited $f103_py_rc: $F103_PY_OUT"
  exit 411
fi
if [ "$F103_C_OUT" != "$F103_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_listen_emit_multi_with_stub" >&2
  echo "C:  $F103_C_OUT" >&2
  echo "Py: $F103_PY_OUT" >&2
  exit 412
fi

echo "[gate] F104: C vs Python — execute_ast memory|set|… / memory|say|… stub row"
F104EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_memory_set_step.azl"
F104_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F104EX" boot.entry 2>&1)"
f104_c_rc=$?
if [ "$f104_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_memory_set_step exited $f104_c_rc: $F104_C_OUT"
  exit 413
fi
if ! printf '%s\n' "$F104_C_OUT" | awk 'NR==1{if($0!="F104_TREE")exit 1} NR==2{if($0!="F104_SAYLINE")exit 1} NR==3{if($0!="F104_CELL")exit 1} NR==4{if($0!="EX104_POST")exit 1} NR==5{if($0!="Said: F104_SAYLINE")exit 1} NR==6{if($0!="EC104_INNER")exit 1} NR==7{if($0!="Said: F104_SAYLINE")exit 1} NR==8{if($0!="P0_SEM_F104_OK")exit 1} END{if(NR!=8)exit 1}'; then
  echo "ERROR: expected F104 execute_ast memory| stub stdout (8 lines), got: $F104_C_OUT"
  exit 413
fi
F104_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F104EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f104_py_rc=$?
if [ "$f104_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_memory_set_step exited $f104_py_rc: $F104_PY_OUT"
  exit 414
fi
if [ "$F104_C_OUT" != "$F104_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_memory_set_step" >&2
  echo "C:  $F104_C_OUT" >&2
  echo "Py: $F104_PY_OUT" >&2
  exit 415
fi

echo "[gate] F105: C vs Python — execute_ast memory|emit|… (bare emit + drain)"
F105EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_memory_emit_step.azl"
F105_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F105EX" boot.entry 2>&1)"
f105_c_rc=$?
if [ "$f105_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_memory_emit_step exited $f105_c_rc: $F105_C_OUT"
  exit 416
fi
if ! printf '%s\n' "$F105_C_OUT" | awk 'NR==1{if($0!="F105_TREE")exit 1} NR==2{if($0!="F105_A")exit 1} NR==3{if($0!="F105_INNER_BODY")exit 1} NR==4{if($0!="EX105_POST")exit 1} NR==5{if($0!="Emitted: f105_inner")exit 1} NR==6{if($0!="EC105_INNER")exit 1} NR==7{if($0!="Emitted: f105_inner")exit 1} NR==8{if($0!="P0_SEM_F105_OK")exit 1} END{if(NR!=8)exit 1}'; then
  echo "ERROR: expected F105 execute_ast memory|emit stdout (8 lines), got: $F105_C_OUT"
  exit 416
fi
F105_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F105EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f105_py_rc=$?
if [ "$f105_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_memory_emit_step exited $f105_py_rc: $F105_PY_OUT"
  exit 417
fi
if [ "$F105_C_OUT" != "$F105_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_memory_emit_step" >&2
  echo "C:  $F105_C_OUT" >&2
  echo "Py: $F105_PY_OUT" >&2
  exit 418
fi

echo "[gate] F106: C vs Python — execute_ast memory|emit|…|with|key|value"
F106EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_memory_emit_with_step.azl"
F106_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F106EX" boot.entry 2>&1)"
f106_c_rc=$?
if [ "$f106_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_memory_emit_with_step exited $f106_c_rc: $F106_C_OUT"
  exit 419
fi
if ! printf '%s\n' "$F106_C_OUT" | awk 'NR==1{if($0!="F106_TREE")exit 1} NR==2{if($0!="F106_A")exit 1} NR==3{if($0!="F106_PAYLOAD")exit 1} NR==4{if($0!="EX106_POST")exit 1} NR==5{if($0!="Emitted: f106_inner")exit 1} NR==6{if($0!="EC106_INNER")exit 1} NR==7{if($0!="Emitted: f106_inner")exit 1} NR==8{if($0!="P0_SEM_F106_OK")exit 1} END{if(NR!=8)exit 1}'; then
  echo "ERROR: expected F106 execute_ast memory|emit|with stdout (8 lines), got: $F106_C_OUT"
  exit 419
fi
F106_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F106EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f106_py_rc=$?
if [ "$f106_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_memory_emit_with_step exited $f106_py_rc: $F106_PY_OUT"
  exit 420
fi
if [ "$F106_C_OUT" != "$F106_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_memory_emit_with_step" >&2
  echo "C:  $F106_C_OUT" >&2
  echo "Py: $F106_PY_OUT" >&2
  exit 421
fi

echo "[gate] F107: C vs Python — execute_ast memory|emit|…|with multi key|value"
F107EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_memory_emit_multi_with_step.azl"
F107_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F107EX" boot.entry 2>&1)"
f107_c_rc=$?
if [ "$f107_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_memory_emit_multi_with_step exited $f107_c_rc: $F107_C_OUT"
  exit 422
fi
if ! printf '%s\n' "$F107_C_OUT" | awk 'NR==1{if($0!="F107_TREE")exit 1} NR==2{if($0!="F107_A")exit 1} NR==3{if($0!="F107_ONE")exit 1} NR==4{if($0!="F107_TWO")exit 1} NR==5{if($0!="EX107_POST")exit 1} NR==6{if($0!="Emitted: f107_inner")exit 1} NR==7{if($0!="EC107_INNER")exit 1} NR==8{if($0!="Emitted: f107_inner")exit 1} NR==9{if($0!="P0_SEM_F107_OK")exit 1} END{if(NR!=9)exit 1}'; then
  echo "ERROR: expected F107 execute_ast memory|emit|with multi stdout (9 lines), got: $F107_C_OUT"
  exit 422
fi
F107_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F107EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f107_py_rc=$?
if [ "$f107_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_memory_emit_multi_with_step exited $f107_py_rc: $F107_PY_OUT"
  exit 423
fi
if [ "$F107_C_OUT" != "$F107_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_memory_emit_multi_with_step" >&2
  echo "C:  $F107_C_OUT" >&2
  echo "Py: $F107_PY_OUT" >&2
  exit 424
fi

echo "[gate] F108: C vs Python — execute_ast multi memory|say rows + say order"
F108EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_memory_multi_row_order.azl"
F108_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F108EX" boot.entry 2>&1)"
f108_c_rc=$?
if [ "$f108_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_memory_multi_row_order exited $f108_c_rc: $F108_C_OUT"
  exit 425
fi
if ! printf '%s\n' "$F108_C_OUT" | awk 'NR==1{if($0!="F108_TREE")exit 1} NR==2{if($0!="F108_M1")exit 1} NR==3{if($0!="F108_M2")exit 1} NR==4{if($0!="F108_TAIL")exit 1} NR==5{if($0!="EX108_POST")exit 1} NR==6{if($0!="Said: F108_TAIL")exit 1} NR==7{if($0!="EC108_INNER")exit 1} NR==8{if($0!="Said: F108_TAIL")exit 1} NR==9{if($0!="P0_SEM_F108_OK")exit 1} END{if(NR!=9)exit 1}'; then
  echo "ERROR: expected F108 execute_ast multi memory| row order stdout (9 lines), got: $F108_C_OUT"
  exit 425
fi
F108_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F108EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f108_py_rc=$?
if [ "$f108_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_memory_multi_row_order exited $f108_py_rc: $F108_PY_OUT"
  exit 426
fi
if [ "$F108_C_OUT" != "$F108_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_memory_multi_row_order" >&2
  echo "C:  $F108_C_OUT" >&2
  echo "Py: $F108_PY_OUT" >&2
  exit 427
fi

echo "[gate] F109: C vs Python — execute_ast memory|set then memory|emit then memory|say order"
F109EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_memory_mixed_order.azl"
F109_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F109EX" boot.entry 2>&1)"
f109_c_rc=$?
if [ "$f109_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_memory_mixed_order exited $f109_c_rc: $F109_C_OUT"
  exit 428
fi
if ! printf '%s\n' "$F109_C_OUT" | awk 'NR==1{if($0!="F109_TREE")exit 1} NR==2{if($0!="F109_INNER_BODY")exit 1} NR==3{if($0!="F109_AFTER")exit 1} NR==4{if($0!="F109_CELL")exit 1} NR==5{if($0!="EX109_POST")exit 1} NR==6{if($0!="Said: F109_AFTER")exit 1} NR==7{if($0!="EC109_INNER")exit 1} NR==8{if($0!="Said: F109_AFTER")exit 1} NR==9{if($0!="P0_SEM_F109_OK")exit 1} END{if(NR!=9)exit 1}'; then
  echo "ERROR: expected F109 execute_ast mixed memory| stdout (9 lines), got: $F109_C_OUT"
  exit 428
fi
F109_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F109EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f109_py_rc=$?
if [ "$f109_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_memory_mixed_order exited $f109_py_rc: $F109_PY_OUT"
  exit 429
fi
if [ "$F109_C_OUT" != "$F109_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_memory_mixed_order" >&2
  echo "C:  $F109_C_OUT" >&2
  echo "Py: $F109_PY_OUT" >&2
  exit 430
fi

echo "[gate] F110: C vs Python — execute_ast memory|set then memory|emit|with then memory|say order"
F110EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_memory_mixed_emit_with_order.azl"
F110_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F110EX" boot.entry 2>&1)"
f110_c_rc=$?
if [ "$f110_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_memory_mixed_emit_with_order exited $f110_c_rc: $F110_C_OUT"
  exit 431
fi
if ! printf '%s\n' "$F110_C_OUT" | awk 'NR==1{if($0!="F110_TREE")exit 1} NR==2{if($0!="F110_PAYLOAD")exit 1} NR==3{if($0!="F110_AFTER")exit 1} NR==4{if($0!="F110_CELL")exit 1} NR==5{if($0!="EX110_POST")exit 1} NR==6{if($0!="Said: F110_AFTER")exit 1} NR==7{if($0!="EC110_INNER")exit 1} NR==8{if($0!="Said: F110_AFTER")exit 1} NR==9{if($0!="P0_SEM_F110_OK")exit 1} END{if(NR!=9)exit 1}'; then
  echo "ERROR: expected F110 execute_ast mixed memory|emit|with stdout (9 lines), got: $F110_C_OUT"
  exit 431
fi
F110_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F110EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f110_py_rc=$?
if [ "$f110_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_memory_mixed_emit_with_order exited $f110_py_rc: $F110_PY_OUT"
  exit 432
fi
if [ "$F110_C_OUT" != "$F110_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_memory_mixed_emit_with_order" >&2
  echo "C:  $F110_C_OUT" >&2
  echo "Py: $F110_PY_OUT" >&2
  exit 433
fi

echo "[gate] F111: C vs Python — execute_ast memory|set then memory|emit|with multi then memory|say order"
F111EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_memory_mixed_emit_multi_with_order.azl"
F111_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F111EX" boot.entry 2>&1)"
f111_c_rc=$?
if [ "$f111_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_memory_mixed_emit_multi_with_order exited $f111_c_rc: $F111_C_OUT"
  exit 434
fi
if ! printf '%s\n' "$F111_C_OUT" | awk 'NR==1{if($0!="F111_TREE")exit 1} NR==2{if($0!="F111_ONE")exit 1} NR==3{if($0!="F111_TWO")exit 1} NR==4{if($0!="F111_AFTER")exit 1} NR==5{if($0!="F111_CELL")exit 1} NR==6{if($0!="EX111_POST")exit 1} NR==7{if($0!="Said: F111_AFTER")exit 1} NR==8{if($0!="EC111_INNER")exit 1} NR==9{if($0!="Said: F111_AFTER")exit 1} NR==10{if($0!="P0_SEM_F111_OK")exit 1} END{if(NR!=10)exit 1}'; then
  echo "ERROR: expected F111 execute_ast mixed memory|emit|with multi stdout (10 lines), got: $F111_C_OUT"
  exit 434
fi
F111_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F111EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f111_py_rc=$?
if [ "$f111_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_memory_mixed_emit_multi_with_order exited $f111_py_rc: $F111_PY_OUT"
  exit 435
fi
if [ "$F111_C_OUT" != "$F111_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_memory_mixed_emit_multi_with_order" >&2
  echo "C:  $F111_C_OUT" >&2
  echo "Py: $F111_PY_OUT" >&2
  exit 436
fi

echo "[gate] F112: C vs Python — execute_ast preloop import|+link| then memory|say|"
F112EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_then_memory_say.azl"
F112_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F112EX" boot.entry 2>&1)"
f112_c_rc=$?
if [ "$f112_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_then_memory_say exited $f112_c_rc: $F112_C_OUT"
  exit 437
fi
if ! printf '%s\n' "$F112_C_OUT" | awk 'NR==1{if($0!="F112_TREE")exit 1} NR==2{if($0!="P112_LINK_SID")exit 1} NR==3{if($0!="F112_MEM")exit 1} NR==4{if($0!="f112_mod_tag")exit 1} NR==5{if($0!="EX112_POST")exit 1} NR==6{if($0!="Said: F112_MEM")exit 1} NR==7{if($0!="EC112_INNER")exit 1} NR==8{if($0!="Said: F112_MEM")exit 1} NR==9{if($0!="P0_SEM_F112_OK")exit 1} END{if(NR!=9)exit 1}'; then
  echo "ERROR: expected F112 execute_ast preloop then memory|say stdout (9 lines), got: $F112_C_OUT"
  exit 437
fi
F112_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F112EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f112_py_rc=$?
if [ "$f112_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_then_memory_say exited $f112_py_rc: $F112_PY_OUT"
  exit 438
fi
if [ "$F112_C_OUT" != "$F112_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_then_memory_say" >&2
  echo "C:  $F112_C_OUT" >&2
  echo "Py: $F112_PY_OUT" >&2
  exit 439
fi

echo "[gate] F113: C vs Python — execute_ast preloop then say| then memory|say|"
F113EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_say_then_memory_say.azl"
F113_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F113EX" boot.entry 2>&1)"
f113_c_rc=$?
if [ "$f113_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_say_then_memory_say exited $f113_c_rc: $F113_C_OUT"
  exit 440
fi
if ! printf '%s\n' "$F113_C_OUT" | awk 'NR==1{if($0!="F113_TREE")exit 1} NR==2{if($0!="P113_LINK_SID")exit 1} NR==3{if($0!="F113_TOP")exit 1} NR==4{if($0!="F113_MEM")exit 1} NR==5{if($0!="f113_mod_tag")exit 1} NR==6{if($0!="EX113_POST")exit 1} NR==7{if($0!="Said: F113_MEM")exit 1} NR==8{if($0!="EC113_INNER")exit 1} NR==9{if($0!="Said: F113_MEM")exit 1} NR==10{if($0!="P0_SEM_F113_OK")exit 1} END{if(NR!=10)exit 1}'; then
  echo "ERROR: expected F113 execute_ast preloop say then memory|say stdout (10 lines), got: $F113_C_OUT"
  exit 440
fi
F113_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F113EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f113_py_rc=$?
if [ "$f113_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_say_then_memory_say exited $f113_py_rc: $F113_PY_OUT"
  exit 441
fi
if [ "$F113_C_OUT" != "$F113_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_say_then_memory_say" >&2
  echo "C:  $F113_C_OUT" >&2
  echo "Py: $F113_PY_OUT" >&2
  exit 442
fi

echo "[gate] F114: C vs Python — execute_ast preloop then emit|…|with|… then memory|say|"
F114EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_emit_then_memory_say.azl"
F114_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F114EX" boot.entry 2>&1)"
f114_c_rc=$?
if [ "$f114_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_emit_then_memory_say exited $f114_c_rc: $F114_C_OUT"
  exit 443
fi
if ! printf '%s\n' "$F114_C_OUT" | awk 'NR==1{if($0!="F114_TREE")exit 1} NR==2{if($0!="P114_LINK_SID")exit 1} NR==3{if($0!="F114_PL_LINE")exit 1} NR==4{if($0!="F114_MEM")exit 1} NR==5{if($0!="f114_mod_tag")exit 1} NR==6{if($0!="EX114_POST")exit 1} NR==7{if($0!="Said: F114_MEM")exit 1} NR==8{if($0!="EC114_INNER")exit 1} NR==9{if($0!="Said: F114_MEM")exit 1} NR==10{if($0!="P0_SEM_F114_OK")exit 1} END{if(NR!=10)exit 1}'; then
  echo "ERROR: expected F114 execute_ast preloop emit|with then memory|say stdout (10 lines), got: $F114_C_OUT"
  exit 443
fi
F114_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F114EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f114_py_rc=$?
if [ "$f114_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_emit_then_memory_say exited $f114_py_rc: $F114_PY_OUT"
  exit 444
fi
if [ "$F114_C_OUT" != "$F114_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_emit_then_memory_say" >&2
  echo "C:  $F114_C_OUT" >&2
  echo "Py: $F114_PY_OUT" >&2
  exit 445
fi

echo "[gate] F115: C vs Python — execute_ast memory|listen|… then memory|emit|… + memory|say|"
F115EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_memory_listen_emit_say.azl"
F115_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F115EX" boot.entry 2>&1)"
f115_c_rc=$?
if [ "$f115_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_memory_listen_emit_say exited $f115_c_rc: $F115_C_OUT"
  exit 446
fi
if ! printf '%s\n' "$F115_C_OUT" | awk 'NR==1{if($0!="F115_TREE")exit 1} NR==2{if($0!="F115_TOP")exit 1} NR==3{if($0!="F115_LISTEN_CB")exit 1} NR==4{if($0!="F115_MEM")exit 1} NR==5{if($0!="f115_mod_tag")exit 1} NR==6{if($0!="EX115_POST")exit 1} NR==7{if($0!="Said: F115_MEM")exit 1} NR==8{if($0!="EC115_INNER")exit 1} NR==9{if($0!="Said: F115_MEM")exit 1} NR==10{if($0!="P0_SEM_F115_OK")exit 1} END{if(NR!=10)exit 1}'; then
  echo "ERROR: expected F115 execute_ast memory listen + emit + say stdout (10 lines), got: $F115_C_OUT"
  exit 446
fi
F115_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F115EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f115_py_rc=$?
if [ "$f115_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_memory_listen_emit_say exited $f115_py_rc: $F115_PY_OUT"
  exit 447
fi
if [ "$F115_C_OUT" != "$F115_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_memory_listen_emit_say" >&2
  echo "C:  $F115_C_OUT" >&2
  echo "Py: $F115_PY_OUT" >&2
  exit 448
fi

echo "[gate] F116: C vs Python — execute_ast memory|listen|emit|with|… then memory|emit|… + memory|say|"
F116EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_memory_listen_emit_with_say.azl"
F116_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F116EX" boot.entry 2>&1)"
f116_c_rc=$?
if [ "$f116_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_memory_listen_emit_with_say exited $f116_c_rc: $F116_C_OUT"
  exit 449
fi
if ! printf '%s\n' "$F116_C_OUT" | awk 'NR==1{if($0!="F116_TREE")exit 1} NR==2{if($0!="F116_TOP")exit 1} NR==3{if($0!="F116_PAYLOAD")exit 1} NR==4{if($0!="F116_MEM")exit 1} NR==5{if($0!="f116_mod_tag")exit 1} NR==6{if($0!="EX116_POST")exit 1} NR==7{if($0!="Said: F116_MEM")exit 1} NR==8{if($0!="EC116_INNER")exit 1} NR==9{if($0!="Said: F116_MEM")exit 1} NR==10{if($0!="P0_SEM_F116_OK")exit 1} END{if(NR!=10)exit 1}'; then
  echo "ERROR: expected F116 execute_ast memory listen emit|with + emit + say stdout (10 lines), got: $F116_C_OUT"
  exit 449
fi
F116_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F116EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f116_py_rc=$?
if [ "$f116_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_memory_listen_emit_with_say exited $f116_py_rc: $F116_PY_OUT"
  exit 450
fi
if [ "$F116_C_OUT" != "$F116_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_memory_listen_emit_with_say" >&2
  echo "C:  $F116_C_OUT" >&2
  echo "Py: $F116_PY_OUT" >&2
  exit 451
fi

echo "[gate] F117: C vs Python — execute_ast memory|listen|emit|with multi-pair then memory|emit|… + memory|say|"
F117EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_memory_listen_emit_multi_with_say.azl"
F117_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F117EX" boot.entry 2>&1)"
f117_c_rc=$?
if [ "$f117_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_memory_listen_emit_multi_with_say exited $f117_c_rc: $F117_C_OUT"
  exit 452
fi
if ! printf '%s\n' "$F117_C_OUT" | awk 'NR==1{if($0!="F117_TREE")exit 1} NR==2{if($0!="F117_TOP")exit 1} NR==3{if($0!="F117_ONE")exit 1} NR==4{if($0!="F117_TWO")exit 1} NR==5{if($0!="F117_MEM")exit 1} NR==6{if($0!="f117_mod_tag")exit 1} NR==7{if($0!="EX117_POST")exit 1} NR==8{if($0!="Said: F117_MEM")exit 1} NR==9{if($0!="EC117_INNER")exit 1} NR==10{if($0!="Said: F117_MEM")exit 1} NR==11{if($0!="P0_SEM_F117_OK")exit 1} END{if(NR!=11)exit 1}'; then
  echo "ERROR: expected F117 execute_ast memory listen emit|with multi + emit + say stdout (11 lines), got: $F117_C_OUT"
  exit 452
fi
F117_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F117EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f117_py_rc=$?
if [ "$f117_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_memory_listen_emit_multi_with_say exited $f117_py_rc: $F117_PY_OUT"
  exit 453
fi
if [ "$F117_C_OUT" != "$F117_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_memory_listen_emit_multi_with_say" >&2
  echo "C:  $F117_C_OUT" >&2
  echo "Py: $F117_PY_OUT" >&2
  exit 454
fi

echo "[gate] F118: C vs Python — preloop import|+link| then memory|listen|emit|with multi + memory|emit|… + memory|say|"
F118EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_memory_listen_emit_multi_with_say.azl"
F118_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F118EX" boot.entry 2>&1)"
f118_c_rc=$?
if [ "$f118_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_memory_listen_emit_multi_with_say exited $f118_c_rc: $F118_C_OUT"
  exit 455
fi
if ! printf '%s\n' "$F118_C_OUT" | awk 'NR==1{if($0!="F118_TREE")exit 1} NR==2{if($0!="P118_LINK_SID")exit 1} NR==3{if($0!="F118_TOP")exit 1} NR==4{if($0!="F118_ONE")exit 1} NR==5{if($0!="F118_TWO")exit 1} NR==6{if($0!="F118_MEM")exit 1} NR==7{if($0!="f118_mod_tag")exit 1} NR==8{if($0!="EX118_POST")exit 1} NR==9{if($0!="Said: F118_MEM")exit 1} NR==10{if($0!="EC118_INNER")exit 1} NR==11{if($0!="Said: F118_MEM")exit 1} NR==12{if($0!="P0_SEM_F118_OK")exit 1} END{if(NR!=12)exit 1}'; then
  echo "ERROR: expected F118 preloop + memory listen emit|with multi + emit + say stdout (12 lines), got: $F118_C_OUT"
  exit 455
fi
F118_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F118EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f118_py_rc=$?
if [ "$f118_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_memory_listen_emit_multi_with_say exited $f118_py_rc: $F118_PY_OUT"
  exit 456
fi
if [ "$F118_C_OUT" != "$F118_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_memory_listen_emit_multi_with_say" >&2
  echo "C:  $F118_C_OUT" >&2
  echo "Py: $F118_PY_OUT" >&2
  exit 457
fi

echo "[gate] F119: C vs Python — stacked memory|listen|say stubs then memory|emit|… ×2 + memory|say|"
F119EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_memory_listen_stack_say.azl"
F119_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F119EX" boot.entry 2>&1)"
f119_c_rc=$?
if [ "$f119_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_memory_listen_stack_say exited $f119_c_rc: $F119_C_OUT"
  exit 458
fi
if ! printf '%s\n' "$F119_C_OUT" | awk 'NR==1{if($0!="F119_TREE")exit 1} NR==2{if($0!="F119_TOP")exit 1} NR==3{if($0!="F119_STUB_ONE")exit 1} NR==4{if($0!="F119_STUB_TWO")exit 1} NR==5{if($0!="F119_MEM")exit 1} NR==6{if($0!="f119_mod_tag")exit 1} NR==7{if($0!="EX119_POST")exit 1} NR==8{if($0!="Said: F119_MEM")exit 1} NR==9{if($0!="EC119_INNER")exit 1} NR==10{if($0!="Said: F119_MEM")exit 1} NR==11{if($0!="P0_SEM_F119_OK")exit 1} END{if(NR!=11)exit 1}'; then
  echo "ERROR: expected F119 stacked memory|listen|say + dual memory|emit stdout (11 lines), got: $F119_C_OUT"
  exit 458
fi
F119_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F119EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f119_py_rc=$?
if [ "$f119_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_memory_listen_stack_say exited $f119_py_rc: $F119_PY_OUT"
  exit 459
fi
if [ "$F119_C_OUT" != "$F119_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_memory_listen_stack_say" >&2
  echo "C:  $F119_C_OUT" >&2
  echo "Py: $F119_PY_OUT" >&2
  exit 460
fi

echo "[gate] F120: C vs Python — preloop import|+link| then stacked memory|listen|say + memory|emit|… ×2 + memory|say|"
F120EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_memory_listen_stack_say.azl"
F120_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F120EX" boot.entry 2>&1)"
f120_c_rc=$?
if [ "$f120_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_memory_listen_stack_say exited $f120_c_rc: $F120_C_OUT"
  exit 461
fi
if ! printf '%s\n' "$F120_C_OUT" | awk 'NR==1{if($0!="F120_TREE")exit 1} NR==2{if($0!="P120_LINK_SID")exit 1} NR==3{if($0!="F120_TOP")exit 1} NR==4{if($0!="F120_STUB_ONE")exit 1} NR==5{if($0!="F120_STUB_TWO")exit 1} NR==6{if($0!="F120_MEM")exit 1} NR==7{if($0!="f120_mod_tag")exit 1} NR==8{if($0!="EX120_POST")exit 1} NR==9{if($0!="Said: F120_MEM")exit 1} NR==10{if($0!="EC120_INNER")exit 1} NR==11{if($0!="Said: F120_MEM")exit 1} NR==12{if($0!="P0_SEM_F120_OK")exit 1} END{if(NR!=12)exit 1}'; then
  echo "ERROR: expected F120 preloop + stacked memory|listen|say + dual memory|emit stdout (12 lines), got: $F120_C_OUT"
  exit 461
fi
F120_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F120EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f120_py_rc=$?
if [ "$f120_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_memory_listen_stack_say exited $f120_py_rc: $F120_PY_OUT"
  exit 462
fi
if [ "$F120_C_OUT" != "$F120_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_memory_listen_stack_say" >&2
  echo "C:  $F120_C_OUT" >&2
  echo "Py: $F120_PY_OUT" >&2
  exit 463
fi

echo "[gate] F121: C vs Python — preloop import|+link| then say| then stacked memory|listen|say + memory|emit|… ×2 + memory|say|"
F121EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_say_then_memory_listen_stack_say.azl"
F121_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F121EX" boot.entry 2>&1)"
f121_c_rc=$?
if [ "$f121_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_say_then_memory_listen_stack_say exited $f121_c_rc: $F121_C_OUT"
  exit 464
fi
if ! printf '%s\n' "$F121_C_OUT" | awk 'NR==1{if($0!="F121_TREE")exit 1} NR==2{if($0!="P121_LINK_SID")exit 1} NR==3{if($0!="F121_PRE_SLICE")exit 1} NR==4{if($0!="F121_STUB_ONE")exit 1} NR==5{if($0!="F121_STUB_TWO")exit 1} NR==6{if($0!="F121_MEM")exit 1} NR==7{if($0!="f121_mod_tag")exit 1} NR==8{if($0!="EX121_POST")exit 1} NR==9{if($0!="Said: F121_MEM")exit 1} NR==10{if($0!="EC121_INNER")exit 1} NR==11{if($0!="Said: F121_MEM")exit 1} NR==12{if($0!="P0_SEM_F121_OK")exit 1} END{if(NR!=12)exit 1}'; then
  echo "ERROR: expected F121 preloop + say| + stacked memory|listen stdout (12 lines), got: $F121_C_OUT"
  exit 464
fi
F121_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F121EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f121_py_rc=$?
if [ "$f121_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_say_then_memory_listen_stack_say exited $f121_py_rc: $F121_PY_OUT"
  exit 465
fi
if [ "$F121_C_OUT" != "$F121_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_say_then_memory_listen_stack_say" >&2
  echo "C:  $F121_C_OUT" >&2
  echo "Py: $F121_PY_OUT" >&2
  exit 466
fi

echo "[gate] F122: C vs Python — preloop import|+link| then emit|…|with|… then stacked memory|listen|say + memory|emit|… ×2 + memory|say|"
F122EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_emit_then_memory_listen_stack_say.azl"
F122_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F122EX" boot.entry 2>&1)"
f122_c_rc=$?
if [ "$f122_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_emit_then_memory_listen_stack_say exited $f122_c_rc: $F122_C_OUT"
  exit 467
fi
if ! printf '%s\n' "$F122_C_OUT" | awk 'NR==1{if($0!="F122_TREE")exit 1} NR==2{if($0!="P122_LINK_SID")exit 1} NR==3{if($0!="F122_FROM_EMIT")exit 1} NR==4{if($0!="F122_STUB_ONE")exit 1} NR==5{if($0!="F122_STUB_TWO")exit 1} NR==6{if($0!="F122_MEM")exit 1} NR==7{if($0!="f122_mod_tag")exit 1} NR==8{if($0!="EX122_POST")exit 1} NR==9{if($0!="Said: F122_MEM")exit 1} NR==10{if($0!="EC122_INNER")exit 1} NR==11{if($0!="Said: F122_MEM")exit 1} NR==12{if($0!="P0_SEM_F122_OK")exit 1} END{if(NR!=12)exit 1}'; then
  echo "ERROR: expected F122 preloop + emit|with + stacked memory|listen stdout (12 lines), got: $F122_C_OUT"
  exit 467
fi
F122_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F122EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f122_py_rc=$?
if [ "$f122_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_emit_then_memory_listen_stack_say exited $f122_py_rc: $F122_PY_OUT"
  exit 468
fi
if [ "$F122_C_OUT" != "$F122_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_emit_then_memory_listen_stack_say" >&2
  echo "C:  $F122_C_OUT" >&2
  echo "Py: $F122_PY_OUT" >&2
  exit 469
fi

echo "[gate] F123: C vs Python — preloop import|+link| then component| then 2× memory|set| then stacked memory|listen|say + memory|emit|… ×2 + memory|say|"
F123EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_set_listen_stack.azl"
F123_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F123EX" boot.entry 2>&1)"
f123_c_rc=$?
if [ "$f123_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_set_listen_stack exited $f123_c_rc: $F123_C_OUT"
  exit 470
fi
if ! printf '%s\n' "$F123_C_OUT" | awk 'NR==1{if($0!="F123_TREE")exit 1} NR==2{if($0!="P123_LINK_SID")exit 1} NR==3{if($0!="P123_COMP")exit 1} NR==4{if($0!="F123_ONE")exit 1} NR==5{if($0!="F123_TWO")exit 1} NR==6{if($0!="F123_MEM")exit 1} NR==7{if($0!="f123_mod_tag")exit 1} NR==8{if($0!="EX123_POST")exit 1} NR==9{if($0!="Said: F123_MEM")exit 1} NR==10{if($0!="EC123_INNER")exit 1} NR==11{if($0!="Said: F123_MEM")exit 1} NR==12{if($0!="P0_SEM_F123_OK")exit 1} END{if(NR!=12)exit 1}'; then
  echo "ERROR: expected F123 preloop + component| + 2× memory|set| + stacked memory|listen stdout (12 lines), got: $F123_C_OUT"
  exit 470
fi
F123_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F123EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f123_py_rc=$?
if [ "$f123_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_set_listen_stack exited $f123_py_rc: $F123_PY_OUT"
  exit 471
fi
if [ "$F123_C_OUT" != "$F123_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_set_listen_stack" >&2
  echo "C:  $F123_C_OUT" >&2
  echo "Py: $F123_PY_OUT" >&2
  exit 472
fi

echo "[gate] F124: C vs Python — preloop import|+link| then component| + memory|say| + component| + memory|say| (two linked inits interleaved)"
F124EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_two_component_memory_say.azl"
F124_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F124EX" boot.entry 2>&1)"
f124_c_rc=$?
if [ "$f124_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_two_component_memory_say exited $f124_c_rc: $F124_C_OUT"
  exit 473
fi
if ! printf '%s\n' "$F124_C_OUT" | awk 'NR==1{if($0!="F124_TREE")exit 1} NR==2{if($0!="P124_LINK_SID")exit 1} NR==3{if($0!="P124_ALPHA")exit 1} NR==4{if($0!="F124_MID")exit 1} NR==5{if($0!="P124_BETA")exit 1} NR==6{if($0!="F124_END")exit 1} NR==7{if($0!="f124_mod_tag")exit 1} NR==8{if($0!="EX124_POST")exit 1} NR==9{if($0!="Said: F124_END")exit 1} NR==10{if($0!="EC124_INNER")exit 1} NR==11{if($0!="Said: F124_END")exit 1} NR==12{if($0!="P0_SEM_F124_OK")exit 1} END{if(NR!=12)exit 1}'; then
  echo "ERROR: expected F124 preloop + two component| + memory|say| interleave stdout (12 lines), got: $F124_C_OUT"
  exit 473
fi
F124_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F124EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f124_py_rc=$?
if [ "$f124_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_two_component_memory_say exited $f124_py_rc: $F124_PY_OUT"
  exit 474
fi
if [ "$F124_C_OUT" != "$F124_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_two_component_memory_say" >&2
  echo "C:  $F124_C_OUT" >&2
  echo "Py: $F124_PY_OUT" >&2
  exit 475
fi

echo "[gate] F125: C vs Python — preloop import|+link| then component|×3 + memory|say| between (triple linked inits interleaved)"
F125EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_three_component_memory_say.azl"
F125_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F125EX" boot.entry 2>&1)"
f125_c_rc=$?
if [ "$f125_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_three_component_memory_say exited $f125_c_rc: $F125_C_OUT"
  exit 476
fi
if ! printf '%s\n' "$F125_C_OUT" | awk 'NR==1{if($0!="F125_TREE")exit 1} NR==2{if($0!="P125_LINK_SID")exit 1} NR==3{if($0!="P125_A")exit 1} NR==4{if($0!="F125_M1")exit 1} NR==5{if($0!="P125_B")exit 1} NR==6{if($0!="F125_M2")exit 1} NR==7{if($0!="P125_C")exit 1} NR==8{if($0!="F125_M3")exit 1} NR==9{if($0!="f125_mod_tag")exit 1} NR==10{if($0!="EX125_POST")exit 1} NR==11{if($0!="Said: F125_M3")exit 1} NR==12{if($0!="EC125_INNER")exit 1} NR==13{if($0!="Said: F125_M3")exit 1} NR==14{if($0!="P0_SEM_F125_OK")exit 1} END{if(NR!=14)exit 1}'; then
  echo "ERROR: expected F125 preloop + three component| + memory|say| interleave stdout (14 lines), got: $F125_C_OUT"
  exit 476
fi
F125_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F125EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f125_py_rc=$?
if [ "$f125_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_three_component_memory_say exited $f125_py_rc: $F125_PY_OUT"
  exit 477
fi
if [ "$F125_C_OUT" != "$F125_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_three_component_memory_say" >&2
  echo "C:  $F125_C_OUT" >&2
  echo "Py: $F125_PY_OUT" >&2
  exit 478
fi

echo "[gate] F126: C vs Python — preloop import|+link| then component| + memory|emit|…|with|… + component| + memory|say|"
F126EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_emit_component_say.azl"
F126_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F126EX" boot.entry 2>&1)"
f126_c_rc=$?
if [ "$f126_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_emit_component_say exited $f126_c_rc: $F126_C_OUT"
  exit 479
fi
if ! printf '%s\n' "$F126_C_OUT" | awk 'NR==1{if($0!="F126_TREE")exit 1} NR==2{if($0!="P126_LINK_SID")exit 1} NR==3{if($0!="P126_A")exit 1} NR==4{if($0!="F126_FROM_MEM_EMIT")exit 1} NR==5{if($0!="P126_B")exit 1} NR==6{if($0!="F126_MEM")exit 1} NR==7{if($0!="f126_mod_tag")exit 1} NR==8{if($0!="EX126_POST")exit 1} NR==9{if($0!="Said: F126_MEM")exit 1} NR==10{if($0!="EC126_INNER")exit 1} NR==11{if($0!="Said: F126_MEM")exit 1} NR==12{if($0!="P0_SEM_F126_OK")exit 1} END{if(NR!=12)exit 1}'; then
  echo "ERROR: expected F126 preloop + component| + memory|emit|with + component| + memory|say stdout (12 lines), got: $F126_C_OUT"
  exit 479
fi
F126_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F126EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f126_py_rc=$?
if [ "$f126_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_emit_component_say exited $f126_py_rc: $F126_PY_OUT"
  exit 480
fi
if [ "$F126_C_OUT" != "$F126_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_emit_component_say" >&2
  echo "C:  $F126_C_OUT" >&2
  echo "Py: $F126_PY_OUT" >&2
  exit 481
fi

echo "[gate] F127: C vs Python — preloop import|+link| then component| + two memory|emit|…|with|… + component| + memory|say|"
F127EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_dual_emit_component_say.azl"
F127_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F127EX" boot.entry 2>&1)"
f127_c_rc=$?
if [ "$f127_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_dual_emit_component_say exited $f127_c_rc: $F127_C_OUT"
  exit 482
fi
if ! printf '%s\n' "$F127_C_OUT" | awk 'NR==1{if($0!="F127_TREE")exit 1} NR==2{if($0!="P127_LINK_SID")exit 1} NR==3{if($0!="P127_A")exit 1} NR==4{if($0!="F127_K1")exit 1} NR==5{if($0!="F127_K2")exit 1} NR==6{if($0!="P127_B")exit 1} NR==7{if($0!="F127_MEM")exit 1} NR==8{if($0!="f127_mod_tag")exit 1} NR==9{if($0!="EX127_POST")exit 1} NR==10{if($0!="Said: F127_MEM")exit 1} NR==11{if($0!="EC127_INNER")exit 1} NR==12{if($0!="Said: F127_MEM")exit 1} NR==13{if($0!="P0_SEM_F127_OK")exit 1} END{if(NR!=13)exit 1}'; then
  echo "ERROR: expected F127 preloop + component| + dual memory|emit|with + component| + memory|say stdout (13 lines), got: $F127_C_OUT"
  exit 482
fi
F127_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F127EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f127_py_rc=$?
if [ "$f127_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_dual_emit_component_say exited $f127_py_rc: $F127_PY_OUT"
  exit 483
fi
if [ "$F127_C_OUT" != "$F127_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_dual_emit_component_say" >&2
  echo "C:  $F127_C_OUT" >&2
  echo "Py: $F127_PY_OUT" >&2
  exit 484
fi

echo "[gate] F128: C vs Python — preloop import|+link| then component| + three memory|emit|…|with|… + component| + memory|say|"
F128EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_triple_emit_component_say.azl"
F128_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F128EX" boot.entry 2>&1)"
f128_c_rc=$?
if [ "$f128_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_triple_emit_component_say exited $f128_c_rc: $F128_C_OUT"
  exit 485
fi
if ! printf '%s\n' "$F128_C_OUT" | awk 'NR==1{if($0!="F128_TREE")exit 1} NR==2{if($0!="P128_LINK_SID")exit 1} NR==3{if($0!="P128_A")exit 1} NR==4{if($0!="F128_K1")exit 1} NR==5{if($0!="F128_K2")exit 1} NR==6{if($0!="F128_K3")exit 1} NR==7{if($0!="P128_B")exit 1} NR==8{if($0!="F128_MEM")exit 1} NR==9{if($0!="f128_mod_tag")exit 1} NR==10{if($0!="EX128_POST")exit 1} NR==11{if($0!="Said: F128_MEM")exit 1} NR==12{if($0!="EC128_INNER")exit 1} NR==13{if($0!="Said: F128_MEM")exit 1} NR==14{if($0!="P0_SEM_F128_OK")exit 1} END{if(NR!=14)exit 1}'; then
  echo "ERROR: expected F128 preloop + component| + triple memory|emit|with + component| + memory|say stdout (14 lines), got: $F128_C_OUT"
  exit 485
fi
F128_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F128EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f128_py_rc=$?
if [ "$f128_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_triple_emit_component_say exited $f128_py_rc: $F128_PY_OUT"
  exit 486
fi
if [ "$F128_C_OUT" != "$F128_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_triple_emit_component_say" >&2
  echo "C:  $F128_C_OUT" >&2
  echo "Py: $F128_PY_OUT" >&2
  exit 487
fi

echo "[gate] F129: C vs Python — preloop import|+link| then component| + bare memory|emit|… + component| + memory|say|"
F129EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_bare_emit_component_say.azl"
F129_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F129EX" boot.entry 2>&1)"
f129_c_rc=$?
if [ "$f129_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_bare_emit_component_say exited $f129_c_rc: $F129_C_OUT"
  exit 488
fi
if ! printf '%s\n' "$F129_C_OUT" | awk 'NR==1{if($0!="F129_TREE")exit 1} NR==2{if($0!="P129_LINK_SID")exit 1} NR==3{if($0!="P129_A")exit 1} NR==4{if($0!="F129_BARE_DRAIN")exit 1} NR==5{if($0!="P129_B")exit 1} NR==6{if($0!="F129_MEM")exit 1} NR==7{if($0!="f129_mod_tag")exit 1} NR==8{if($0!="EX129_POST")exit 1} NR==9{if($0!="Said: F129_MEM")exit 1} NR==10{if($0!="EC129_INNER")exit 1} NR==11{if($0!="Said: F129_MEM")exit 1} NR==12{if($0!="P0_SEM_F129_OK")exit 1} END{if(NR!=12)exit 1}'; then
  echo "ERROR: expected F129 preloop + component| + bare memory|emit + component| + memory|say stdout (12 lines), got: $F129_C_OUT"
  exit 488
fi
F129_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F129EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f129_py_rc=$?
if [ "$f129_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_bare_emit_component_say exited $f129_py_rc: $F129_PY_OUT"
  exit 489
fi
if [ "$F129_C_OUT" != "$F129_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_bare_emit_component_say" >&2
  echo "C:  $F129_C_OUT" >&2
  echo "Py: $F129_PY_OUT" >&2
  exit 490
fi

echo "[gate] F130: C vs Python — preloop import|+link| then component| + two bare memory|emit|… + component| + memory|say|"
F130EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_dual_bare_emit_component_say.azl"
F130_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F130EX" boot.entry 2>&1)"
f130_c_rc=$?
if [ "$f130_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_dual_bare_emit_component_say exited $f130_c_rc: $F130_C_OUT"
  exit 491
fi
if ! printf '%s\n' "$F130_C_OUT" | awk 'NR==1{if($0!="F130_TREE")exit 1} NR==2{if($0!="P130_LINK_SID")exit 1} NR==3{if($0!="P130_A")exit 1} NR==4{if($0!="F130_BARE_1")exit 1} NR==5{if($0!="F130_BARE_2")exit 1} NR==6{if($0!="P130_B")exit 1} NR==7{if($0!="F130_MEM")exit 1} NR==8{if($0!="f130_mod_tag")exit 1} NR==9{if($0!="EX130_POST")exit 1} NR==10{if($0!="Said: F130_MEM")exit 1} NR==11{if($0!="EC130_INNER")exit 1} NR==12{if($0!="Said: F130_MEM")exit 1} NR==13{if($0!="P0_SEM_F130_OK")exit 1} END{if(NR!=13)exit 1}'; then
  echo "ERROR: expected F130 preloop + component| + dual bare memory|emit + component| + memory|say stdout (13 lines), got: $F130_C_OUT"
  exit 491
fi
F130_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F130EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f130_py_rc=$?
if [ "$f130_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_dual_bare_emit_component_say exited $f130_py_rc: $F130_PY_OUT"
  exit 492
fi
if [ "$F130_C_OUT" != "$F130_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_dual_bare_emit_component_say" >&2
  echo "C:  $F130_C_OUT" >&2
  echo "Py: $F130_PY_OUT" >&2
  exit 493
fi

echo "[gate] F131: C vs Python — preloop import|+link| then component| + three bare memory|emit|… + component| + memory|say|"
F131EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_triple_bare_emit_component_say.azl"
F131_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F131EX" boot.entry 2>&1)"
f131_c_rc=$?
if [ "$f131_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_triple_bare_emit_component_say exited $f131_c_rc: $F131_C_OUT"
  exit 494
fi
if ! printf '%s\n' "$F131_C_OUT" | awk 'NR==1{if($0!="F131_TREE")exit 1} NR==2{if($0!="P131_LINK_SID")exit 1} NR==3{if($0!="P131_A")exit 1} NR==4{if($0!="F131_BARE_1")exit 1} NR==5{if($0!="F131_BARE_2")exit 1} NR==6{if($0!="F131_BARE_3")exit 1} NR==7{if($0!="P131_B")exit 1} NR==8{if($0!="F131_MEM")exit 1} NR==9{if($0!="f131_mod_tag")exit 1} NR==10{if($0!="EX131_POST")exit 1} NR==11{if($0!="Said: F131_MEM")exit 1} NR==12{if($0!="EC131_INNER")exit 1} NR==13{if($0!="Said: F131_MEM")exit 1} NR==14{if($0!="P0_SEM_F131_OK")exit 1} END{if(NR!=14)exit 1}'; then
  echo "ERROR: expected F131 preloop + component| + triple bare memory|emit + component| + memory|say stdout (14 lines), got: $F131_C_OUT"
  exit 494
fi
F131_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F131EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f131_py_rc=$?
if [ "$f131_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_triple_bare_emit_component_say exited $f131_py_rc: $F131_PY_OUT"
  exit 495
fi
if [ "$F131_C_OUT" != "$F131_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_triple_bare_emit_component_say" >&2
  echo "C:  $F131_C_OUT" >&2
  echo "Py: $F131_PY_OUT" >&2
  exit 496
fi

echo "[gate] F132: C vs Python — preloop import|+link| then component| + bare memory|emit|… + memory|emit|…|with|… + component| + memory|say|"
F132EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_mixed_bare_with_emit_component_say.azl"
F132_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F132EX" boot.entry 2>&1)"
f132_c_rc=$?
if [ "$f132_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_mixed_bare_with_emit_component_say exited $f132_c_rc: $F132_C_OUT"
  exit 497
fi
if ! printf '%s\n' "$F132_C_OUT" | awk 'NR==1{if($0!="F132_TREE")exit 1} NR==2{if($0!="P132_LINK_SID")exit 1} NR==3{if($0!="P132_A")exit 1} NR==4{if($0!="F132_BARE_1")exit 1} NR==5{if($0!="F132_PAYLOAD")exit 1} NR==6{if($0!="P132_B")exit 1} NR==7{if($0!="F132_MEM")exit 1} NR==8{if($0!="f132_mod_tag")exit 1} NR==9{if($0!="EX132_POST")exit 1} NR==10{if($0!="Said: F132_MEM")exit 1} NR==11{if($0!="EC132_INNER")exit 1} NR==12{if($0!="Said: F132_MEM")exit 1} NR==13{if($0!="P0_SEM_F132_OK")exit 1} END{if(NR!=13)exit 1}'; then
  echo "ERROR: expected F132 preloop + component| + mixed bare/with memory|emit + component| + memory|say stdout (13 lines), got: $F132_C_OUT"
  exit 497
fi
F132_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F132EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f132_py_rc=$?
if [ "$f132_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_mixed_bare_with_emit_component_say exited $f132_py_rc: $F132_PY_OUT"
  exit 498
fi
if [ "$F132_C_OUT" != "$F132_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_mixed_bare_with_emit_component_say" >&2
  echo "C:  $F132_C_OUT" >&2
  echo "Py: $F132_PY_OUT" >&2
  exit 499
fi

echo "[gate] F133: C vs Python — preloop import|+link| then component| + memory|emit|…|with|… + bare memory|emit|… + component| + memory|say|"
F133EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_mixed_with_bare_emit_component_say.azl"
F133_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F133EX" boot.entry 2>&1)"
f133_c_rc=$?
if [ "$f133_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_mixed_with_bare_emit_component_say exited $f133_c_rc: $F133_C_OUT"
  exit 500
fi
if ! printf '%s\n' "$F133_C_OUT" | awk 'NR==1{if($0!="F133_TREE")exit 1} NR==2{if($0!="P133_LINK_SID")exit 1} NR==3{if($0!="P133_A")exit 1} NR==4{if($0!="F133_PAYLOAD")exit 1} NR==5{if($0!="F133_BARE_2")exit 1} NR==6{if($0!="P133_B")exit 1} NR==7{if($0!="F133_MEM")exit 1} NR==8{if($0!="f133_mod_tag")exit 1} NR==9{if($0!="EX133_POST")exit 1} NR==10{if($0!="Said: F133_MEM")exit 1} NR==11{if($0!="EC133_INNER")exit 1} NR==12{if($0!="Said: F133_MEM")exit 1} NR==13{if($0!="P0_SEM_F133_OK")exit 1} END{if(NR!=13)exit 1}'; then
  echo "ERROR: expected F133 preloop + component| + mixed with/bare memory|emit + component| + memory|say stdout (13 lines), got: $F133_C_OUT"
  exit 500
fi
F133_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F133EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f133_py_rc=$?
if [ "$f133_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_mixed_with_bare_emit_component_say exited $f133_py_rc: $F133_PY_OUT"
  exit 501
fi
if [ "$F133_C_OUT" != "$F133_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_mixed_with_bare_emit_component_say" >&2
  echo "C:  $F133_C_OUT" >&2
  echo "Py: $F133_PY_OUT" >&2
  exit 502
fi

echo "[gate] F134: C vs Python — preloop import|+link| then component| + memory|emit|…|with|… + bare + memory|emit|…|with|… + component| + memory|say|"
F134EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_triple_mixed_emit_component_say.azl"
F134_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F134EX" boot.entry 2>&1)"
f134_c_rc=$?
if [ "$f134_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_triple_mixed_emit_component_say exited $f134_c_rc: $F134_C_OUT"
  exit 503
fi
if ! printf '%s\n' "$F134_C_OUT" | awk 'NR==1{if($0!="F134_TREE")exit 1} NR==2{if($0!="P134_LINK_SID")exit 1} NR==3{if($0!="P134_A")exit 1} NR==4{if($0!="F134_PAY_A")exit 1} NR==5{if($0!="F134_BARE_MID")exit 1} NR==6{if($0!="F134_PAY_B")exit 1} NR==7{if($0!="P134_B")exit 1} NR==8{if($0!="F134_MEM")exit 1} NR==9{if($0!="f134_mod_tag")exit 1} NR==10{if($0!="EX134_POST")exit 1} NR==11{if($0!="Said: F134_MEM")exit 1} NR==12{if($0!="EC134_INNER")exit 1} NR==13{if($0!="Said: F134_MEM")exit 1} NR==14{if($0!="P0_SEM_F134_OK")exit 1} END{if(NR!=14)exit 1}'; then
  echo "ERROR: expected F134 preloop + component| + triple mixed memory|emit + component| + memory|say stdout (14 lines), got: $F134_C_OUT"
  exit 503
fi
F134_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F134EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f134_py_rc=$?
if [ "$f134_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_triple_mixed_emit_component_say exited $f134_py_rc: $F134_PY_OUT"
  exit 504
fi
if [ "$F134_C_OUT" != "$F134_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_triple_mixed_emit_component_say" >&2
  echo "C:  $F134_C_OUT" >&2
  echo "Py: $F134_PY_OUT" >&2
  exit 505
fi

echo "[gate] F135: C vs Python — preloop import|+link| then component| + bare + memory|emit|…|with|… + bare + component| + memory|say|"
F135EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_triple_mixed_bare_with_bare_emit_component_say.azl"
F135_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F135EX" boot.entry 2>&1)"
f135_c_rc=$?
if [ "$f135_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_triple_mixed_bare_with_bare_emit_component_say exited $f135_c_rc: $F135_C_OUT"
  exit 506
fi
if ! printf '%s\n' "$F135_C_OUT" | awk 'NR==1{if($0!="F135_TREE")exit 1} NR==2{if($0!="P135_LINK_SID")exit 1} NR==3{if($0!="P135_A")exit 1} NR==4{if($0!="F135_BARE_1")exit 1} NR==5{if($0!="F135_PAY_MID")exit 1} NR==6{if($0!="F135_BARE_3")exit 1} NR==7{if($0!="P135_B")exit 1} NR==8{if($0!="F135_MEM")exit 1} NR==9{if($0!="f135_mod_tag")exit 1} NR==10{if($0!="EX135_POST")exit 1} NR==11{if($0!="Said: F135_MEM")exit 1} NR==12{if($0!="EC135_INNER")exit 1} NR==13{if($0!="Said: F135_MEM")exit 1} NR==14{if($0!="P0_SEM_F135_OK")exit 1} END{if(NR!=14)exit 1}'; then
  echo "ERROR: expected F135 preloop + component| + bare + with + bare memory|emit + component| + memory|say stdout (14 lines), got: $F135_C_OUT"
  exit 506
fi
F135_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F135EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f135_py_rc=$?
if [ "$f135_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_triple_mixed_bare_with_bare_emit_component_say exited $f135_py_rc: $F135_PY_OUT"
  exit 507
fi
if [ "$F135_C_OUT" != "$F135_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_triple_mixed_bare_with_bare_emit_component_say" >&2
  echo "C:  $F135_C_OUT" >&2
  echo "Py: $F135_PY_OUT" >&2
  exit 508
fi

echo "[gate] F136: C vs Python — preloop import|+link| then component| + bare + memory|emit|…|with|… ×2 + bare + component| + memory|say|"
F136EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_quad_mixed_bare_with_with_bare_emit_component_say.azl"
F136_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F136EX" boot.entry 2>&1)"
f136_c_rc=$?
if [ "$f136_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_quad_mixed_bare_with_with_bare_emit_component_say exited $f136_c_rc: $F136_C_OUT"
  exit 509
fi
if ! printf '%s\n' "$F136_C_OUT" | awk 'NR==1{if($0!="F136_TREE")exit 1} NR==2{if($0!="P136_LINK_SID")exit 1} NR==3{if($0!="P136_A")exit 1} NR==4{if($0!="F136_BARE_1")exit 1} NR==5{if($0!="F136_PAY_A")exit 1} NR==6{if($0!="F136_PAY_B")exit 1} NR==7{if($0!="F136_BARE_4")exit 1} NR==8{if($0!="P136_B")exit 1} NR==9{if($0!="F136_MEM")exit 1} NR==10{if($0!="f136_mod_tag")exit 1} NR==11{if($0!="EX136_POST")exit 1} NR==12{if($0!="Said: F136_MEM")exit 1} NR==13{if($0!="EC136_INNER")exit 1} NR==14{if($0!="Said: F136_MEM")exit 1} NR==15{if($0!="P0_SEM_F136_OK")exit 1} END{if(NR!=15)exit 1}'; then
  echo "ERROR: expected F136 preloop + component| + quad mixed memory|emit + component| + memory|say stdout (15 lines), got: $F136_C_OUT"
  exit 509
fi
F136_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F136EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f136_py_rc=$?
if [ "$f136_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_quad_mixed_bare_with_with_bare_emit_component_say exited $f136_py_rc: $F136_PY_OUT"
  exit 510
fi
if [ "$F136_C_OUT" != "$F136_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_quad_mixed_bare_with_with_bare_emit_component_say" >&2
  echo "C:  $F136_C_OUT" >&2
  echo "Py: $F136_PY_OUT" >&2
  exit 511
fi

echo "[gate] F137: C vs Python — preloop import|+link| then component| + memory|emit|…|with|… + bare ×2 + memory|emit|…|with|… + component| + memory|say|"
F137EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_quad_mixed_with_bare_bare_with_emit_component_say.azl"
F137_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F137EX" boot.entry 2>&1)"
f137_c_rc=$?
if [ "$f137_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_quad_mixed_with_bare_bare_with_emit_component_say exited $f137_c_rc: $F137_C_OUT"
  exit 512
fi
if ! printf '%s\n' "$F137_C_OUT" | awk 'NR==1{if($0!="F137_TREE")exit 1} NR==2{if($0!="P137_LINK_SID")exit 1} NR==3{if($0!="P137_A")exit 1} NR==4{if($0!="F137_PAY_A")exit 1} NR==5{if($0!="F137_BARE_2")exit 1} NR==6{if($0!="F137_BARE_3")exit 1} NR==7{if($0!="F137_PAY_B")exit 1} NR==8{if($0!="P137_B")exit 1} NR==9{if($0!="F137_MEM")exit 1} NR==10{if($0!="f137_mod_tag")exit 1} NR==11{if($0!="EX137_POST")exit 1} NR==12{if($0!="Said: F137_MEM")exit 1} NR==13{if($0!="EC137_INNER")exit 1} NR==14{if($0!="Said: F137_MEM")exit 1} NR==15{if($0!="P0_SEM_F137_OK")exit 1} END{if(NR!=15)exit 1}'; then
  echo "ERROR: expected F137 preloop + component| + quad mixed with/bare/bare/with memory|emit + component| + memory|say stdout (15 lines), got: $F137_C_OUT"
  exit 512
fi
F137_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F137EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f137_py_rc=$?
if [ "$f137_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_quad_mixed_with_bare_bare_with_emit_component_say exited $f137_py_rc: $F137_PY_OUT"
  exit 513
fi
if [ "$F137_C_OUT" != "$F137_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_quad_mixed_with_bare_bare_with_emit_component_say" >&2
  echo "C:  $F137_C_OUT" >&2
  echo "Py: $F137_PY_OUT" >&2
  exit 514
fi

echo "[gate] F138: C vs Python — preloop import|+link| then component| + bare + memory|emit|…|with|… + bare + memory|emit|…|with|… + component| + memory|say|"
F138EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_quad_mixed_bare_with_bare_with_emit_component_say.azl"
F138_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F138EX" boot.entry 2>&1)"
f138_c_rc=$?
if [ "$f138_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_quad_mixed_bare_with_bare_with_emit_component_say exited $f138_c_rc: $F138_C_OUT"
  exit 515
fi
if ! printf '%s\n' "$F138_C_OUT" | awk 'NR==1{if($0!="F138_TREE")exit 1} NR==2{if($0!="P138_LINK_SID")exit 1} NR==3{if($0!="P138_A")exit 1} NR==4{if($0!="F138_BARE_1")exit 1} NR==5{if($0!="F138_PAY_A")exit 1} NR==6{if($0!="F138_BARE_3")exit 1} NR==7{if($0!="F138_PAY_B")exit 1} NR==8{if($0!="P138_B")exit 1} NR==9{if($0!="F138_MEM")exit 1} NR==10{if($0!="f138_mod_tag")exit 1} NR==11{if($0!="EX138_POST")exit 1} NR==12{if($0!="Said: F138_MEM")exit 1} NR==13{if($0!="EC138_INNER")exit 1} NR==14{if($0!="Said: F138_MEM")exit 1} NR==15{if($0!="P0_SEM_F138_OK")exit 1} END{if(NR!=15)exit 1}'; then
  echo "ERROR: expected F138 preloop + component| + quad mixed bare/with/bare/with memory|emit + component| + memory|say stdout (15 lines), got: $F138_C_OUT"
  exit 515
fi
F138_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F138EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f138_py_rc=$?
if [ "$f138_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_quad_mixed_bare_with_bare_with_emit_component_say exited $f138_py_rc: $F138_PY_OUT"
  exit 516
fi
if [ "$F138_C_OUT" != "$F138_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_quad_mixed_bare_with_bare_with_emit_component_say" >&2
  echo "C:  $F138_C_OUT" >&2
  echo "Py: $F138_PY_OUT" >&2
  exit 517
fi

echo "[gate] F139: C vs Python — preloop import|+link| then component| + memory|emit|…|with|… ×2 + bare ×2 + component| + memory|say|"
F139EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_quad_mixed_with_with_bare_bare_emit_component_say.azl"
F139_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F139EX" boot.entry 2>&1)"
f139_c_rc=$?
if [ "$f139_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_quad_mixed_with_with_bare_bare_emit_component_say exited $f139_c_rc: $F139_C_OUT"
  exit 518
fi
if ! printf '%s\n' "$F139_C_OUT" | awk 'NR==1{if($0!="F139_TREE")exit 1} NR==2{if($0!="P139_LINK_SID")exit 1} NR==3{if($0!="P139_A")exit 1} NR==4{if($0!="F139_PAY_A")exit 1} NR==5{if($0!="F139_PAY_B")exit 1} NR==6{if($0!="F139_BARE_3")exit 1} NR==7{if($0!="F139_BARE_4")exit 1} NR==8{if($0!="P139_B")exit 1} NR==9{if($0!="F139_MEM")exit 1} NR==10{if($0!="f139_mod_tag")exit 1} NR==11{if($0!="EX139_POST")exit 1} NR==12{if($0!="Said: F139_MEM")exit 1} NR==13{if($0!="EC139_INNER")exit 1} NR==14{if($0!="Said: F139_MEM")exit 1} NR==15{if($0!="P0_SEM_F139_OK")exit 1} END{if(NR!=15)exit 1}'; then
  echo "ERROR: expected F139 preloop + component| + quad mixed with/with/bare/bare memory|emit + component| + memory|say stdout (15 lines), got: $F139_C_OUT"
  exit 518
fi
F139_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F139EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f139_py_rc=$?
if [ "$f139_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_quad_mixed_with_with_bare_bare_emit_component_say exited $f139_py_rc: $F139_PY_OUT"
  exit 519
fi
if [ "$F139_C_OUT" != "$F139_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_quad_mixed_with_with_bare_bare_emit_component_say" >&2
  echo "C:  $F139_C_OUT" >&2
  echo "Py: $F139_PY_OUT" >&2
  exit 520
fi

echo "[gate] F140: C vs Python — preloop import|+link| then component| + bare + memory|emit|…|with|… + bare + memory|emit|…|with|… + bare + component| + memory|say|"
F140EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_penta_mixed_bare_with_bare_with_bare_emit_component_say.azl"
F140_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F140EX" boot.entry 2>&1)"
f140_c_rc=$?
if [ "$f140_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_penta_mixed_bare_with_bare_with_bare_emit_component_say exited $f140_c_rc: $F140_C_OUT"
  exit 521
fi
if ! printf '%s\n' "$F140_C_OUT" | awk 'NR==1{if($0!="F140_TREE")exit 1} NR==2{if($0!="P140_LINK_SID")exit 1} NR==3{if($0!="P140_A")exit 1} NR==4{if($0!="F140_BARE_1")exit 1} NR==5{if($0!="F140_PAY_A")exit 1} NR==6{if($0!="F140_BARE_3")exit 1} NR==7{if($0!="F140_PAY_B")exit 1} NR==8{if($0!="F140_BARE_5")exit 1} NR==9{if($0!="P140_B")exit 1} NR==10{if($0!="F140_MEM")exit 1} NR==11{if($0!="f140_mod_tag")exit 1} NR==12{if($0!="EX140_POST")exit 1} NR==13{if($0!="Said: F140_MEM")exit 1} NR==14{if($0!="EC140_INNER")exit 1} NR==15{if($0!="Said: F140_MEM")exit 1} NR==16{if($0!="P0_SEM_F140_OK")exit 1} END{if(NR!=16)exit 1}'; then
  echo "ERROR: expected F140 preloop + component| + penta bare/with/bare/with/bare memory|emit + component| + memory|say stdout (16 lines), got: $F140_C_OUT"
  exit 521
fi
F140_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F140EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f140_py_rc=$?
if [ "$f140_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_penta_mixed_bare_with_bare_with_bare_emit_component_say exited $f140_py_rc: $F140_PY_OUT"
  exit 522
fi
if [ "$F140_C_OUT" != "$F140_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_penta_mixed_bare_with_bare_with_bare_emit_component_say" >&2
  echo "C:  $F140_C_OUT" >&2
  echo "Py: $F140_PY_OUT" >&2
  exit 523
fi

echo "[gate] F141: C vs Python — preloop import|+link| then component| + memory|emit|…|with|… + bare + memory|emit|…|with|… + bare + memory|emit|…|with|… + component| + memory|say|"
F141EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_penta_mixed_with_bare_with_bare_with_emit_component_say.azl"
F141_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F141EX" boot.entry 2>&1)"
f141_c_rc=$?
if [ "$f141_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_penta_mixed_with_bare_with_bare_with_emit_component_say exited $f141_c_rc: $F141_C_OUT"
  exit 524
fi
if ! printf '%s\n' "$F141_C_OUT" | awk 'NR==1{if($0!="F141_TREE")exit 1} NR==2{if($0!="P141_LINK_SID")exit 1} NR==3{if($0!="P141_A")exit 1} NR==4{if($0!="F141_PAY_A")exit 1} NR==5{if($0!="F141_BARE_2")exit 1} NR==6{if($0!="F141_PAY_B")exit 1} NR==7{if($0!="F141_BARE_4")exit 1} NR==8{if($0!="F141_PAY_C")exit 1} NR==9{if($0!="P141_B")exit 1} NR==10{if($0!="F141_MEM")exit 1} NR==11{if($0!="i141")exit 1} NR==12{if($0!="EX141_POST")exit 1} NR==13{if($0!="Said: F141_MEM")exit 1} NR==14{if($0!="EC141_INNER")exit 1} NR==15{if($0!="Said: F141_MEM")exit 1} NR==16{if($0!="P0_SEM_F141_OK")exit 1} END{if(NR!=16)exit 1}'; then
  echo "ERROR: expected F141 preloop + component| + penta with/bare/with/bare/with memory|emit + component| + memory|say stdout (16 lines), got: $F141_C_OUT"
  exit 524
fi
F141_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F141EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f141_py_rc=$?
if [ "$f141_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_penta_mixed_with_bare_with_bare_with_emit_component_say exited $f141_py_rc: $F141_PY_OUT"
  exit 525
fi
if [ "$F141_C_OUT" != "$F141_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_penta_mixed_with_bare_with_bare_with_emit_component_say" >&2
  echo "C:  $F141_C_OUT" >&2
  echo "Py: $F141_PY_OUT" >&2
  exit 526
fi

echo "[gate] F142: C vs Python — preloop import|+link| then component| + six memory|emit|… (bare/with ×3) + component| + memory|say|"
F142EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_hexa_mixed_bare_with_bare_with_bare_with_emit_component_say.azl"
F142_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F142EX" boot.entry 2>&1)"
f142_c_rc=$?
if [ "$f142_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_hexa_mixed_bare_with_bare_with_bare_with_emit_component_say exited $f142_c_rc: $F142_C_OUT"
  exit 527
fi
if ! printf '%s\n' "$F142_C_OUT" | awk 'NR==1{if($0!="F142_TREE")exit 1} NR==2{if($0!="P142_LINK_SID")exit 1} NR==3{if($0!="P142_A")exit 1} NR==4{if($0!="F142_BARE_1")exit 1} NR==5{if($0!="F142_PA")exit 1} NR==6{if($0!="F142_BARE_3")exit 1} NR==7{if($0!="F142_PB")exit 1} NR==8{if($0!="F142_BARE_5")exit 1} NR==9{if($0!="F142_PC")exit 1} NR==10{if($0!="P142_B")exit 1} NR==11{if($0!="F142_MEM")exit 1} NR==12{if($0!="i")exit 1} NR==13{if($0!="EX142_POST")exit 1} NR==14{if($0!="Said: F142_MEM")exit 1} NR==15{if($0!="EC142_INNER")exit 1} NR==16{if($0!="Said: F142_MEM")exit 1} NR==17{if($0!="P0_SEM_F142_OK")exit 1} END{if(NR!=17)exit 1}'; then
  echo "ERROR: expected F142 preloop + component| + hexa bare/with memory|emit + component| + memory|say stdout (17 lines), got: $F142_C_OUT"
  exit 527
fi
F142_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F142EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f142_py_rc=$?
if [ "$f142_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_hexa_mixed_bare_with_bare_with_bare_with_emit_component_say exited $f142_py_rc: $F142_PY_OUT"
  exit 528
fi
if [ "$F142_C_OUT" != "$F142_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_hexa_mixed_bare_with_bare_with_bare_with_emit_component_say" >&2
  echo "C:  $F142_C_OUT" >&2
  echo "Py: $F142_PY_OUT" >&2
  exit 529
fi

echo "[gate] F143: C vs Python — preloop import|+link| then component| + six memory|emit|… (with/bare ×3) + component| + memory|say|"
F143EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_hexa_mixed_with_bare_with_bare_with_bare_emit_component_say.azl"
F143_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F143EX" boot.entry 2>&1)"
f143_c_rc=$?
if [ "$f143_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_hexa_mixed_with_bare_with_bare_with_bare_emit_component_say exited $f143_c_rc: $F143_C_OUT"
  exit 530
fi
if ! printf '%s\n' "$F143_C_OUT" | awk 'NR==1{if($0!="F143_TREE")exit 1} NR==2{if($0!="P143_LINK_SID")exit 1} NR==3{if($0!="P143_A")exit 1} NR==4{if($0!="F143_PA")exit 1} NR==5{if($0!="F143_BARE_2")exit 1} NR==6{if($0!="F143_PB")exit 1} NR==7{if($0!="F143_BARE_4")exit 1} NR==8{if($0!="F143_PC")exit 1} NR==9{if($0!="F143_BARE_6")exit 1} NR==10{if($0!="P143_B")exit 1} NR==11{if($0!="F143_MEM")exit 1} NR==12{if($0!="i")exit 1} NR==13{if($0!="EX143_POST")exit 1} NR==14{if($0!="Said: F143_MEM")exit 1} NR==15{if($0!="EC143_INNER")exit 1} NR==16{if($0!="Said: F143_MEM")exit 1} NR==17{if($0!="P0_SEM_F143_OK")exit 1} END{if(NR!=17)exit 1}'; then
  echo "ERROR: expected F143 preloop + component| + hexa with/bare memory|emit + component| + memory|say stdout (17 lines), got: $F143_C_OUT"
  exit 530
fi
F143_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F143EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f143_py_rc=$?
if [ "$f143_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_hexa_mixed_with_bare_with_bare_with_bare_emit_component_say exited $f143_py_rc: $F143_PY_OUT"
  exit 531
fi
if [ "$F143_C_OUT" != "$F143_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_hexa_mixed_with_bare_with_bare_with_bare_emit_component_say" >&2
  echo "C:  $F143_C_OUT" >&2
  echo "Py: $F143_PY_OUT" >&2
  exit 532
fi

echo "[gate] F144: C vs Python — preloop import|+link| then component| + seven bare memory|emit|… + component| + memory|say|"
F144EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_hepta_bare_emit_component_say.azl"
F144_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F144EX" boot.entry 2>&1)"
f144_c_rc=$?
if [ "$f144_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_hepta_bare_emit_component_say exited $f144_c_rc: $F144_C_OUT"
  exit 533
fi
if ! printf '%s\n' "$F144_C_OUT" | awk 'NR==1{if($0!="F144_TREE")exit 1} NR==2{if($0!="P144_LINK_SID")exit 1} NR==3{if($0!="P144_A")exit 1} NR==4{if($0!="F144_BARE_1")exit 1} NR==5{if($0!="F144_BARE_2")exit 1} NR==6{if($0!="F144_BARE_3")exit 1} NR==7{if($0!="F144_BARE_4")exit 1} NR==8{if($0!="F144_BARE_5")exit 1} NR==9{if($0!="F144_BARE_6")exit 1} NR==10{if($0!="F144_BARE_7")exit 1} NR==11{if($0!="P144_B")exit 1} NR==12{if($0!="F144_MEM")exit 1} NR==13{if($0!="i")exit 1} NR==14{if($0!="EX144_POST")exit 1} NR==15{if($0!="Said: F144_MEM")exit 1} NR==16{if($0!="EC144_INNER")exit 1} NR==17{if($0!="Said: F144_MEM")exit 1} NR==18{if($0!="P0_SEM_F144_OK")exit 1} END{if(NR!=18)exit 1}'; then
  echo "ERROR: expected F144 preloop + component| + hepta bare memory|emit + component| + memory|say stdout (18 lines), got: $F144_C_OUT"
  exit 533
fi
F144_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F144EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f144_py_rc=$?
if [ "$f144_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_hepta_bare_emit_component_say exited $f144_py_rc: $F144_PY_OUT"
  exit 534
fi
if [ "$F144_C_OUT" != "$F144_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_hepta_bare_emit_component_say" >&2
  echo "C:  $F144_C_OUT" >&2
  echo "Py: $F144_PY_OUT" >&2
  exit 535
fi

echo "[gate] F145: C vs Python — preloop import|+link| then component| + eight bare memory|emit|… + component| + memory|say|"
F145EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_octa_bare_emit_component_say.azl"
F145_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F145EX" boot.entry 2>&1)"
f145_c_rc=$?
if [ "$f145_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_octa_bare_emit_component_say exited $f145_c_rc: $F145_C_OUT"
  exit 536
fi
if ! printf '%s\n' "$F145_C_OUT" | awk 'NR==1{if($0!="F145_TREE")exit 1} NR==2{if($0!="P145_LINK_SID")exit 1} NR==3{if($0!="P145_A")exit 1} NR==4{if($0!="F145_BARE_1")exit 1} NR==5{if($0!="F145_BARE_2")exit 1} NR==6{if($0!="F145_BARE_3")exit 1} NR==7{if($0!="F145_BARE_4")exit 1} NR==8{if($0!="F145_BARE_5")exit 1} NR==9{if($0!="F145_BARE_6")exit 1} NR==10{if($0!="F145_BARE_7")exit 1} NR==11{if($0!="F145_BARE_8")exit 1} NR==12{if($0!="P145_B")exit 1} NR==13{if($0!="F145_MEM")exit 1} NR==14{if($0!="i")exit 1} NR==15{if($0!="EX145_POST")exit 1} NR==16{if($0!="Said: F145_MEM")exit 1} NR==17{if($0!="EC145_INNER")exit 1} NR==18{if($0!="Said: F145_MEM")exit 1} NR==19{if($0!="P0_SEM_F145_OK")exit 1} END{if(NR!=19)exit 1}'; then
  echo "ERROR: expected F145 preloop + component| + octa bare memory|emit + component| + memory|say stdout (19 lines), got: $F145_C_OUT"
  exit 536
fi
F145_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F145EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f145_py_rc=$?
if [ "$f145_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_octa_bare_emit_component_say exited $f145_py_rc: $F145_PY_OUT"
  exit 537
fi
if [ "$F145_C_OUT" != "$F145_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_octa_bare_emit_component_say" >&2
  echo "C:  $F145_C_OUT" >&2
  echo "Py: $F145_PY_OUT" >&2
  exit 538
fi

echo "[gate] F146: C vs Python — preloop import|+link| then component| + nine bare memory|emit|… + component| + memory|say|"
F146EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_nona_bare_emit_component_say.azl"
F146_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F146EX" boot.entry 2>&1)"
f146_c_rc=$?
if [ "$f146_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_nona_bare_emit_component_say exited $f146_c_rc: $F146_C_OUT"
  exit 539
fi
if ! printf '%s\n' "$F146_C_OUT" | awk 'NR==1{if($0!="F146_TREE")exit 1} NR==2{if($0!="P146_LINK_SID")exit 1} NR==3{if($0!="P146_A")exit 1} NR==4{if($0!="F146_BARE_1")exit 1} NR==5{if($0!="F146_BARE_2")exit 1} NR==6{if($0!="F146_BARE_3")exit 1} NR==7{if($0!="F146_BARE_4")exit 1} NR==8{if($0!="F146_BARE_5")exit 1} NR==9{if($0!="F146_BARE_6")exit 1} NR==10{if($0!="F146_BARE_7")exit 1} NR==11{if($0!="F146_BARE_8")exit 1} NR==12{if($0!="F146_BARE_9")exit 1} NR==13{if($0!="P146_B")exit 1} NR==14{if($0!="F146_MEM")exit 1} NR==15{if($0!="i")exit 1} NR==16{if($0!="EX146_POST")exit 1} NR==17{if($0!="Said: F146_MEM")exit 1} NR==18{if($0!="EC146_INNER")exit 1} NR==19{if($0!="Said: F146_MEM")exit 1} NR==20{if($0!="P0_SEM_F146_OK")exit 1} END{if(NR!=20)exit 1}'; then
  echo "ERROR: expected F146 preloop + component| + nona bare memory|emit + component| + memory|say stdout (20 lines), got: $F146_C_OUT"
  exit 539
fi
F146_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F146EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f146_py_rc=$?
if [ "$f146_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_nona_bare_emit_component_say exited $f146_py_rc: $F146_PY_OUT"
  exit 540
fi
if [ "$F146_C_OUT" != "$F146_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_nona_bare_emit_component_say" >&2
  echo "C:  $F146_C_OUT" >&2
  echo "Py: $F146_PY_OUT" >&2
  exit 541
fi

echo "[gate] F147: C vs Python — preloop import|+link| then component| + ten bare memory|emit|… + component| + memory|say|"
F147EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_deca_bare_emit_component_say.azl"
F147_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F147EX" boot.entry 2>&1)"
f147_c_rc=$?
if [ "$f147_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_deca_bare_emit_component_say exited $f147_c_rc: $F147_C_OUT"
  exit 542
fi
if ! printf '%s\n' "$F147_C_OUT" | awk 'NR==1{if($0!="F147_TREE")exit 1} NR==2{if($0!="P147_LINK_SID")exit 1} NR==3{if($0!="P147_A")exit 1} NR==4{if($0!="F147_BARE_1")exit 1} NR==5{if($0!="F147_BARE_2")exit 1} NR==6{if($0!="F147_BARE_3")exit 1} NR==7{if($0!="F147_BARE_4")exit 1} NR==8{if($0!="F147_BARE_5")exit 1} NR==9{if($0!="F147_BARE_6")exit 1} NR==10{if($0!="F147_BARE_7")exit 1} NR==11{if($0!="F147_BARE_8")exit 1} NR==12{if($0!="F147_BARE_9")exit 1} NR==13{if($0!="F147_BARE_10")exit 1} NR==14{if($0!="P147_B")exit 1} NR==15{if($0!="F147_MEM")exit 1} NR==16{if($0!="i")exit 1} NR==17{if($0!="EX147_POST")exit 1} NR==18{if($0!="Said: F147_MEM")exit 1} NR==19{if($0!="EC147_INNER")exit 1} NR==20{if($0!="Said: F147_MEM")exit 1} NR==21{if($0!="P0_SEM_F147_OK")exit 1} END{if(NR!=21)exit 1}'; then
  echo "ERROR: expected F147 preloop + component| + deca bare memory|emit + component| + memory|say stdout (21 lines), got: $F147_C_OUT"
  exit 542
fi
F147_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F147EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f147_py_rc=$?
if [ "$f147_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_deca_bare_emit_component_say exited $f147_py_rc: $F147_PY_OUT"
  exit 543
fi
if [ "$F147_C_OUT" != "$F147_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_deca_bare_emit_component_say" >&2
  echo "C:  $F147_C_OUT" >&2
  echo "Py: $F147_PY_OUT" >&2
  exit 544
fi

echo "[gate] F148: C vs Python — preloop import|+link| then component| + eleven bare memory|emit|… + component| + memory|say|"
F148EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_preloop_component_memory_undeca_bare_emit_component_say.azl"
F148_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F148EX" boot.entry 2>&1)"
f148_c_rc=$?
if [ "$f148_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_preloop_component_memory_undeca_bare_emit_component_say exited $f148_c_rc: $F148_C_OUT"
  exit 545
fi
if ! printf '%s\n' "$F148_C_OUT" | awk 'NR==1{if($0!="F148_TREE")exit 1} NR==2{if($0!="P148_LINK_SID")exit 1} NR==3{if($0!="P148_A")exit 1} NR==4{if($0!="F148_BARE_1")exit 1} NR==5{if($0!="F148_BARE_2")exit 1} NR==6{if($0!="F148_BARE_3")exit 1} NR==7{if($0!="F148_BARE_4")exit 1} NR==8{if($0!="F148_BARE_5")exit 1} NR==9{if($0!="F148_BARE_6")exit 1} NR==10{if($0!="F148_BARE_7")exit 1} NR==11{if($0!="F148_BARE_8")exit 1} NR==12{if($0!="F148_BARE_9")exit 1} NR==13{if($0!="F148_BARE_10")exit 1} NR==14{if($0!="F148_BARE_11")exit 1} NR==15{if($0!="P148_B")exit 1} NR==16{if($0!="F148_MEM")exit 1} NR==17{if($0!="i")exit 1} NR==18{if($0!="EX148_POST")exit 1} NR==19{if($0!="Said: F148_MEM")exit 1} NR==20{if($0!="EC148_INNER")exit 1} NR==21{if($0!="Said: F148_MEM")exit 1} NR==22{if($0!="P0_SEM_F148_OK")exit 1} END{if(NR!=22)exit 1}'; then
  echo "ERROR: expected F148 preloop + component| + undeca bare memory|emit + component| + memory|say stdout (22 lines), got: $F148_C_OUT"
  exit 545
fi
F148_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F148EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f148_py_rc=$?
if [ "$f148_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_preloop_component_memory_undeca_bare_emit_component_say exited $f148_py_rc: $F148_PY_OUT"
  exit 546
fi
if [ "$F148_C_OUT" != "$F148_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_preloop_component_memory_undeca_bare_emit_component_say" >&2
  echo "C:  $F148_C_OUT" >&2
  echo "Py: $F148_PY_OUT" >&2
  exit 547
fi

echo "[gate] F149: C vs Python — ::parse_tokens(::tokens) from tz buffer → ::ast.nodes say|…"
F149EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_say_identifier.azl"
F149_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F149EX" boot.entry 2>&1)"
f149_c_rc=$?
if [ "$f149_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_say_identifier exited $f149_c_rc: $F149_C_OUT"
  exit 560
fi
if ! printf '%s\n' "$F149_C_OUT" | awk 'NR==1{if($0!="say|F149_PAYLOAD")exit 1} NR==2{if($0!="P0_SEM_F149_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F149 ::parse_tokens stdout (2 lines: say|F149_PAYLOAD, P0_SEM_F149_OK), got: $F149_C_OUT"
  exit 560
fi
F149_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F149EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f149_py_rc=$?
if [ "$f149_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_say_identifier exited $f149_py_rc: $F149_PY_OUT"
  exit 561
fi
if [ "$F149_C_OUT" != "$F149_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_say_identifier" >&2
  echo "C:  $F149_C_OUT" >&2
  echo "Py: $F149_PY_OUT" >&2
  exit 562
fi

echo "[gate] F150: C vs Python — ::parse_tokens say + set + emit (tokenize_line, Var cap safe)"
F150EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_multi_statements.azl"
F150_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F150EX" boot.entry 2>&1)"
f150_c_rc=$?
if [ "$f150_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_multi_statements exited $f150_c_rc: $F150_C_OUT"
  exit 563
fi
if ! printf '%s\n' "$F150_C_OUT" | awk 'NR==1{if($0!="say|A")exit 1} NR==2{if($0!="set|::f|z")exit 1} NR==3{if($0!="emit|e")exit 1} NR==4{if($0!="P0_SEM_F150_OK")exit 1} END{if(NR!=4)exit 1}'; then
  echo "ERROR: expected F150 parse_tokens stdout (4 lines), got: $F150_C_OUT"
  exit 563
fi
F150_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F150EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f150_py_rc=$?
if [ "$f150_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_multi_statements exited $f150_py_rc: $F150_PY_OUT"
  exit 564
fi
if [ "$F150_C_OUT" != "$F150_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_multi_statements" >&2
  echo "C:  $F150_C_OUT" >&2
  echo "Py: $F150_PY_OUT" >&2
  exit 565
fi

echo "[gate] F151: C vs Python — ::parse_tokens import + link + say (tokenize_line)"
F151EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_import_link_say.azl"
F151_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F151EX" boot.entry 2>&1)"
f151_c_rc=$?
if [ "$f151_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_import_link_say exited $f151_c_rc: $F151_C_OUT"
  exit 566
fi
if ! printf '%s\n' "$F151_C_OUT" | awk 'NR==1{if($0!="import|m")exit 1} NR==2{if($0!="link|::l")exit 1} NR==3{if($0!="say|Z")exit 1} NR==4{if($0!="P0_SEM_F151_OK")exit 1} END{if(NR!=4)exit 1}'; then
  echo "ERROR: expected F151 parse_tokens stdout (4 lines), got: $F151_C_OUT"
  exit 566
fi
F151_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F151EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f151_py_rc=$?
if [ "$f151_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_import_link_say exited $f151_py_rc: $F151_PY_OUT"
  exit 567
fi
if [ "$F151_C_OUT" != "$F151_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_import_link_say" >&2
  echo "C:  $F151_C_OUT" >&2
  echo "Py: $F151_PY_OUT" >&2
  exit 568
fi

echo "[gate] F152: C vs Python — ::parse_tokens emit … with { k: v } → emit|…|with|k|v"
F152EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_emit_with_brace.azl"
F152_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F152EX" boot.entry 2>&1)"
f152_c_rc=$?
if [ "$f152_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_emit_with_brace exited $f152_c_rc: $F152_C_OUT"
  exit 569
fi
if ! printf '%s\n' "$F152_C_OUT" | awk 'NR==1{if($0!="emit|w|with|k|a")exit 1} NR==2{if($0!="P0_SEM_F152_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F152 parse_tokens stdout (2 lines), got: $F152_C_OUT"
  exit 569
fi
F152_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F152EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f152_py_rc=$?
if [ "$f152_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_emit_with_brace exited $f152_py_rc: $F152_PY_OUT"
  exit 570
fi
if [ "$F152_C_OUT" != "$F152_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_emit_with_brace" >&2
  echo "C:  $F152_C_OUT" >&2
  echo "Py: $F152_PY_OUT" >&2
  exit 571
fi

echo "[gate] F153: C vs Python — ::parse_tokens emit … with { a: b, c: d } → emit|…|with|a|b|c|d"
F153EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_emit_with_multi.azl"
F153_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F153EX" boot.entry 2>&1)"
f153_c_rc=$?
if [ "$f153_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_emit_with_multi exited $f153_c_rc: $F153_C_OUT"
  exit 572
fi
if ! printf '%s\n' "$F153_C_OUT" | awk 'NR==1{if($0!="emit|w|with|a|b|c|d")exit 1} NR==2{if($0!="P0_SEM_F153_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F153 parse_tokens stdout (2 lines), got: $F153_C_OUT"
  exit 572
fi
F153_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F153EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f153_py_rc=$?
if [ "$f153_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_emit_with_multi exited $f153_py_rc: $F153_PY_OUT"
  exit 573
fi
if [ "$F153_C_OUT" != "$F153_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_emit_with_multi" >&2
  echo "C:  $F153_C_OUT" >&2
  echo "Py: $F153_PY_OUT" >&2
  exit 574
fi

echo "[gate] F154: C vs Python — ::parse_tokens component ::c154 → component|::c154"
F154EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_component.azl"
F154_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F154EX" boot.entry 2>&1)"
f154_c_rc=$?
if [ "$f154_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_component exited $f154_c_rc: $F154_C_OUT"
  exit 575
fi
if ! printf '%s\n' "$F154_C_OUT" | awk 'NR==1{if($0!="component|::c154")exit 1} NR==2{if($0!="P0_SEM_F154_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F154 parse_tokens stdout (2 lines), got: $F154_C_OUT"
  exit 575
fi
F154_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F154EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f154_py_rc=$?
if [ "$f154_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_component exited $f154_py_rc: $F154_PY_OUT"
  exit 576
fi
if [ "$F154_C_OUT" != "$F154_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_component" >&2
  echo "C:  $F154_C_OUT" >&2
  echo "Py: $F154_PY_OUT" >&2
  exit 577
fi

echo "[gate] F155: C vs Python — ::parse_tokens listen for ev { say pay } → listen|ev|say|pay"
F155EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_say.azl"
F155_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F155EX" boot.entry 2>&1)"
f155_c_rc=$?
if [ "$f155_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_say exited $f155_c_rc: $F155_C_OUT"
  exit 578
fi
if ! printf '%s\n' "$F155_C_OUT" | awk 'NR==1{if($0!="listen|e155|say|PAY155")exit 1} NR==2{if($0!="P0_SEM_F155_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F155 parse_tokens stdout (2 lines), got: $F155_C_OUT"
  exit 578
fi
F155_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F155EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f155_py_rc=$?
if [ "$f155_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_say exited $f155_py_rc: $F155_PY_OUT"
  exit 579
fi
if [ "$F155_C_OUT" != "$F155_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_say" >&2
  echo "C:  $F155_C_OUT" >&2
  echo "Py: $F155_PY_OUT" >&2
  exit 580
fi

echo "[gate] F156: C vs Python — ::parse_tokens listen for … then { say … }"
F156EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_then_say.azl"
F156_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F156EX" boot.entry 2>&1)"
f156_c_rc=$?
if [ "$f156_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_then_say exited $f156_c_rc: $F156_C_OUT"
  exit 581
fi
if ! printf '%s\n' "$F156_C_OUT" | awk 'NR==1{if($0!="listen|f156|say|PAY156")exit 1} NR==2{if($0!="P0_SEM_F156_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F156 parse_tokens stdout (2 lines), got: $F156_C_OUT"
  exit 581
fi
F156_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F156EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f156_py_rc=$?
if [ "$f156_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_then_say exited $f156_py_rc: $F156_PY_OUT"
  exit 582
fi
if [ "$F156_C_OUT" != "$F156_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_then_say" >&2
  echo "C:  $F156_C_OUT" >&2
  echo "Py: $F156_PY_OUT" >&2
  exit 583
fi

echo "[gate] F157: C vs Python — ::parse_tokens listen { emit … }"
F157EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_emit.azl"
F157_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F157EX" boot.entry 2>&1)"
f157_c_rc=$?
if [ "$f157_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_emit exited $f157_c_rc: $F157_C_OUT"
  exit 584
fi
if ! printf '%s\n' "$F157_C_OUT" | awk 'NR==1{if($0!="listen|f157|emit|E157")exit 1} NR==2{if($0!="P0_SEM_F157_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F157 parse_tokens stdout (2 lines), got: $F157_C_OUT"
  exit 584
fi
F157_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F157EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f157_py_rc=$?
if [ "$f157_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_emit exited $f157_py_rc: $F157_PY_OUT"
  exit 585
fi
if [ "$F157_C_OUT" != "$F157_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_emit" >&2
  echo "C:  $F157_C_OUT" >&2
  echo "Py: $F157_PY_OUT" >&2
  exit 586
fi

echo "[gate] F158: C vs Python — ::parse_tokens listen { emit … with { k: v } }"
F158EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_emit_with.azl"
F158_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F158EX" boot.entry 2>&1)"
f158_c_rc=$?
if [ "$f158_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_emit_with exited $f158_c_rc: $F158_C_OUT"
  exit 587
fi
if ! printf '%s\n' "$F158_C_OUT" | awk 'NR==1{if($0!="listen|f158|emit|em158|with|k|a")exit 1} NR==2{if($0!="P0_SEM_F158_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F158 parse_tokens stdout (2 lines), got: $F158_C_OUT"
  exit 587
fi
F158_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F158EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f158_py_rc=$?
if [ "$f158_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_emit_with exited $f158_py_rc: $F158_PY_OUT"
  exit 588
fi
if [ "$F158_C_OUT" != "$F158_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_emit_with" >&2
  echo "C:  $F158_C_OUT" >&2
  echo "Py: $F158_PY_OUT" >&2
  exit 589
fi

echo "[gate] F159: C vs Python — ::parse_tokens listen { set ::g = v }"
F159EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_set.azl"
F159_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F159EX" boot.entry 2>&1)"
f159_c_rc=$?
if [ "$f159_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_set exited $f159_c_rc: $F159_C_OUT"
  exit 590
fi
if ! printf '%s\n' "$F159_C_OUT" | awk 'NR==1{if($0!="listen|f159|set|::g159|V159")exit 1} NR==2{if($0!="P0_SEM_F159_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F159 parse_tokens stdout (2 lines), got: $F159_C_OUT"
  exit 590
fi
F159_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F159EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f159_py_rc=$?
if [ "$f159_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_set exited $f159_py_rc: $F159_PY_OUT"
  exit 591
fi
if [ "$F159_C_OUT" != "$F159_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_set" >&2
  echo "C:  $F159_C_OUT" >&2
  echo "Py: $F159_PY_OUT" >&2
  exit 592
fi

echo "[gate] F160: C vs Python — ::parse_tokens memory say …"
F160EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_memory_say.azl"
F160_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F160EX" boot.entry 2>&1)"
f160_c_rc=$?
if [ "$f160_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_memory_say exited $f160_c_rc: $F160_C_OUT"
  exit 593
fi
if ! printf '%s\n' "$F160_C_OUT" | awk 'NR==1{if($0!="memory|say|F160_LINE")exit 1} NR==2{if($0!="P0_SEM_F160_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F160 parse_tokens stdout (2 lines), got: $F160_C_OUT"
  exit 593
fi
F160_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F160EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f160_py_rc=$?
if [ "$f160_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_memory_say exited $f160_py_rc: $F160_PY_OUT"
  exit 594
fi
if [ "$F160_C_OUT" != "$F160_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_memory_say" >&2
  echo "C:  $F160_C_OUT" >&2
  echo "Py: $F160_PY_OUT" >&2
  exit 595
fi

echo "[gate] F161: C vs Python — ::parse_tokens memory set …"
F161EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_memory_set.azl"
F161_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F161EX" boot.entry 2>&1)"
f161_c_rc=$?
if [ "$f161_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_memory_set exited $f161_c_rc: $F161_C_OUT"
  exit 596
fi
if ! printf '%s\n' "$F161_C_OUT" | awk 'NR==1{if($0!="memory|set|::f161_slot|F161_CELL")exit 1} NR==2{if($0!="P0_SEM_F161_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F161 parse_tokens stdout (2 lines), got: $F161_C_OUT"
  exit 596
fi
F161_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F161EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f161_py_rc=$?
if [ "$f161_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_memory_set exited $f161_py_rc: $F161_PY_OUT"
  exit 597
fi
if [ "$F161_C_OUT" != "$F161_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_memory_set" >&2
  echo "C:  $F161_C_OUT" >&2
  echo "Py: $F161_PY_OUT" >&2
  exit 598
fi

echo "[gate] F162: C vs Python — ::parse_tokens memory emit … (bare)"
F162EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_memory_emit.azl"
F162_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F162EX" boot.entry 2>&1)"
f162_c_rc=$?
if [ "$f162_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_memory_emit exited $f162_c_rc: $F162_C_OUT"
  exit 599
fi
if ! printf '%s\n' "$F162_C_OUT" | awk 'NR==1{if($0!="memory|emit|F162_EVT")exit 1} NR==2{if($0!="P0_SEM_F162_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F162 parse_tokens stdout (2 lines), got: $F162_C_OUT"
  exit 599
fi
F162_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F162EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f162_py_rc=$?
if [ "$f162_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_memory_emit exited $f162_py_rc: $F162_PY_OUT"
  exit 600
fi
if [ "$F162_C_OUT" != "$F162_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_memory_emit" >&2
  echo "C:  $F162_C_OUT" >&2
  echo "Py: $F162_PY_OUT" >&2
  exit 601
fi

echo "[gate] F163: C vs Python — ::parse_tokens memory emit … with { k: v }"
F163EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_memory_emit_with.azl"
F163_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F163EX" boot.entry 2>&1)"
f163_c_rc=$?
if [ "$f163_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_memory_emit_with exited $f163_c_rc: $F163_C_OUT"
  exit 602
fi
if ! printf '%s\n' "$F163_C_OUT" | awk 'NR==1{if($0!="memory|emit|f163|with|pk|pv")exit 1} NR==2{if($0!="P0_SEM_F163_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F163 parse_tokens stdout (2 lines), got: $F163_C_OUT"
  exit 602
fi
F163_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F163EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f163_py_rc=$?
if [ "$f163_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_memory_emit_with exited $f163_py_rc: $F163_PY_OUT"
  exit 603
fi
if [ "$F163_C_OUT" != "$F163_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_memory_emit_with" >&2
  echo "C:  $F163_C_OUT" >&2
  echo "Py: $F163_PY_OUT" >&2
  exit 604
fi

echo "[gate] F164: C vs Python — ::parse_tokens memory emit … with multi-pair { }"
F164EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_memory_emit_multi_with.azl"
F164_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F164EX" boot.entry 2>&1)"
f164_c_rc=$?
if [ "$f164_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_memory_emit_multi_with exited $f164_c_rc: $F164_C_OUT"
  exit 605
fi
if ! printf '%s\n' "$F164_C_OUT" | awk 'NR==1{if($0!="memory|emit|m164|with|a|b|c|d")exit 1} NR==2{if($0!="P0_SEM_F164_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F164 parse_tokens stdout (2 lines), got: $F164_C_OUT"
  exit 605
fi
F164_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F164EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f164_py_rc=$?
if [ "$f164_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_memory_emit_multi_with exited $f164_py_rc: $F164_PY_OUT"
  exit 606
fi
if [ "$F164_C_OUT" != "$F164_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_memory_emit_multi_with" >&2
  echo "C:  $F164_C_OUT" >&2
  echo "Py: $F164_PY_OUT" >&2
  exit 607
fi

echo "[gate] F165: C vs Python — ::parse_tokens listen { emit … with multi-pair { } }"
F165EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_emit_multi_with.azl"
F165_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F165EX" boot.entry 2>&1)"
f165_c_rc=$?
if [ "$f165_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_emit_multi_with exited $f165_c_rc: $F165_C_OUT"
  exit 608
fi
if ! printf '%s\n' "$F165_C_OUT" | awk 'NR==1{if($0!="listen|f165|emit|em165|with|a|b|c|d")exit 1} NR==2{if($0!="P0_SEM_F165_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F165 parse_tokens stdout (2 lines), got: $F165_C_OUT"
  exit 608
fi
F165_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F165EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f165_py_rc=$?
if [ "$f165_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_emit_multi_with exited $f165_py_rc: $F165_PY_OUT"
  exit 609
fi
if [ "$F165_C_OUT" != "$F165_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_emit_multi_with" >&2
  echo "C:  $F165_C_OUT" >&2
  echo "Py: $F165_PY_OUT" >&2
  exit 610
fi

echo "[gate] F166: C vs Python — ::parse_tokens listen { dual say } (multi-statement body)"
F166EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_multi_say.azl"
F166_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F166EX" boot.entry 2>&1)"
f166_c_rc=$?
if [ "$f166_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_multi_say exited $f166_c_rc: $F166_C_OUT"
  exit 612
fi
if ! printf '%s\n' "$F166_C_OUT" | awk 'NR==1{if($0!="listen|f166|say|F166_A")exit 1} NR==2{if($0!="listen|f166|say|F166_B")exit 1} NR==3{if($0!="P0_SEM_F166_OK")exit 1} END{if(NR!=3)exit 1}'; then
  echo "ERROR: expected F166 parse_tokens stdout (3 lines), got: $F166_C_OUT"
  exit 612
fi
F166_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F166EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f166_py_rc=$?
if [ "$f166_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_multi_say exited $f166_py_rc: $F166_PY_OUT"
  exit 613
fi
if [ "$F166_C_OUT" != "$F166_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_multi_say" >&2
  echo "C:  $F166_C_OUT" >&2
  echo "Py: $F166_PY_OUT" >&2
  exit 614
fi

echo "[gate] F167: C vs Python — ::parse_tokens listen { say … ; emit … ; } (bare emit at eol)"
F167EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_say_emit.azl"
F167_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F167EX" boot.entry 2>&1)"
f167_c_rc=$?
if [ "$f167_c_rc" -ne 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_say_emit exited $f167_c_rc: $F167_C_OUT"
  exit 615
fi
if ! printf '%s\n' "$F167_C_OUT" | awk 'NR==1{if($0!="listen|f167|say|F167_SAY")exit 1} NR==2{if($0!="listen|f167|emit|F167_EMIT")exit 1} NR==3{if($0!="P0_SEM_F167_OK")exit 1} END{if(NR!=3)exit 1}'; then
  echo "ERROR: expected F167 parse_tokens stdout (3 lines), got: $F167_C_OUT"
  exit 615
fi
F167_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F167EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f167_py_rc=$?
if [ "$f167_py_rc" -ne 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_say_emit exited $f167_py_rc: $F167_PY_OUT"
  exit 616
fi
if [ "$F167_C_OUT" != "$F167_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_say_emit" >&2
  echo "C:  $F167_C_OUT" >&2
  echo "Py: $F167_PY_OUT" >&2
  exit 617
fi

echo "[gate] F168: C vs Python — spine_component_v1 parse → execute_ast (init / listen / memory)"
F168EX="${ROOT_DIR}/azl/tests/p0_semantic_spine_structured_component_e2e.azl"
F168_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F168EX" boot.entry 2>&1)"
f168_c_rc=$?
if [ "$f168_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_spine_structured_component_e2e exited $f168_c_rc: $F168_C_OUT"
  exit 618
fi
if ! printf '%s\n' "$F168_C_OUT" | awk 'NR==1{if($0!="F168_INIT")exit 1} NR==2{if($0!="F168_L")exit 1} NR==3{if($0!="F168_M")exit 1} NR==4{if($0!="Said: '\''F168_M'\''")exit 1} NR==5{if($0!="P0_SEM_F168_OK")exit 1} END{if(NR!=5)exit 1}'; then
  echo "ERROR: expected F168 stdout (5 lines), got: $F168_C_OUT"
  exit 618
fi
F168_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F168EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f168_py_rc=$?
if [ "$f168_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_spine_structured_component_e2e exited $f168_py_rc: $F168_PY_OUT"
  exit 619
fi
if [ "$F168_C_OUT" != "$F168_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_spine_structured_component_e2e" >&2
  echo "C:  $F168_C_OUT" >&2
  echo "Py: $F168_PY_OUT" >&2
  exit 620
fi

echo "[gate] F169: C vs Python — spine_component_v1 listen body say + set + emit (one listener)"
F169EX="${ROOT_DIR}/azl/tests/p0_semantic_spine_component_listen_say_set_emit.azl"
F169_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F169EX" boot.entry 2>&1)"
f169_c_rc=$?
if [ "$f169_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_spine_component_listen_say_set_emit exited $f169_c_rc: $F169_C_OUT"
  exit 621
fi
if ! printf '%s\n' "$F169_C_OUT" | awk 'NR==1{if($0!="F169_I")exit 1} NR==2{if($0!="F169_S")exit 1} NR==3{if($0!="F169_M")exit 1} NR==4{if($0!="mark")exit 1} NR==5{if($0!="Said: ::lb169")exit 1} NR==6{if($0!="P0_SEM_F169_OK")exit 1} END{if(NR!=6)exit 1}'; then
  echo "ERROR: expected F169 stdout (6 lines), got: $F169_C_OUT"
  exit 621
fi
F169_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F169EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f169_py_rc=$?
if [ "$f169_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_spine_component_listen_say_set_emit exited $f169_py_rc: $F169_PY_OUT"
  exit 622
fi
if [ "$F169_C_OUT" != "$F169_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_spine_component_listen_say_set_emit" >&2
  echo "C:  $F169_C_OUT" >&2
  echo "Py: $F169_PY_OUT" >&2
  exit 623
fi

echo "[gate] F170: C vs Python — spine_component_v1 emit with { k: v } + downstream payload"
F170EX="${ROOT_DIR}/azl/tests/p0_semantic_spine_component_listen_emit_with_payload.azl"
F170_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F170EX" boot.entry 2>&1)"
f170_c_rc=$?
if [ "$f170_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_spine_component_listen_emit_with_payload exited $f170_c_rc: $F170_C_OUT"
  exit 624
fi
if ! printf '%s\n' "$F170_C_OUT" | awk 'NR==1{if($0!="F170_I")exit 1} NR==2{if($0!="F170_S")exit 1} NR==3{if($0!="F170_CELL")exit 1} NR==4{if($0!="F170_M")exit 1} NR==5{if($0!="ready")exit 1} NR==6{if($0!="Said: ::flag170")exit 1} NR==7{if($0!="P0_SEM_F170_OK")exit 1} END{if(NR!=7)exit 1}'; then
  echo "ERROR: expected F170 stdout (7 lines), got: $F170_C_OUT"
  exit 624
fi
F170_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F170EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f170_py_rc=$?
if [ "$f170_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_spine_component_listen_emit_with_payload exited $f170_py_rc: $F170_PY_OUT"
  exit 625
fi
if [ "$F170_C_OUT" != "$F170_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_spine_component_listen_emit_with_payload" >&2
  echo "C:  $F170_C_OUT" >&2
  echo "Py: $F170_PY_OUT" >&2
  exit 626
fi

echo "[gate] F171: C vs Python — parse_tokens listen { set … ; emit … }"
F171EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_set_emit.azl"
F171_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F171EX" boot.entry 2>&1)"
f171_c_rc=$?
if [ "$f171_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_set_emit exited $f171_c_rc: $F171_C_OUT"
  exit 627
fi
if ! printf '%s\n' "$F171_C_OUT" | awk 'NR==1{if($0!="listen|f171|set|::g171|V171")exit 1} NR==2{if($0!="listen|f171|emit|E171")exit 1} NR==3{if($0!="P0_SEM_F171_OK")exit 1} END{if(NR!=3)exit 1}'; then
  echo "ERROR: expected F171 stdout (3 lines), got: $F171_C_OUT"
  exit 627
fi
F171_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F171EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f171_py_rc=$?
if [ "$f171_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_set_emit exited $f171_py_rc: $F171_PY_OUT"
  exit 628
fi
if [ "$F171_C_OUT" != "$F171_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_set_emit" >&2
  echo "C:  $F171_C_OUT" >&2
  echo "Py: $F171_PY_OUT" >&2
  exit 629
fi

echo "[gate] F172: C vs Python — parse_tokens listen { set … ; emit … with { k: v } }"
F172EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_set_emit_with.azl"
F172_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F172EX" boot.entry 2>&1)"
f172_c_rc=$?
if [ "$f172_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_set_emit_with exited $f172_c_rc: $F172_C_OUT"
  exit 630
fi
if ! printf '%s\n' "$F172_C_OUT" | awk 'NR==1{if($0!="listen|f172|set|::g172|V172")exit 1} NR==2{if($0!="listen|f172|emit|E172|with|k172|v172")exit 1} NR==3{if($0!="P0_SEM_F172_OK")exit 1} END{if(NR!=3)exit 1}'; then
  echo "ERROR: expected F172 stdout (3 lines), got: $F172_C_OUT"
  exit 630
fi
F172_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F172EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f172_py_rc=$?
if [ "$f172_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_set_emit_with exited $f172_py_rc: $F172_PY_OUT"
  exit 631
fi
if [ "$F172_C_OUT" != "$F172_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_set_emit_with" >&2
  echo "C:  $F172_C_OUT" >&2
  echo "Py: $F172_PY_OUT" >&2
  exit 632
fi

echo "[gate] F173: C vs Python — parse_tokens listen { set … ; emit … with multi-pair }"
F173EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_set_emit_multi_with.azl"
F173_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F173EX" boot.entry 2>&1)"
f173_c_rc=$?
if [ "$f173_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_set_emit_multi_with exited $f173_c_rc: $F173_C_OUT"
  exit 768
fi
if ! printf '%s\n' "$F173_C_OUT" | awk 'NR==1{if($0!="listen|f173|set|::g173|V173")exit 1} NR==2{if($0!="listen|f173|emit|E173|with|a173|b173|c173|d173")exit 1} NR==3{if($0!="P0_SEM_F173_OK")exit 1} END{if(NR!=3)exit 1}'; then
  echo "ERROR: expected F173 stdout (3 lines), got: $F173_C_OUT"
  exit 768
fi
F173_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F173EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f173_py_rc=$?
if [ "$f173_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_set_emit_multi_with exited $f173_py_rc: $F173_PY_OUT"
  exit 769
fi
if [ "$F173_C_OUT" != "$F173_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_set_emit_multi_with" >&2
  echo "C:  $F173_C_OUT" >&2
  echo "Py: $F173_PY_OUT" >&2
  exit 770
fi

echo "[gate] F174: C vs Python — parse_tokens listen { say … ; set … ; emit … }"
F174EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_say_set_emit.azl"
F174_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F174EX" boot.entry 2>&1)"
f174_c_rc=$?
if [ "$f174_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_say_set_emit exited $f174_c_rc: $F174_C_OUT"
  exit 771
fi
if ! printf '%s\n' "$F174_C_OUT" | awk 'NR==1{if($0!="listen|f174|say|F174_A")exit 1} NR==2{if($0!="listen|f174|set|::g174|V174")exit 1} NR==3{if($0!="listen|f174|emit|E174")exit 1} NR==4{if($0!="P0_SEM_F174_OK")exit 1} END{if(NR!=4)exit 1}'; then
  echo "ERROR: expected F174 stdout (4 lines), got: $F174_C_OUT"
  exit 771
fi
F174_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F174EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f174_py_rc=$?
if [ "$f174_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_say_set_emit exited $f174_py_rc: $F174_PY_OUT"
  exit 772
fi
if [ "$F174_C_OUT" != "$F174_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_say_set_emit" >&2
  echo "C:  $F174_C_OUT" >&2
  echo "Py: $F174_PY_OUT" >&2
  exit 773
fi

echo "[gate] F175: C vs Python — parse_tokens listen { emit … ; set … }"
F175EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_emit_then_set.azl"
F175_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F175EX" boot.entry 2>&1)"
f175_c_rc=$?
if [ "$f175_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_emit_then_set exited $f175_c_rc: $F175_C_OUT"
  exit 774
fi
if ! printf '%s\n' "$F175_C_OUT" | awk 'NR==1{if($0!="listen|f175|emit|E175")exit 1} NR==2{if($0!="listen|f175|set|::g175|V175")exit 1} NR==3{if($0!="P0_SEM_F175_OK")exit 1} END{if(NR!=3)exit 1}'; then
  echo "ERROR: expected F175 stdout (3 lines), got: $F175_C_OUT"
  exit 774
fi
F175_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F175EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f175_py_rc=$?
if [ "$f175_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_emit_then_set exited $f175_py_rc: $F175_PY_OUT"
  exit 775
fi
if [ "$F175_C_OUT" != "$F175_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_emit_then_set" >&2
  echo "C:  $F175_C_OUT" >&2
  echo "Py: $F175_PY_OUT" >&2
  exit 776
fi

echo "[gate] F176: C vs Python — parse_tokens listen { if ( true ) { say … } }"
F176EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_if_say.azl"
F176_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F176EX" boot.entry 2>&1)"
f176_c_rc=$?
if [ "$f176_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_if_say exited $f176_c_rc: $F176_C_OUT"
  exit 783
fi
if ! printf '%s\n' "$F176_C_OUT" | awk 'NR==1{if($0!="listen|f176|say|F176_INNER")exit 1} NR==2{if($0!="P0_SEM_F176_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F176 stdout (2 lines), got: $F176_C_OUT"
  exit 783
fi
F176_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F176EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f176_py_rc=$?
if [ "$f176_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_if_say exited $f176_py_rc: $F176_PY_OUT"
  exit 784
fi
if [ "$F176_C_OUT" != "$F176_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_if_say" >&2
  echo "C:  $F176_C_OUT" >&2
  echo "Py: $F176_PY_OUT" >&2
  exit 785
fi

echo "[gate] F177: C vs Python — parse_tokens listen { return … }"
F177EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_return.azl"
F177_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F177EX" boot.entry 2>&1)"
f177_c_rc=$?
if [ "$f177_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_return exited $f177_c_rc: $F177_C_OUT"
  exit 786
fi
if ! printf '%s\n' "$F177_C_OUT" | awk 'NR==1{if($0!="listen|f177|return|F177_MARK")exit 1} NR==2{if($0!="P0_SEM_F177_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F177 stdout (2 lines), got: $F177_C_OUT"
  exit 786
fi
F177_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F177EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f177_py_rc=$?
if [ "$f177_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_return exited $f177_py_rc: $F177_PY_OUT"
  exit 787
fi
if [ "$F177_C_OUT" != "$F177_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_return" >&2
  echo "C:  $F177_C_OUT" >&2
  echo "Py: $F177_PY_OUT" >&2
  exit 788
fi

echo "[gate] F178: C vs Python — parse_tokens memory say … + listen { say … }"
F178EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_memory_then_listen.azl"
F178_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F178EX" boot.entry 2>&1)"
f178_c_rc=$?
if [ "$f178_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_memory_then_listen exited $f178_c_rc: $F178_C_OUT"
  exit 789
fi
if ! printf '%s\n' "$F178_C_OUT" | awk 'NR==1{if($0!="memory|say|F178_MEM")exit 1} NR==2{if($0!="listen|f178|say|F178_INNER")exit 1} NR==3{if($0!="P0_SEM_F178_OK")exit 1} END{if(NR!=3)exit 1}'; then
  echo "ERROR: expected F178 stdout (3 lines), got: $F178_C_OUT"
  exit 789
fi
F178_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F178EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f178_py_rc=$?
if [ "$f178_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_memory_then_listen exited $f178_py_rc: $F178_PY_OUT"
  exit 790
fi
if [ "$F178_C_OUT" != "$F178_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_memory_then_listen" >&2
  echo "C:  $F178_C_OUT" >&2
  echo "Py: $F178_PY_OUT" >&2
  exit 791
fi

echo "[gate] F181: C vs Python — execute_ast memory|listen|…|return (+ bare return) + memory|emit ×2"
F181EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_memory_listen_return_stack.azl"
F181_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F181EX" boot.entry 2>&1)"
f181_c_rc=$?
if [ "$f181_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_memory_listen_return_stack exited $f181_c_rc: $F181_C_OUT"
  exit 792
fi
if ! printf '%s\n' "$F181_C_OUT" | awk 'NR==1{if($0!="F181_TREE")exit 1} NR==2{if($0!="F181_TOP")exit 1} NR==3{if($0!="F181_WITH_PAY")exit 1} NR==4{if($0!="F181_MEM")exit 1} NR==5{if($0!="f181_mod_tag")exit 1} NR==6{if($0!="EX181_POST")exit 1} NR==7{if($0!="Said: F181_MEM")exit 1} NR==8{if($0!="EC181_INNER")exit 1} NR==9{if($0!="Said: F181_MEM")exit 1} NR==10{if($0!="P0_SEM_F181_OK")exit 1} END{if(NR!=10)exit 1}'; then
  echo "ERROR: expected F181 memory|listen|return stack stdout (10 lines), got: $F181_C_OUT"
  exit 792
fi
F181_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F181EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f181_py_rc=$?
if [ "$f181_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_memory_listen_return_stack exited $f181_py_rc: $F181_PY_OUT"
  exit 793
fi
if [ "$F181_C_OUT" != "$F181_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_memory_listen_return_stack" >&2
  echo "C:  $F181_C_OUT" >&2
  echo "Py: $F181_PY_OUT" >&2
  exit 794
fi

echo "[gate] F182: C vs Python — parse_tokens listen { listen { say … } ; say … }"
F182EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_nested_say.azl"
F182_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F182EX" boot.entry 2>&1)"
f182_c_rc=$?
if [ "$f182_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_nested_say exited $f182_c_rc: $F182_C_OUT"
  exit 795
fi
if ! printf '%s\n' "$F182_C_OUT" | awk 'NR==1{if($0!="listen|f182_in|say|F182_NEST")exit 1} NR==2{if($0!="listen|f182_out|say|F182_OUT")exit 1} NR==3{if($0!="P0_SEM_F182_OK")exit 1} END{if(NR!=3)exit 1}'; then
  echo "ERROR: expected F182 stdout (3 lines), got: $F182_C_OUT"
  exit 795
fi
F182_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F182EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f182_py_rc=$?
if [ "$f182_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_nested_say exited $f182_py_rc: $F182_PY_OUT"
  exit 796
fi
if [ "$F182_C_OUT" != "$F182_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_nested_say" >&2
  echo "C:  $F182_C_OUT" >&2
  echo "Py: $F182_PY_OUT" >&2
  exit 797
fi

echo "[gate] F183: C vs Python — parse_tokens listen { let … ; say … }"
F183EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_let_say.azl"
F183_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F183EX" boot.entry 2>&1)"
f183_c_rc=$?
if [ "$f183_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_let_say exited $f183_c_rc: $F183_C_OUT"
  exit 798
fi
if ! printf '%s\n' "$F183_C_OUT" | awk 'NR==1{if($0!="listen|f183|let|::lv183|VAL183")exit 1} NR==2{if($0!="listen|f183|say|F183_SAY")exit 1} NR==3{if($0!="P0_SEM_F183_OK")exit 1} END{if(NR!=3)exit 1}'; then
  echo "ERROR: expected F183 stdout (3 lines), got: $F183_C_OUT"
  exit 798
fi
F183_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F183EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f183_py_rc=$?
if [ "$f183_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_let_say exited $f183_py_rc: $F183_PY_OUT"
  exit 799
fi
if [ "$F183_C_OUT" != "$F183_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_let_say" >&2
  echo "C:  $F183_C_OUT" >&2
  echo "Py: $F183_PY_OUT" >&2
  exit 800
fi

echo "[gate] F184: C vs Python — parse_tokens listen { name ( ) } → listen|…|call|…"
F184EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_call.azl"
F184_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F184EX" boot.entry 2>&1)"
f184_c_rc=$?
if [ "$f184_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_call exited $f184_c_rc: $F184_C_OUT"
  exit 801
fi
if ! printf '%s\n' "$F184_C_OUT" | awk 'NR==1{if($0!="listen|f184|call|f184_fn")exit 1} NR==2{if($0!="P0_SEM_F184_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F184 stdout (2 lines), got: $F184_C_OUT"
  exit 801
fi
F184_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F184EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f184_py_rc=$?
if [ "$f184_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_call exited $f184_py_rc: $F184_PY_OUT"
  exit 802
fi
if [ "$F184_C_OUT" != "$F184_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_call" >&2
  echo "C:  $F184_C_OUT" >&2
  echo "Py: $F184_PY_OUT" >&2
  exit 803
fi

echo "[gate] F185: C vs Python — execute_ast listen|…|call|fn stub + emit drain"
F185EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_listen_call_stub.azl"
F185_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F185EX" boot.entry 2>&1)"
f185_c_rc=$?
if [ "$f185_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_listen_call_stub exited $f185_c_rc: $F185_C_OUT"
  exit 804
fi
if ! printf '%s\n' "$F185_C_OUT" | awk 'NR==1{if($0!="F185_TREE")exit 1} NR==2{if($0!="F185_CALL_CB")exit 1} NR==3{if($0!="F185_TAIL")exit 1} NR==4{if($0!="EX185_POST")exit 1} NR==5{if($0!="Said: F185_TAIL")exit 1} NR==6{if($0!="EC185_INNER")exit 1} NR==7{if($0!="Said: F185_TAIL")exit 1} NR==8{if($0!="P0_SEM_F185_OK")exit 1} END{if(NR!=8)exit 1}'; then
  echo "ERROR: expected F185 execute_ast listen|call stub stdout (8 lines), got: $F185_C_OUT"
  exit 804
fi
F185_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F185EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f185_py_rc=$?
if [ "$f185_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_listen_call_stub exited $f185_py_rc: $F185_PY_OUT"
  exit 805
fi
if [ "$F185_C_OUT" != "$F185_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_listen_call_stub" >&2
  echo "C:  $F185_C_OUT" >&2
  echo "Py: $F185_PY_OUT" >&2
  exit 806
fi

echo "[gate] F186: C vs Python — parse_tokens listen { name ( '…' ) } → listen|…|call|…|payload"
F186EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_call_string_arg.azl"
F186_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F186EX" boot.entry 2>&1)"
f186_c_rc=$?
if [ "$f186_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_call_string_arg exited $f186_c_rc: $F186_C_OUT"
  exit 807
fi
if ! printf '%s\n' "$F186_C_OUT" | awk 'NR==1{if($0!="listen|f186|call|f186_fn|F186_MARK")exit 1} NR==2{if($0!="P0_SEM_F186_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F186 stdout (2 lines), got: $F186_C_OUT"
  exit 807
fi
F186_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F186EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f186_py_rc=$?
if [ "$f186_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_call_string_arg exited $f186_py_rc: $F186_PY_OUT"
  exit 808
fi
if [ "$F186_C_OUT" != "$F186_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_call_string_arg" >&2
  echo "C:  $F186_C_OUT" >&2
  echo "Py: $F186_PY_OUT" >&2
  exit 809
fi

echo "[gate] F187: C vs Python — execute_ast listen|…|call|fn|arg stub + emit drain"
F187EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_listen_call_arg_stub.azl"
F187_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F187EX" boot.entry 2>&1)"
f187_c_rc=$?
if [ "$f187_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_listen_call_arg_stub exited $f187_c_rc: $F187_C_OUT"
  exit 810
fi
if ! printf '%s\n' "$F187_C_OUT" | awk 'NR==1{if($0!="F187_TREE")exit 1} NR==2{if($0!="F187_CB")exit 1} NR==3{if($0!="F187_ARG")exit 1} NR==4{if($0!="F187_TAIL")exit 1} NR==5{if($0!="EX187_POST")exit 1} NR==6{if($0!="Said: F187_TAIL")exit 1} NR==7{if($0!="EC187_INNER")exit 1} NR==8{if($0!="Said: F187_TAIL")exit 1} NR==9{if($0!="P0_SEM_F187_OK")exit 1} END{if(NR!=9)exit 1}'; then
  echo "ERROR: expected F187 execute_ast listen|call|arg stub stdout (9 lines), got: $F187_C_OUT"
  exit 810
fi
F187_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F187EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f187_py_rc=$?
if [ "$f187_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_listen_call_arg_stub exited $f187_py_rc: $F187_PY_OUT"
  exit 811
fi
if [ "$F187_C_OUT" != "$F187_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_listen_call_arg_stub" >&2
  echo "C:  $F187_C_OUT" >&2
  echo "Py: $F187_PY_OUT" >&2
  exit 812
fi

echo "[gate] F188: C vs Python — parse_tokens top-level name ( '…' ) → call|…|payload"
F188EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_top_call_string_arg.azl"
F188_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F188EX" boot.entry 2>&1)"
f188_c_rc=$?
if [ "$f188_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_top_call_string_arg exited $f188_c_rc: $F188_C_OUT"
  exit 813
fi
if ! printf '%s\n' "$F188_C_OUT" | awk 'NR==1{if($0!="call|f188_fn|F188_MARK")exit 1} NR==2{if($0!="P0_SEM_F188_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F188 stdout (2 lines), got: $F188_C_OUT"
  exit 813
fi
F188_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F188EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f188_py_rc=$?
if [ "$f188_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_top_call_string_arg exited $f188_py_rc: $F188_PY_OUT"
  exit 814
fi
if [ "$F188_C_OUT" != "$F188_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_top_call_string_arg" >&2
  echo "C:  $F188_C_OUT" >&2
  echo "Py: $F188_PY_OUT" >&2
  exit 815
fi

echo "[gate] F189: C vs Python — execute_ast top-level call|fn|arg + emit drain"
F189EX="${ROOT_DIR}/azl/tests/p0_semantic_execute_ast_top_call_arg_stub.azl"
F189_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F189EX" boot.entry 2>&1)"
f189_c_rc=$?
if [ "$f189_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_execute_ast_top_call_arg_stub exited $f189_c_rc: $F189_C_OUT"
  exit 816
fi
if ! printf '%s\n' "$F189_C_OUT" | awk 'NR==1{if($0!="F189_TREE")exit 1} NR==2{if($0!="F189_CB")exit 1} NR==3{if($0!="F189_ARG")exit 1} NR==4{if($0!="F189_TAIL")exit 1} NR==5{if($0!="EX189_POST")exit 1} NR==6{if($0!="Said: F189_TAIL")exit 1} NR==7{if($0!="EC189_INNER")exit 1} NR==8{if($0!="Said: F189_TAIL")exit 1} NR==9{if($0!="P0_SEM_F189_OK")exit 1} END{if(NR!=9)exit 1}'; then
  echo "ERROR: expected F189 execute_ast top-level call|…|arg stdout (9 lines), got: $F189_C_OUT"
  exit 816
fi
F189_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F189EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f189_py_rc=$?
if [ "$f189_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_execute_ast_top_call_arg_stub exited $f189_py_rc: $F189_PY_OUT"
  exit 817
fi
if [ "$F189_C_OUT" != "$F189_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_execute_ast_top_call_arg_stub" >&2
  echo "C:  $F189_C_OUT" >&2
  echo "Py: $F189_PY_OUT" >&2
  exit 818
fi

echo "[gate] F190: C vs Python — parse_tokens listen { name ( ::id ) } → listen|…|call|…|::id"
F190EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_call_ident_arg.azl"
F190_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F190EX" boot.entry 2>&1)"
f190_c_rc=$?
if [ "$f190_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_call_ident_arg exited $f190_c_rc: $F190_C_OUT"
  exit 819
fi
if ! printf '%s\n' "$F190_C_OUT" | awk 'NR==1{if($0!="listen|f190|call|f190_fn|::F190_ID")exit 1} NR==2{if($0!="P0_SEM_F190_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F190 stdout (2 lines), got: $F190_C_OUT"
  exit 819
fi
F190_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F190EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f190_py_rc=$?
if [ "$f190_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_call_ident_arg exited $f190_py_rc: $F190_PY_OUT"
  exit 820
fi
if [ "$F190_C_OUT" != "$F190_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_call_ident_arg" >&2
  echo "C:  $F190_C_OUT" >&2
  echo "Py: $F190_PY_OUT" >&2
  exit 821
fi

echo "[gate] F191: C vs Python — parse_tokens top-level name ( ::id ) → call|…|::id"
F191EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_top_call_ident_arg.azl"
F191_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F191EX" boot.entry 2>&1)"
f191_c_rc=$?
if [ "$f191_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_top_call_ident_arg exited $f191_c_rc: $F191_C_OUT"
  exit 822
fi
if ! printf '%s\n' "$F191_C_OUT" | awk 'NR==1{if($0!="call|f191_fn|::F191_ID")exit 1} NR==2{if($0!="P0_SEM_F191_OK")exit 1} END{if(NR!=2)exit 1}'; then
  echo "ERROR: expected F191 stdout (2 lines), got: $F191_C_OUT"
  exit 822
fi
F191_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F191EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f191_py_rc=$?
if [ "$f191_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_top_call_ident_arg exited $f191_py_rc: $F191_PY_OUT"
  exit 823
fi
if [ "$F191_C_OUT" != "$F191_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_top_call_ident_arg" >&2
  echo "C:  $F191_C_OUT" >&2
  echo "Py: $F191_PY_OUT" >&2
  exit 824
fi

echo "[gate] F179: C vs Python — parse_tokens listen { set … ; emit \"…\" with { k: v } }"
F179EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_set_emit_quoted_event.azl"
F179_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F179EX" boot.entry 2>&1)"
f179_c_rc=$?
if [ "$f179_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_set_emit_quoted_event exited $f179_c_rc: $F179_C_OUT"
  exit 777
fi
if ! printf '%s\n' "$F179_C_OUT" | awk 'NR==1{if($0!="listen|f179|set|::g179|V179")exit 1} NR==2{if($0!="listen|f179|emit|E179Q|with|k179|v179")exit 1} NR==3{if($0!="P0_SEM_F179_OK")exit 1} END{if(NR!=3)exit 1}'; then
  echo "ERROR: expected F179 stdout (3 lines), got: $F179_C_OUT"
  exit 777
fi
F179_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F179EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f179_py_rc=$?
if [ "$f179_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_set_emit_quoted_event exited $f179_py_rc: $F179_PY_OUT"
  exit 778
fi
if [ "$F179_C_OUT" != "$F179_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_set_emit_quoted_event" >&2
  echo "C:  $F179_C_OUT" >&2
  echo "Py: $F179_PY_OUT" >&2
  exit 779
fi

echo "[gate] F180: C vs Python — parse_tokens listen { set … ; emit … with { k: ::global } }"
F180EX="${ROOT_DIR}/azl/tests/p0_semantic_parse_tokens_listen_set_emit_with_global_rhs.azl"
F180_C_OUT="$(env -u AZL_USE_VM "$MINI_BIN" "$F180EX" boot.entry 2>&1)"
f180_c_rc=$?
if [ "$f180_c_rc" != 0 ]; then
  echo "ERROR: azl-interpreter-minimal p0_semantic_parse_tokens_listen_set_emit_with_global_rhs exited $f180_c_rc: $F180_C_OUT"
  exit 780
fi
if ! printf '%s\n' "$F180_C_OUT" | awk 'NR==1{if($0!="listen|f180|set|::g180|V180")exit 1} NR==2{if($0!="listen|f180|emit|E180|with|k180|::gv180")exit 1} NR==3{if($0!="P0_SEM_F180_OK")exit 1} END{if(NR!=3)exit 1}'; then
  echo "ERROR: expected F180 stdout (3 lines), got: $F180_C_OUT"
  exit 780
fi
F180_PY_OUT="$(unset AZL_INTERPRETER_DAEMON; env -u AZL_USE_VM AZL_COMBINED_PATH="$F180EX" AZL_ENTRY='boot.entry' python3 "${ROOT_DIR}/tools/azl_runtime_spine_host.py" 2>&1)"
f180_py_rc=$?
if [ "$f180_py_rc" != 0 ]; then
  echo "ERROR: Python spine host p0_semantic_parse_tokens_listen_set_emit_with_global_rhs exited $f180_py_rc: $F180_PY_OUT"
  exit 781
fi
if [ "$F180_C_OUT" != "$F180_PY_OUT" ]; then
  echo "ERROR: C vs Python output mismatch on p0_semantic_parse_tokens_listen_set_emit_with_global_rhs" >&2
  echo "C:  $F180_C_OUT" >&2
  echo "Py: $F180_PY_OUT" >&2
  exit 782
fi

echo "[gate] G: runtime spine resolver + semantic host error surface"
chmod +x scripts/azl_resolve_native_runtime_cmd.sh scripts/azl_azl_interpreter_runtime.sh scripts/verify_runtime_spine_contract.sh 2>/dev/null || true
bash scripts/verify_runtime_spine_contract.sh

echo "[gate] G2: semantic spec line = azl_interpreter.azl path; spine exec owner = Python minimal_runtime (not C minimal)"
chmod +x scripts/verify_semantic_spine_owner_contract.sh 2>/dev/null || true
bash scripts/verify_semantic_spine_owner_contract.sh

echo "[gate] H: P0 progress — tokenizer + brace balance on azl_interpreter.azl"
chmod +x scripts/verify_p0_interpreter_tokenizer_boundary.sh 2>/dev/null || true
bash scripts/verify_p0_interpreter_tokenizer_boundary.sh

echo "[gate] E: legacy deploy profile blocked by default"
if rg -q 'AZL_ENABLE_LEGACY_HOST="\$\{AZL_ENABLE_LEGACY_HOST:-1\}"' scripts/*.sh; then
  echo "ERROR: found script defaulting AZL_ENABLE_LEGACY_HOST to 1"
  exit 31
fi

echo "[gate] all gates passed"
