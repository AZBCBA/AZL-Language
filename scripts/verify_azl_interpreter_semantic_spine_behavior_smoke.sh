#!/usr/bin/env bash
# Tier B P0.1 — real interpreter behavior path on the semantic spine (Python minimal_runtime).
# Concatenates stub ::azl.security + behavior-entry harness + azl/runtime/interpreter/azl_interpreter.azl,
# runs tools/azl_runtime_spine_host.py with AZL_ENTRY=azl.spine.behavior.entry, asserts the full in-file chain:
# interpret → tokenize → parse → execute (say line) → execute_complete listener (Interpretation complete:).
# Harness: smoke/smoke2 same code → cache hits; third–fifth multi-line embedded say depth; smoke6 literal AZL_S6_ONLY;
# smoke7 repeats smoke6 code → second pair of (cache hit) lines on that snippet; smoke8 new literal AZL_S8_MARK;
# smoke9 set ::… then say — exercises execute_ast set row on the real file path;
# smoke10 bare emit — ::execute_emit / ::emit_event_resolved (spine surfaces result as Interpretation complete: Emitted: …).
# smoke11 emit with payload — payload branch + host prints AZL_EMIT_WITH_PAYLOAD (matches in-file marker intent).
# Complements verify_azl_interpreter_semantic_spine_smoke.sh (init-only).
#
# Prefix ERROR[AZL_INTERPRETER_SEMANTIC_SPINE_BEHAVIOR_SMOKE]: on stderr for script-owned failures.
# See docs/ERROR_SYSTEM.md (exits 548–562, 611, 627–629).
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
# Proof-only: mirror ::emit_event_resolved payload marker on stdout without mutating F96+ gate fixtures.
export AZL_SPINE_BEHAVIOR_SMOKE_PAYLOAD_MARK=1

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
if ! awk '/Interpretation complete:/{n++} END{exit !(n>=11)}' "$out"; then
  err "stdout expected >=11 \"Interpretation complete:\" lines (harness eleven emit interpret)"
  cat "$out" >&2 || true
  exit 556
fi
if ! awk '/\(cache hit\)/{n++} END{exit !(n>=4)}' "$out"; then
  err "stdout expected >=4 in-file \"(cache hit)\" lines (smoke2 + smoke7: tokenize + parse cache per duplicate code)"
  cat "$out" >&2 || true
  exit 557
fi
if ! rg -q 'AZL_SPINE_DEPTH_A' "$out" || ! rg -q 'AZL_SPINE_DEPTH_B' "$out"; then
  err "stdout missing third-interpret two-line say markers AZL_SPINE_DEPTH_A / AZL_SPINE_DEPTH_B"
  cat "$out" >&2 || true
  exit 558
fi
if ! rg -q 'AZL_SPINE_TRIPLE_1' "$out" || ! rg -q 'AZL_SPINE_TRIPLE_2' "$out" || ! rg -q 'AZL_SPINE_TRIPLE_3' "$out"; then
  err "stdout missing fourth-interpret three-line say markers AZL_SPINE_TRIPLE_1 / _2 / _3"
  cat "$out" >&2 || true
  exit 559
fi
if ! rg -q 'Q5a' "$out" || ! rg -q 'Q5b' "$out" || ! rg -q 'Q5c' "$out" || ! rg -q 'Q5d' "$out"; then
  err "stdout missing fifth-interpret four-line say markers Q5a / Q5b / Q5c / Q5d (compact: spine ::ast.nodes Var.v 255-byte budget)"
  cat "$out" >&2 || true
  exit 560
fi
if ! awk '/AZL_S6_ONLY/{n++} END{exit !(n>=2)}' "$out"; then
  err "stdout expected >=2 lines containing AZL_S6_ONLY (sixth + seventh interpret same code)"
  cat "$out" >&2 || true
  exit 561
fi
if ! rg -q 'AZL_S8_MARK' "$out"; then
  err "stdout missing eighth-interpret literal say marker AZL_S8_MARK"
  cat "$out" >&2 || true
  exit 562
fi
if ! rg -q 'AZL_SPINE_P9_SET_LINE' "$out"; then
  err "stdout missing ninth-interpret set+say marker AZL_SPINE_P9_SET_LINE"
  cat "$out" >&2 || true
  exit 611
fi
if ! rg -q 'Emitted: AZL_SPINE_P10_USER_EMIT' "$out"; then
  err "stdout missing tenth-interpret user emit result (Interpretation complete: Emitted: AZL_SPINE_P10_USER_EMIT)"
  cat "$out" >&2 || true
  exit 627
fi
if ! rg -q 'Emitted: AZL_SPINE_P11' "$out"; then
  err "stdout missing eleventh-interpret emit-with-payload result (Emitted: AZL_SPINE_P11)"
  cat "$out" >&2 || true
  exit 628
fi
if ! rg -q 'AZL_EMIT_WITH_PAYLOAD' "$out"; then
  err "stdout missing in-file payload emit marker AZL_EMIT_WITH_PAYLOAD (::emit_event_resolved)"
  cat "$out" >&2 || true
  exit 629
fi

echo "azl-interpreter-semantic-spine-behavior-smoke-ok"
exit 0
