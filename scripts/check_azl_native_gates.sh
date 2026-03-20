#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

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

echo "[gate] G: runtime spine resolver + semantic host error surface"
chmod +x scripts/azl_resolve_native_runtime_cmd.sh scripts/azl_azl_interpreter_runtime.sh scripts/verify_runtime_spine_contract.sh 2>/dev/null || true
bash scripts/verify_runtime_spine_contract.sh

echo "[gate] H: P0 progress — tokenizer + brace balance on azl_interpreter.azl"
chmod +x scripts/verify_p0_interpreter_tokenizer_boundary.sh 2>/dev/null || true
bash scripts/verify_p0_interpreter_tokenizer_boundary.sh

echo "[gate] E: legacy deploy profile blocked by default"
if rg -q 'AZL_ENABLE_LEGACY_HOST="\$\{AZL_ENABLE_LEGACY_HOST:-1\}"' scripts/*.sh; then
  echo "ERROR: found script defaulting AZL_ENABLE_LEGACY_HOST to 1"
  exit 31
fi

echo "[gate] all gates passed"
