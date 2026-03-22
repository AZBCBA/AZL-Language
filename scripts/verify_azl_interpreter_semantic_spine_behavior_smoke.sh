#!/usr/bin/env bash
# Tier B P0.1 — real interpreter behavior path on the semantic spine (Python minimal_runtime).
# Concatenates stub ::azl.security + behavior-entry harness + azl/runtime/interpreter/azl_interpreter.azl,
# runs tools/azl_runtime_spine_host.py with AZL_ENTRY=azl.spine.behavior.entry, asserts the full in-file chain:
# interpret → tokenize → parse → execute (say line) → execute_complete listener (Interpretation complete:).
# Harness: two interpret emits (same code) so the second pass hits in-file tok_cache + ast_cache; third emit
# runs two-line embedded code (two say statements) to exercise more of azl_interpreter.azl tokenize/parse/execute.
# Complements verify_azl_interpreter_semantic_spine_smoke.sh (init-only).
#
# Prefix ERROR[AZL_INTERPRETER_SEMANTIC_SPINE_BEHAVIOR_SMOKE]: on stderr for script-owned failures.
# See docs/ERROR_SYSTEM.md (exits 548–558).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

err() {
  echo "ERROR[AZL_INTERPRETER_SEMANTIC_SPINE_BEHAVIOR_SMOKE]: $*" >&2
}

if ! command -v python3 >/dev/null 2>&1; then
  err "python3 required"
  exit 92
fi
if ! command -v rg >/dev/null 2>&1; then
  err "ripgrep (rg) required"
  exit 40
fi

STUB="${ROOT_DIR}/azl/tests/stubs/azl_security_for_interpreter_spine.azl"
HARNESS="${ROOT_DIR}/azl/tests/harness/azl_interpreter_semantic_spine_behavior_entry.azl"
SRC="${ROOT_DIR}/azl/runtime/interpreter/azl_interpreter.azl"
HOST_PY="${ROOT_DIR}/tools/azl_runtime_spine_host.py"

for f in "$STUB" "$HARNESS" "$SRC" "$HOST_PY"; do
  if [ ! -f "$f" ]; then
    err "missing required file: $f"
    exit 548
  fi
done

COMBINED=""
out=""
errf=""
cleanup() {
  rm -f "${COMBINED:-}" "${out:-}" "${errf:-}"
}
trap cleanup EXIT

COMBINED="$(mktemp "${TMPDIR:-/tmp}/azl_interpreter_spine_behavior_smoke.XXXXXX.azl")"
if ! cat "$STUB" "$HARNESS" "$SRC" >"$COMBINED"; then
  err "failed to write combined AZL"
  exit 549
fi

unset AZL_INTERPRETER_DAEMON || true
export AZL_COMBINED_PATH="$COMBINED"
export AZL_ENTRY=azl.spine.behavior.entry

out="$(mktemp "${TMPDIR:-/tmp}/azl_interpreter_spine_behavior_smoke_out.XXXXXX")"
errf="$(mktemp "${TMPDIR:-/tmp}/azl_interpreter_spine_behavior_smoke_err.XXXXXX")"

set +e
python3 "$HOST_PY" >"$out" 2>"$errf"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  err "spine host exited $rc (expected 0)"
  cat "$errf" >&2 || true
  exit 550
fi
if rg -q 'component not found: ::azl\.security' "$errf"; then
  err "link ::azl.security still unresolved (stderr)"
  cat "$errf" >&2 || true
  exit 551
fi
if ! rg -q 'Pure AZL Interpreter Initialized' "$out"; then
  err "stdout missing interpreter init marker"
  cat "$out" >&2 || true
  exit 552
fi
if ! rg -q 'AZL_SPINE_BEHAVIOR_ENTRY_POST_EMIT' "$out"; then
  err "stdout missing harness POST_EMIT marker (interpret pipeline did not complete)"
  cat "$out" >&2 || true
  exit 553
fi
if ! rg -q 'Execution complete' "$out"; then
  err "stdout missing execute listener completion (in-file say \"⚡ Execution complete\" after ::execute_ast)"
  cat "$out" >&2 || true
  exit 554
fi
if ! rg -q 'Interpretation complete:' "$out"; then
  err "stdout missing execute_complete listener (in-file \"Interpretation complete:\" after nested event chain)"
  cat "$out" >&2 || true
  exit 555
fi
if ! awk '/Interpretation complete:/{n++} END{exit !(n>=3)}' "$out"; then
  err "stdout expected >=3 \"Interpretation complete:\" lines (harness three emit interpret)"
  cat "$out" >&2 || true
  exit 556
fi
if ! awk '/\(cache hit\)/{n++} END{exit !(n>=2)}' "$out"; then
  err "stdout expected >=2 in-file \"(cache hit)\" lines (tokenize + parse cache on second interpret)"
  cat "$out" >&2 || true
  exit 557
fi
if ! rg -q 'AZL_SPINE_DEPTH_A' "$out" || ! rg -q 'AZL_SPINE_DEPTH_B' "$out"; then
  err "stdout missing third-interpret two-line say markers AZL_SPINE_DEPTH_A / AZL_SPINE_DEPTH_B"
  cat "$out" >&2 || true
  exit 558
fi

echo "azl-interpreter-semantic-spine-behavior-smoke-ok"
exit 0
