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

echo "[gate] G: runtime spine resolver + semantic host error surface"
chmod +x scripts/azl_resolve_native_runtime_cmd.sh scripts/azl_azl_interpreter_runtime.sh scripts/verify_runtime_spine_contract.sh 2>/dev/null || true
bash scripts/verify_runtime_spine_contract.sh

echo "[gate] G2: semantic spine execution owner = Python minimal_runtime (not C minimal)"
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
