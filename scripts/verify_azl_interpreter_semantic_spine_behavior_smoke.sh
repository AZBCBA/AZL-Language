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
# smoke12 on/call — top-level user function + call (registered:* / called:* via execute_ast fn|/call| spine encoding).
# smoke14 if ( true ) { say … } — ::parse_if_statement / ::execute_if_statement; spine ::parse_tokens emits if| row; host execute_ast branches.
# smoke15 if ( false ) { … } otherwise { say … } — alternate branch; then-body marker must not appear (same if| + host branch).
# smoke16 if ( false ) { … } otherwise { two says } — ordered multi-statement otherwise; P16_BAD must not appear; P16_A before P16_B on stdout.
# smoke17 set ::azl_spine_p17 = true then if ( ::azl_spine_p17 ) { … } otherwise { … } — evaluated condition (if| + host execute_ast); P17_IF only; P17_BAD must not appear.
# smoke18 set ::azl_spine_p18 = false then if ( ::azl_spine_p18 ) { … } otherwise { … } — evaluated falsey global; P18_ELSE only; P18_BAD must not appear.
# smoke19 evaluated truthy then-branch: two say lines in then-block; P19_A before P19_B; P19_BAD must not appear.
# smoke20 evaluated falsey otherwise-branch: two say lines in otherwise-block; P20_A before P20_B; P20_BAD must not appear.
# smoke21 if ( ::azl_spine_p21 == 1 ) expression condition; P21_IF only; P21_BAD must not appear.
# smoke22 if ( ::azl_spine_p22 == 2 ) false expression path; P22_ELSE only; P22_BAD must not appear.
# smoke23 if ( ::azl_spine_p23 == 2 ) true expression path, multi-statement then; P23_A before P23_B; P23_BAD must not appear.
# smoke24 if ( ::azl_spine_p24 == 3 ) false expression path, multi-statement otherwise; P24_A before P24_B; P24_BAD must not appear.
# smoke25 two sequential ifs on ::azl_spine_p25; P25_T before P25_F; P25_BAD1 and P25_BAD2 must not appear.
# smoke26 nested if inside then-branch; P26_OUTER before P26_INNER; P26_BAD1 and P26_BAD2 must not appear.
# smoke27 nested if inside otherwise-branch; P27_OUTER before P27_INNER; P27_BAD1 and P27_BAD2 must not appear.
# smoke28 nested expression if in outer then; P28_OUTER before P28_INNER; P28_BAD1 and P28_BAD2 must not appear.
# smoke29 three sequential ifs on ::azl_spine_p29; P29_A before P29_B before P29_C; BAD1–BAD3 must not appear.
# smoke30 multi-statement then on ==1 then second if ==2 false → C; P30_A before P30_B before P30_C; BAD1/BAD2 must not appear.
# smoke31 nested multi-statement then under evaluated outer true; P31_OUTER then P31_A then P31_B; BAD1/BAD2 must not appear.
# smoke32 nested multi-statement otherwise under evaluated outer false; P32_OUTER then P32_A then P32_B; BAD1/BAD2 must not appear.
# smoke33 nested expression under outer ==1; P33_OUTER then P33_INNER; BAD1/BAD2 must not appear.
# smoke34 three-level nesting L1/L2/L3; BAD1/BAD2/BAD3 must not appear.
# smoke35 four alternating if outcomes A/B/C/D; BAD1–BAD4 must not appear.
# smoke36 expression multi-statement then + second if multi-statement otherwise; P36_A..D order; BAD1/BAD2 must not appear.
# smoke37 otherwise body sets global then inner if; P37_OUTER then P37_INNER; BAD1/BAD2 must not appear.
# smoke38 expression branches after set mutation; P38_A then P38_B then P38_C; BAD1–BAD3 must not appear.
# smoke39 double-nested mixed false/then in inner branches; P39_L1 then L2 then L3; BAD1–BAD3 must not appear.
# smoke40 long mix ==5/==6/flag/==5 again; P40_A..D order; BAD1–BAD4 must not appear.
# smoke41 otherwise OUTER then set ::azl_spine_p41_n then inner ==7; P41_OUTER then P41_INNER; BAD1/BAD2 must not appear.
# smoke42 plain branch, expression false → B, set false then multi-statement otherwise C/D; P42_A..D order; BAD1–BAD3 must not appear.
# smoke43 triple sequential == with set mutation between; P43_A then P43_B then P43_C; BAD1–BAD3 must not appear.
# smoke44 outer false L1, nested otherwise L2, inner then L3; P44_L1 then L2 then L3; BAD1–BAD3 must not appear.
# smoke45 outer ==4 then set+inner ==5; P45_OUTER then P45_INNER; BAD1/BAD2 must not appear.
# smoke46 five-way plain true/false alternation; P46_A..E order; BAD1–BAD5 must not appear.
# smoke47 expr true then expr false then plain flag false; P47_A then B then C; BAD1–BAD3 must not appear.
# smoke48 outer ==8 then inner ==9 false → multi-statement otherwise A/B; OUTER then A then B; BAD1/BAD2 must not appear.
# smoke49 outer otherwise OUTER, set true, multi-statement then A/B; OUTER then A then B; BAD1/BAD2 must not appear.
# smoke50 three-level mixed == nesting L1/L2/L3; BAD1–BAD3 must not appear.
# smoke51 A then B then nested otherwise C; BAD1–BAD3 must not appear.
# smoke52 mutation flip A/B then multi-statement then C/D; BAD1–BAD3 must not appear.
# smoke53 outer false A, inner true B, then expr ==2 false → C; BAD1–BAD3 must not appear.
# smoke54 five-step mixed expr/flag/final otherwise E; P54_A..E order; BAD1–BAD5 must not appear.
# smoke55 spine_component_v1: two listeners (say+set+emit chain + downstream listener), init emit, memory re-reads ::azl_spine_p55_flag; ordered AZL_SPINE_P55_* + p55_chain_ok; AZL_SPINE_P55_BAD must not appear on stdout.
# Complements verify_azl_interpreter_semantic_spine_smoke.sh (init-only).
#
# Prefix ERROR[AZL_INTERPRETER_SEMANTIC_SPINE_BEHAVIOR_SMOKE]: on stderr for script-owned failures.
# See docs/ERROR_SYSTEM.md (exits 548–562, 611, 627–752).
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
if ! awk '/Interpretation complete:/{n++} END{exit !(n>=55)}' "$out"; then
  err "stdout expected >=55 \"Interpretation complete:\" lines (harness fifty-five emit interpret)"
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
if ! rg -q 'AZL_S12_FN' "$out"; then
  err "stdout missing twelfth-interpret user function body output AZL_S12_FN (on/call → execute_call say path)"
  cat "$out" >&2 || true
  exit 630
fi
if ! rg -q 'called:a' "$out"; then
  err "stdout missing twelfth-interpret call result (Interpretation complete: called:a)"
  cat "$out" >&2 || true
  exit 631
fi
if ! rg -q 'Let ::azl_spine_p13' "$out" || ! rg -q 'AZL_S13_MARK' "$out"; then
  err "stdout missing thirteenth-interpret top-level let (Let ::azl_spine_p13 … AZL_S13_MARK)"
  cat "$out" >&2 || true
  exit 632
fi
if ! rg -q 'AZL_SPINE_P14_IF' "$out"; then
  err "stdout missing fourteenth-interpret if-body say marker AZL_SPINE_P14_IF (::parse_if_statement / ::execute_if_statement)"
  cat "$out" >&2 || true
  exit 633
fi
if rg -q 'AZL_SPINE_P15_BAD' "$out"; then
  err "stdout must not contain fifteenth-interpret skipped then-body marker AZL_SPINE_P15_BAD"
  cat "$out" >&2 || true
  exit 634
fi
if ! rg -q 'AZL_SPINE_P15_ELSE' "$out"; then
  err "stdout missing fifteenth-interpret otherwise-branch say marker AZL_SPINE_P15_ELSE (if/false + otherwise on real file path)"
  cat "$out" >&2 || true
  exit 635
fi
if rg -q 'AZL_SPINE_P16_BAD' "$out"; then
  err "stdout must not contain sixteenth-interpret skipped then-body marker AZL_SPINE_P16_BAD"
  cat "$out" >&2 || true
  exit 636
fi
if ! rg -q 'AZL_SPINE_P16_A' "$out" || ! rg -q 'AZL_SPINE_P16_B' "$out"; then
  err "stdout missing sixteenth-interpret otherwise markers AZL_SPINE_P16_A and/or AZL_SPINE_P16_B"
  cat "$out" >&2 || true
  exit 637
fi
if ! awk '
  /AZL_SPINE_P16_A/ && !a { a = NR }
  /AZL_SPINE_P16_B/ && !b { b = NR }
  END { exit !(a && b && a < b) }
' "$out"; then
  err "stdout expected AZL_SPINE_P16_A line before AZL_SPINE_P16_B (ordered multi-statement otherwise)"
  cat "$out" >&2 || true
  exit 638
fi
if ! rg -q 'AZL_SPINE_P17_IF' "$out"; then
  err "stdout missing seventeenth-interpret evaluated-condition if marker AZL_SPINE_P17_IF (set ::azl_spine_p17 + if (::azl_spine_p17), not literal in parens)"
  cat "$out" >&2 || true
  exit 639
fi
if rg -q 'AZL_SPINE_P17_BAD' "$out"; then
  err "stdout must not contain seventeenth-interpret otherwise marker AZL_SPINE_P17_BAD (then-branch must run)"
  cat "$out" >&2 || true
  exit 640
fi
if rg -q 'AZL_SPINE_P18_BAD' "$out"; then
  err "stdout must not contain eighteenth-interpret skipped then-body marker AZL_SPINE_P18_BAD (evaluated falsey ::azl_spine_p18)"
  cat "$out" >&2 || true
  exit 641
fi
if ! rg -q 'AZL_SPINE_P18_ELSE' "$out"; then
  err "stdout missing eighteenth-interpret otherwise marker AZL_SPINE_P18_ELSE (set false + if (::azl_spine_p18) on real file path)"
  cat "$out" >&2 || true
  exit 642
fi
if rg -q 'AZL_SPINE_P19_BAD' "$out"; then
  err "stdout must not contain nineteenth-interpret otherwise marker AZL_SPINE_P19_BAD (evaluated truthy then-branch)"
  cat "$out" >&2 || true
  exit 643
fi
if ! rg -q 'AZL_SPINE_P19_A' "$out" || ! rg -q 'AZL_SPINE_P19_B' "$out"; then
  err "stdout missing nineteenth-interpret then-branch markers AZL_SPINE_P19_A and/or AZL_SPINE_P19_B"
  cat "$out" >&2 || true
  exit 644
fi
if ! awk '
  /AZL_SPINE_P19_A/ && !a { a = NR }
  /AZL_SPINE_P19_B/ && !b { b = NR }
  END { exit !(a && b && a < b) }
' "$out"; then
  err "stdout expected AZL_SPINE_P19_A line before AZL_SPINE_P19_B (multi-statement then)"
  cat "$out" >&2 || true
  exit 645
fi
if rg -q 'AZL_SPINE_P20_BAD' "$out"; then
  err "stdout must not contain twentieth-interpret then-branch marker AZL_SPINE_P20_BAD (evaluated falsey otherwise)"
  cat "$out" >&2 || true
  exit 646
fi
if ! rg -q 'AZL_SPINE_P20_A' "$out" || ! rg -q 'AZL_SPINE_P20_B' "$out"; then
  err "stdout missing twentieth-interpret otherwise markers AZL_SPINE_P20_A and/or AZL_SPINE_P20_B"
  cat "$out" >&2 || true
  exit 647
fi
if ! awk '
  /AZL_SPINE_P20_A/ && !a { a = NR }
  /AZL_SPINE_P20_B/ && !b { b = NR }
  END { exit !(a && b && a < b) }
' "$out"; then
  err "stdout expected AZL_SPINE_P20_A line before AZL_SPINE_P20_B (multi-statement otherwise)"
  cat "$out" >&2 || true
  exit 648
fi
if ! rg -q 'AZL_SPINE_P21_IF' "$out"; then
  err "stdout missing twenty-first-interpret expression-condition if marker AZL_SPINE_P21_IF (::azl_spine_p21 == 1)"
  cat "$out" >&2 || true
  exit 649
fi
if rg -q 'AZL_SPINE_P21_BAD' "$out"; then
  err "stdout must not contain twenty-first-interpret otherwise marker AZL_SPINE_P21_BAD"
  cat "$out" >&2 || true
  exit 650
fi
if rg -q 'AZL_SPINE_P22_BAD' "$out"; then
  err "stdout must not contain twenty-second-interpret skipped then-body marker AZL_SPINE_P22_BAD (::azl_spine_p22 == 2 is false)"
  cat "$out" >&2 || true
  exit 651
fi
if ! rg -q 'AZL_SPINE_P22_ELSE' "$out"; then
  err "stdout missing twenty-second-interpret otherwise marker AZL_SPINE_P22_ELSE (expression false path on real file path)"
  cat "$out" >&2 || true
  exit 652
fi
if rg -q 'AZL_SPINE_P23_BAD' "$out"; then
  err "stdout must not contain twenty-third-interpret otherwise marker AZL_SPINE_P23_BAD (expression true multi-statement then)"
  cat "$out" >&2 || true
  exit 653
fi
if ! rg -q 'AZL_SPINE_P23_A' "$out" || ! rg -q 'AZL_SPINE_P23_B' "$out"; then
  err "stdout missing twenty-third-interpret then markers AZL_SPINE_P23_A and/or AZL_SPINE_P23_B"
  cat "$out" >&2 || true
  exit 654
fi
if ! awk '
  /AZL_SPINE_P23_A/ && !a { a = NR }
  /AZL_SPINE_P23_B/ && !b { b = NR }
  END { exit !(a && b && a < b) }
' "$out"; then
  err "stdout expected AZL_SPINE_P23_A line before AZL_SPINE_P23_B (expression true multi-statement then)"
  cat "$out" >&2 || true
  exit 655
fi
if rg -q 'AZL_SPINE_P24_BAD' "$out"; then
  err "stdout must not contain twenty-fourth-interpret then marker AZL_SPINE_P24_BAD (expression false multi-statement otherwise)"
  cat "$out" >&2 || true
  exit 656
fi
if ! rg -q 'AZL_SPINE_P24_A' "$out" || ! rg -q 'AZL_SPINE_P24_B' "$out"; then
  err "stdout missing twenty-fourth-interpret otherwise markers AZL_SPINE_P24_A and/or AZL_SPINE_P24_B"
  cat "$out" >&2 || true
  exit 657
fi
if ! awk '
  /AZL_SPINE_P24_A/ && !a { a = NR }
  /AZL_SPINE_P24_B/ && !b { b = NR }
  END { exit !(a && b && a < b) }
' "$out"; then
  err "stdout expected AZL_SPINE_P24_A line before AZL_SPINE_P24_B (expression false multi-statement otherwise)"
  cat "$out" >&2 || true
  exit 658
fi
if rg -q 'AZL_SPINE_P25_BAD1' "$out"; then
  err "stdout must not contain twenty-fifth-interpret skipped otherwise marker AZL_SPINE_P25_BAD1"
  cat "$out" >&2 || true
  exit 659
fi
if rg -q 'AZL_SPINE_P25_BAD2' "$out"; then
  err "stdout must not contain twenty-fifth-interpret skipped then marker AZL_SPINE_P25_BAD2"
  cat "$out" >&2 || true
  exit 660
fi
if ! rg -q 'AZL_SPINE_P25_T' "$out" || ! rg -q 'AZL_SPINE_P25_F' "$out"; then
  err "stdout missing twenty-fifth-interpret markers AZL_SPINE_P25_T and/or AZL_SPINE_P25_F (two sequential ifs)"
  cat "$out" >&2 || true
  exit 661
fi
if ! awk '
  /AZL_SPINE_P25_T/ && !t { t = NR }
  /AZL_SPINE_P25_F/ && !f { f = NR }
  END { exit !(t && f && t < f) }
' "$out"; then
  err "stdout expected AZL_SPINE_P25_T line before AZL_SPINE_P25_F (ordered sequential ifs in one emitted program)"
  cat "$out" >&2 || true
  exit 662
fi
if ! rg -q 'AZL_SPINE_P26_OUTER' "$out" || ! rg -q 'AZL_SPINE_P26_INNER' "$out"; then
  err "stdout missing twenty-sixth-interpret nested-if-in-then markers AZL_SPINE_P26_OUTER and/or AZL_SPINE_P26_INNER"
  cat "$out" >&2 || true
  exit 663
fi
if rg -q 'AZL_SPINE_P26_BAD1' "$out" || rg -q 'AZL_SPINE_P26_BAD2' "$out"; then
  err "stdout must not contain AZL_SPINE_P26_BAD1 or AZL_SPINE_P26_BAD2 (nested if in then-branch)"
  cat "$out" >&2 || true
  exit 664
fi
if ! awk '
  /AZL_SPINE_P26_OUTER/ && !o { o = NR }
  /AZL_SPINE_P26_INNER/ && !i { i = NR }
  END { exit !(o && i && o < i) }
' "$out"; then
  err "stdout expected AZL_SPINE_P26_OUTER line before AZL_SPINE_P26_INNER (nested if inside then)"
  cat "$out" >&2 || true
  exit 665
fi
if ! rg -q 'AZL_SPINE_P27_OUTER' "$out" || ! rg -q 'AZL_SPINE_P27_INNER' "$out"; then
  err "stdout missing twenty-seventh-interpret nested-if-in-otherwise markers AZL_SPINE_P27_OUTER and/or AZL_SPINE_P27_INNER"
  cat "$out" >&2 || true
  exit 666
fi
if rg -q 'AZL_SPINE_P27_BAD1' "$out" || rg -q 'AZL_SPINE_P27_BAD2' "$out"; then
  err "stdout must not contain AZL_SPINE_P27_BAD1 or AZL_SPINE_P27_BAD2 (nested if inside otherwise)"
  cat "$out" >&2 || true
  exit 667
fi
if ! awk '
  /AZL_SPINE_P27_OUTER/ && !o { o = NR }
  /AZL_SPINE_P27_INNER/ && !i { i = NR }
  END { exit !(o && i && o < i) }
' "$out"; then
  err "stdout expected AZL_SPINE_P27_OUTER line before AZL_SPINE_P27_INNER (nested if inside otherwise)"
  cat "$out" >&2 || true
  exit 668
fi
if ! rg -q 'AZL_SPINE_P28_OUTER' "$out" || ! rg -q 'AZL_SPINE_P28_INNER' "$out"; then
  err "stdout missing twenty-eighth-interpret nested expression-if markers AZL_SPINE_P28_OUTER and/or AZL_SPINE_P28_INNER"
  cat "$out" >&2 || true
  exit 669
fi
if rg -q 'AZL_SPINE_P28_BAD1' "$out" || rg -q 'AZL_SPINE_P28_BAD2' "$out"; then
  err "stdout must not contain AZL_SPINE_P28_BAD1 or AZL_SPINE_P28_BAD2"
  cat "$out" >&2 || true
  exit 670
fi
if ! awk '
  /AZL_SPINE_P28_OUTER/ && !o { o = NR }
  /AZL_SPINE_P28_INNER/ && !i { i = NR }
  END { exit !(o && i && o < i) }
' "$out"; then
  err "stdout expected AZL_SPINE_P28_OUTER line before AZL_SPINE_P28_INNER (nested if under expression outer then)"
  cat "$out" >&2 || true
  exit 671
fi
if rg -q 'AZL_SPINE_P29_BAD1' "$out" || rg -q 'AZL_SPINE_P29_BAD2' "$out" || rg -q 'AZL_SPINE_P29_BAD3' "$out"; then
  err "stdout must not contain AZL_SPINE_P29_BAD1, AZL_SPINE_P29_BAD2, or AZL_SPINE_P29_BAD3"
  cat "$out" >&2 || true
  exit 672
fi
if ! rg -q 'AZL_SPINE_P29_A' "$out" || ! rg -q 'AZL_SPINE_P29_B' "$out" || ! rg -q 'AZL_SPINE_P29_C' "$out"; then
  err "stdout missing twenty-ninth-interpret markers AZL_SPINE_P29_A / P29_B / P29_C (three sequential ifs)"
  cat "$out" >&2 || true
  exit 673
fi
if ! awk '
  /AZL_SPINE_P29_A/ && !a { a = NR }
  /AZL_SPINE_P29_B/ && !b { b = NR }
  /AZL_SPINE_P29_C/ && !c { c = NR }
  END { exit !(a && b && c && a < b && b < c) }
' "$out"; then
  err "stdout expected AZL_SPINE_P29_A then P29_B then P29_C (three sequential if decisions)"
  cat "$out" >&2 || true
  exit 674
fi
if rg -q 'AZL_SPINE_P30_BAD1' "$out" || rg -q 'AZL_SPINE_P30_BAD2' "$out"; then
  err "stdout must not contain AZL_SPINE_P30_BAD1 or AZL_SPINE_P30_BAD2"
  cat "$out" >&2 || true
  exit 675
fi
if ! rg -q 'AZL_SPINE_P30_A' "$out" || ! rg -q 'AZL_SPINE_P30_B' "$out" || ! rg -q 'AZL_SPINE_P30_C' "$out"; then
  err "stdout missing thirtieth-interpret markers AZL_SPINE_P30_A / P30_B / P30_C"
  cat "$out" >&2 || true
  exit 676
fi
if ! awk '
  /AZL_SPINE_P30_A/ && !a { a = NR }
  /AZL_SPINE_P30_B/ && !b { b = NR }
  /AZL_SPINE_P30_C/ && !c { c = NR }
  END { exit !(a && b && c && a < b && b < c) }
' "$out"; then
  err "stdout expected AZL_SPINE_P30_A then P30_B then P30_C (multi-statement then + second if otherwise)"
  cat "$out" >&2 || true
  exit 677
fi
if rg -q 'AZL_SPINE_P31_BAD1' "$out" || rg -q 'AZL_SPINE_P31_BAD2' "$out"; then
  err "stdout must not contain AZL_SPINE_P31_BAD1 or AZL_SPINE_P31_BAD2 (nested multi-statement then under outer true)"
  cat "$out" >&2 || true
  exit 678
fi
if ! rg -q 'AZL_SPINE_P31_OUTER' "$out" || ! rg -q 'AZL_SPINE_P31_A' "$out" || ! rg -q 'AZL_SPINE_P31_B' "$out"; then
  err "stdout missing thirty-first-interpret markers AZL_SPINE_P31_OUTER / P31_A / P31_B"
  cat "$out" >&2 || true
  exit 679
fi
if ! awk '
  /AZL_SPINE_P31_OUTER/ && !o { o = NR }
  /AZL_SPINE_P31_A/ && !a { a = NR }
  /AZL_SPINE_P31_B/ && !b { b = NR }
  END { exit !(o && a && b && o < a && a < b) }
' "$out"; then
  err "stdout expected AZL_SPINE_P31_OUTER then P31_A then P31_B (nested multi-statement inner then)"
  cat "$out" >&2 || true
  exit 680
fi
if rg -q 'AZL_SPINE_P32_BAD1' "$out" || rg -q 'AZL_SPINE_P32_BAD2' "$out"; then
  err "stdout must not contain AZL_SPINE_P32_BAD1 or AZL_SPINE_P32_BAD2 (nested multi-statement otherwise under outer false)"
  cat "$out" >&2 || true
  exit 681
fi
if ! rg -q 'AZL_SPINE_P32_OUTER' "$out" || ! rg -q 'AZL_SPINE_P32_A' "$out" || ! rg -q 'AZL_SPINE_P32_B' "$out"; then
  err "stdout missing thirty-second-interpret markers AZL_SPINE_P32_OUTER / P32_A / P32_B"
  cat "$out" >&2 || true
  exit 682
fi
if ! awk '
  /AZL_SPINE_P32_OUTER/ && !o { o = NR }
  /AZL_SPINE_P32_A/ && !a { a = NR }
  /AZL_SPINE_P32_B/ && !b { b = NR }
  END { exit !(o && a && b && o < a && a < b) }
' "$out"; then
  err "stdout expected AZL_SPINE_P32_OUTER then P32_A then P32_B (nested multi-statement inner otherwise)"
  cat "$out" >&2 || true
  exit 683
fi
if rg -q 'AZL_SPINE_P33_BAD1' "$out" || rg -q 'AZL_SPINE_P33_BAD2' "$out"; then
  err "stdout must not contain AZL_SPINE_P33_BAD1 or AZL_SPINE_P33_BAD2 (nested expression under outer ==1)"
  cat "$out" >&2 || true
  exit 684
fi
if ! rg -q 'AZL_SPINE_P33_OUTER' "$out" || ! rg -q 'AZL_SPINE_P33_INNER' "$out"; then
  err "stdout missing thirty-third-interpret markers AZL_SPINE_P33_OUTER and/or AZL_SPINE_P33_INNER"
  cat "$out" >&2 || true
  exit 685
fi
if ! awk '
  /AZL_SPINE_P33_OUTER/ && !o { o = NR }
  /AZL_SPINE_P33_INNER/ && !i { i = NR }
  END { exit !(o && i && o < i) }
' "$out"; then
  err "stdout expected AZL_SPINE_P33_OUTER line before AZL_SPINE_P33_INNER"
  cat "$out" >&2 || true
  exit 686
fi
if rg -q 'AZL_SPINE_P34_BAD1' "$out" || rg -q 'AZL_SPINE_P34_BAD2' "$out" || rg -q 'AZL_SPINE_P34_BAD3' "$out"; then
  err "stdout must not contain AZL_SPINE_P34_BAD1, AZL_SPINE_P34_BAD2, or AZL_SPINE_P34_BAD3 (three-level nesting)"
  cat "$out" >&2 || true
  exit 687
fi
if ! rg -q 'AZL_SPINE_P34_L1' "$out" || ! rg -q 'AZL_SPINE_P34_L2' "$out" || ! rg -q 'AZL_SPINE_P34_L3' "$out"; then
  err "stdout missing thirty-fourth-interpret markers AZL_SPINE_P34_L1 / L2 / L3"
  cat "$out" >&2 || true
  exit 688
fi
if ! awk '
  /AZL_SPINE_P34_L1/ && !a { a = NR }
  /AZL_SPINE_P34_L2/ && !b { b = NR }
  /AZL_SPINE_P34_L3/ && !c { c = NR }
  END { exit !(a && b && c && a < b && b < c) }
' "$out"; then
  err "stdout expected AZL_SPINE_P34_L1 then L2 then L3 (three nested levels)"
  cat "$out" >&2 || true
  exit 689
fi
if rg -q 'AZL_SPINE_P35_BAD1' "$out" || rg -q 'AZL_SPINE_P35_BAD2' "$out" || rg -q 'AZL_SPINE_P35_BAD3' "$out" || rg -q 'AZL_SPINE_P35_BAD4' "$out"; then
  err "stdout must not contain AZL_SPINE_P35_BAD1 through AZL_SPINE_P35_BAD4 (four alternating outcomes)"
  cat "$out" >&2 || true
  exit 690
fi
if ! rg -q 'AZL_SPINE_P35_A' "$out" || ! rg -q 'AZL_SPINE_P35_B' "$out" || ! rg -q 'AZL_SPINE_P35_C' "$out" || ! rg -q 'AZL_SPINE_P35_D' "$out"; then
  err "stdout missing thirty-fifth-interpret markers AZL_SPINE_P35_A / B / C / D"
  cat "$out" >&2 || true
  exit 691
fi
if ! awk '
  /AZL_SPINE_P35_A/ && !a { a = NR }
  /AZL_SPINE_P35_B/ && !b { b = NR }
  /AZL_SPINE_P35_C/ && !c { c = NR }
  /AZL_SPINE_P35_D/ && !d { d = NR }
  END { exit !(a && b && c && d && a < b && b < c && c < d) }
' "$out"; then
  err "stdout expected AZL_SPINE_P35_A then B then C then D (alternating branch sequence)"
  cat "$out" >&2 || true
  exit 692
fi
if rg -q 'AZL_SPINE_P36_BAD1' "$out" || rg -q 'AZL_SPINE_P36_BAD2' "$out"; then
  err "stdout must not contain AZL_SPINE_P36_BAD1 or AZL_SPINE_P36_BAD2 (mixed multi-statement then/otherwise)"
  cat "$out" >&2 || true
  exit 693
fi
if ! rg -q 'AZL_SPINE_P36_A' "$out" || ! rg -q 'AZL_SPINE_P36_B' "$out" || ! rg -q 'AZL_SPINE_P36_C' "$out" || ! rg -q 'AZL_SPINE_P36_D' "$out"; then
  err "stdout missing thirty-sixth-interpret markers AZL_SPINE_P36_A / B / C / D"
  cat "$out" >&2 || true
  exit 694
fi
if ! awk '
  /AZL_SPINE_P36_A/ && !a { a = NR }
  /AZL_SPINE_P36_B/ && !b { b = NR }
  /AZL_SPINE_P36_C/ && !c { c = NR }
  /AZL_SPINE_P36_D/ && !d { d = NR }
  END { exit !(a && b && c && d && a < b && b < c && c < d) }
' "$out"; then
  err "stdout expected AZL_SPINE_P36_A then B then C then D (expression then + otherwise)"
  cat "$out" >&2 || true
  exit 695
fi
if rg -q 'AZL_SPINE_P37_BAD1' "$out" || rg -q 'AZL_SPINE_P37_BAD2' "$out"; then
  err "stdout must not contain AZL_SPINE_P37_BAD1 or AZL_SPINE_P37_BAD2 (otherwise then inner branch flip)"
  cat "$out" >&2 || true
  exit 696
fi
if ! rg -q 'AZL_SPINE_P37_OUTER' "$out" || ! rg -q 'AZL_SPINE_P37_INNER' "$out"; then
  err "stdout missing thirty-seventh-interpret markers AZL_SPINE_P37_OUTER and/or AZL_SPINE_P37_INNER"
  cat "$out" >&2 || true
  exit 697
fi
if ! awk '
  /AZL_SPINE_P37_OUTER/ && !o { o = NR }
  /AZL_SPINE_P37_INNER/ && !i { i = NR }
  END { exit !(o && i && o < i) }
' "$out"; then
  err "stdout expected AZL_SPINE_P37_OUTER line before AZL_SPINE_P37_INNER"
  cat "$out" >&2 || true
  exit 698
fi
if rg -q 'AZL_SPINE_P38_BAD1' "$out" || rg -q 'AZL_SPINE_P38_BAD2' "$out" || rg -q 'AZL_SPINE_P38_BAD3' "$out"; then
  err "stdout must not contain AZL_SPINE_P38_BAD1, AZL_SPINE_P38_BAD2, or AZL_SPINE_P38_BAD3 (expression after mutation)"
  cat "$out" >&2 || true
  exit 699
fi
if ! rg -q 'AZL_SPINE_P38_A' "$out" || ! rg -q 'AZL_SPINE_P38_B' "$out" || ! rg -q 'AZL_SPINE_P38_C' "$out"; then
  err "stdout missing thirty-eighth-interpret markers AZL_SPINE_P38_A / B / C"
  cat "$out" >&2 || true
  exit 700
fi
if ! awk '
  /AZL_SPINE_P38_A/ && !a { a = NR }
  /AZL_SPINE_P38_B/ && !b { b = NR }
  /AZL_SPINE_P38_C/ && !c { c = NR }
  END { exit !(a && b && c && a < b && b < c) }
' "$out"; then
  err "stdout expected AZL_SPINE_P38_A then B then C (sequential == after set)"
  cat "$out" >&2 || true
  exit 701
fi
if rg -q 'AZL_SPINE_P39_BAD1' "$out" || rg -q 'AZL_SPINE_P39_BAD2' "$out" || rg -q 'AZL_SPINE_P39_BAD3' "$out"; then
  err "stdout must not contain AZL_SPINE_P39_BAD1, AZL_SPINE_P39_BAD2, or AZL_SPINE_P39_BAD3 (double-nested mixed branches)"
  cat "$out" >&2 || true
  exit 702
fi
if ! rg -q 'AZL_SPINE_P39_L1' "$out" || ! rg -q 'AZL_SPINE_P39_L2' "$out" || ! rg -q 'AZL_SPINE_P39_L3' "$out"; then
  err "stdout missing thirty-ninth-interpret markers AZL_SPINE_P39_L1 / L2 / L3"
  cat "$out" >&2 || true
  exit 703
fi
if ! awk '
  /AZL_SPINE_P39_L1/ && !a { a = NR }
  /AZL_SPINE_P39_L2/ && !b { b = NR }
  /AZL_SPINE_P39_L3/ && !c { c = NR }
  END { exit !(a && b && c && a < b && b < c) }
' "$out"; then
  err "stdout expected AZL_SPINE_P39_L1 then L2 then L3 (nested mixed true/false)"
  cat "$out" >&2 || true
  exit 704
fi
if rg -q 'AZL_SPINE_P40_BAD1' "$out" || rg -q 'AZL_SPINE_P40_BAD2' "$out" || rg -q 'AZL_SPINE_P40_BAD3' "$out" || rg -q 'AZL_SPINE_P40_BAD4' "$out"; then
  err "stdout must not contain AZL_SPINE_P40_BAD1 through AZL_SPINE_P40_BAD4 (mixed == and flag branch)"
  cat "$out" >&2 || true
  exit 705
fi
if ! rg -q 'AZL_SPINE_P40_A' "$out" || ! rg -q 'AZL_SPINE_P40_B' "$out" || ! rg -q 'AZL_SPINE_P40_C' "$out" || ! rg -q 'AZL_SPINE_P40_D' "$out"; then
  err "stdout missing fortieth-interpret markers AZL_SPINE_P40_A / B / C / D"
  cat "$out" >&2 || true
  exit 706
fi
if ! awk '
  /AZL_SPINE_P40_A/ && !a { a = NR }
  /AZL_SPINE_P40_B/ && !b { b = NR }
  /AZL_SPINE_P40_C/ && !c { c = NR }
  /AZL_SPINE_P40_D/ && !d { d = NR }
  END { exit !(a && b && c && d && a < b && b < c && c < d) }
' "$out"; then
  err "stdout expected AZL_SPINE_P40_A then B then C then D (expression + flag + re-read ::azl_spine_p40)"
  cat "$out" >&2 || true
  exit 707
fi
if rg -q 'AZL_SPINE_P41_BAD1' "$out" || rg -q 'AZL_SPINE_P41_BAD2' "$out"; then
  err "stdout must not contain AZL_SPINE_P41_BAD1 or AZL_SPINE_P41_BAD2 (otherwise then set + inner ==)"
  cat "$out" >&2 || true
  exit 708
fi
if ! rg -q 'AZL_SPINE_P41_OUTER' "$out" || ! rg -q 'AZL_SPINE_P41_INNER' "$out"; then
  err "stdout missing forty-first-interpret markers AZL_SPINE_P41_OUTER and/or AZL_SPINE_P41_INNER"
  cat "$out" >&2 || true
  exit 709
fi
if ! awk '
  /AZL_SPINE_P41_OUTER/ && !o { o = NR }
  /AZL_SPINE_P41_INNER/ && !i { i = NR }
  END { exit !(o && i && o < i) }
' "$out"; then
  err "stdout expected AZL_SPINE_P41_OUTER line before AZL_SPINE_P41_INNER"
  cat "$out" >&2 || true
  exit 710
fi
if rg -q 'AZL_SPINE_P42_BAD1' "$out" || rg -q 'AZL_SPINE_P42_BAD2' "$out" || rg -q 'AZL_SPINE_P42_BAD3' "$out"; then
  err "stdout must not contain AZL_SPINE_P42_BAD1, AZL_SPINE_P42_BAD2, or AZL_SPINE_P42_BAD3"
  cat "$out" >&2 || true
  exit 711
fi
if ! rg -q 'AZL_SPINE_P42_A' "$out" || ! rg -q 'AZL_SPINE_P42_B' "$out" || ! rg -q 'AZL_SPINE_P42_C' "$out" || ! rg -q 'AZL_SPINE_P42_D' "$out"; then
  err "stdout missing forty-second-interpret markers AZL_SPINE_P42_A / B / C / D"
  cat "$out" >&2 || true
  exit 712
fi
if ! awk '
  /AZL_SPINE_P42_A/ && !a { a = NR }
  /AZL_SPINE_P42_B/ && !b { b = NR }
  /AZL_SPINE_P42_C/ && !c { c = NR }
  /AZL_SPINE_P42_D/ && !d { d = NR }
  END { exit !(a && b && c && d && a < b && b < c && c < d) }
' "$out"; then
  err "stdout expected AZL_SPINE_P42_A then B then C then D (final multi-statement otherwise)"
  cat "$out" >&2 || true
  exit 713
fi
if rg -q 'AZL_SPINE_P43_BAD1' "$out" || rg -q 'AZL_SPINE_P43_BAD2' "$out" || rg -q 'AZL_SPINE_P43_BAD3' "$out"; then
  err "stdout must not contain AZL_SPINE_P43_BAD1, AZL_SPINE_P43_BAD2, or AZL_SPINE_P43_BAD3 (triple expression after mutation)"
  cat "$out" >&2 || true
  exit 714
fi
if ! rg -q 'AZL_SPINE_P43_A' "$out" || ! rg -q 'AZL_SPINE_P43_B' "$out" || ! rg -q 'AZL_SPINE_P43_C' "$out"; then
  err "stdout missing forty-third-interpret markers AZL_SPINE_P43_A / B / C"
  cat "$out" >&2 || true
  exit 715
fi
if ! awk '
  /AZL_SPINE_P43_A/ && !a { a = NR }
  /AZL_SPINE_P43_B/ && !b { b = NR }
  /AZL_SPINE_P43_C/ && !c { c = NR }
  END { exit !(a && b && c && a < b && b < c) }
' "$out"; then
  err "stdout expected AZL_SPINE_P43_A then P43_B then P43_C (sequential == after each set)"
  cat "$out" >&2 || true
  exit 716
fi
if rg -q 'AZL_SPINE_P44_BAD1' "$out" || rg -q 'AZL_SPINE_P44_BAD2' "$out" || rg -q 'AZL_SPINE_P44_BAD3' "$out"; then
  err "stdout must not contain AZL_SPINE_P44_BAD1, AZL_SPINE_P44_BAD2, or AZL_SPINE_P44_BAD3 (nested outer false inner false inner-inner true)"
  cat "$out" >&2 || true
  exit 717
fi
if ! rg -q 'AZL_SPINE_P44_L1' "$out" || ! rg -q 'AZL_SPINE_P44_L2' "$out" || ! rg -q 'AZL_SPINE_P44_L3' "$out"; then
  err "stdout missing forty-fourth-interpret markers AZL_SPINE_P44_L1 / L2 / L3"
  cat "$out" >&2 || true
  exit 718
fi
if ! awk '
  /AZL_SPINE_P44_L1/ && !a { a = NR }
  /AZL_SPINE_P44_L2/ && !b { b = NR }
  /AZL_SPINE_P44_L3/ && !c { c = NR }
  END { exit !(a && b && c && a < b && b < c) }
' "$out"; then
  err "stdout expected AZL_SPINE_P44_L1 then L2 then L3 (outer otherwise → nested otherwise → inner then)"
  cat "$out" >&2 || true
  exit 719
fi
if rg -q 'AZL_SPINE_P45_BAD1' "$out" || rg -q 'AZL_SPINE_P45_BAD2' "$out"; then
  err "stdout must not contain AZL_SPINE_P45_BAD1 or AZL_SPINE_P45_BAD2 (outer then set + inner ==)"
  cat "$out" >&2 || true
  exit 720
fi
if ! rg -q 'AZL_SPINE_P45_OUTER' "$out" || ! rg -q 'AZL_SPINE_P45_INNER' "$out"; then
  err "stdout missing forty-fifth-interpret markers AZL_SPINE_P45_OUTER and/or AZL_SPINE_P45_INNER"
  cat "$out" >&2 || true
  exit 721
fi
if ! awk '
  /AZL_SPINE_P45_OUTER/ && !o { o = NR }
  /AZL_SPINE_P45_INNER/ && !i { i = NR }
  END { exit !(o && i && o < i) }
' "$out"; then
  err "stdout expected AZL_SPINE_P45_OUTER line before AZL_SPINE_P45_INNER (mutation before inner comparison)"
  cat "$out" >&2 || true
  exit 722
fi
if rg -q 'AZL_SPINE_P46_BAD1' "$out" || rg -q 'AZL_SPINE_P46_BAD2' "$out" || rg -q 'AZL_SPINE_P46_BAD3' "$out" || rg -q 'AZL_SPINE_P46_BAD4' "$out" || rg -q 'AZL_SPINE_P46_BAD5' "$out"; then
  err "stdout must not contain AZL_SPINE_P46_BAD1 through AZL_SPINE_P46_BAD5 (five-way plain alternation)"
  cat "$out" >&2 || true
  exit 723
fi
if ! rg -q 'AZL_SPINE_P46_A' "$out" || ! rg -q 'AZL_SPINE_P46_B' "$out" || ! rg -q 'AZL_SPINE_P46_C' "$out" || ! rg -q 'AZL_SPINE_P46_D' "$out" || ! rg -q 'AZL_SPINE_P46_E' "$out"; then
  err "stdout missing forty-sixth-interpret markers AZL_SPINE_P46_A / B / C / D / E"
  cat "$out" >&2 || true
  exit 724
fi
if ! awk '
  /AZL_SPINE_P46_A/ && !a { a = NR }
  /AZL_SPINE_P46_B/ && !b { b = NR }
  /AZL_SPINE_P46_C/ && !c { c = NR }
  /AZL_SPINE_P46_D/ && !d { d = NR }
  /AZL_SPINE_P46_E/ && !e { e = NR }
  END { exit !(a && b && c && d && e && a < b && b < c && c < d && d < e) }
' "$out"; then
  err "stdout expected AZL_SPINE_P46_A then B then C then D then E (long alternating plain-variable path)"
  cat "$out" >&2 || true
  exit 725
fi
if rg -q 'AZL_SPINE_P47_BAD1' "$out" || rg -q 'AZL_SPINE_P47_BAD2' "$out" || rg -q 'AZL_SPINE_P47_BAD3' "$out"; then
  err "stdout must not contain AZL_SPINE_P47_BAD1, AZL_SPINE_P47_BAD2, or AZL_SPINE_P47_BAD3"
  cat "$out" >&2 || true
  exit 726
fi
if ! rg -q 'AZL_SPINE_P47_A' "$out" || ! rg -q 'AZL_SPINE_P47_B' "$out" || ! rg -q 'AZL_SPINE_P47_C' "$out"; then
  err "stdout missing forty-seventh-interpret markers AZL_SPINE_P47_A / B / C"
  cat "$out" >&2 || true
  exit 727
fi
if ! awk '
  /AZL_SPINE_P47_A/ && !a { a = NR }
  /AZL_SPINE_P47_B/ && !b { b = NR }
  /AZL_SPINE_P47_C/ && !c { c = NR }
  END { exit !(a && b && c && a < b && b < c) }
' "$out"; then
  err "stdout expected AZL_SPINE_P47_A then B then C (expr true, expr false else, plain flag false)"
  cat "$out" >&2 || true
  exit 728
fi
if rg -q 'AZL_SPINE_P48_BAD1' "$out" || rg -q 'AZL_SPINE_P48_BAD2' "$out"; then
  err "stdout must not contain AZL_SPINE_P48_BAD1 or AZL_SPINE_P48_BAD2 (outer true inner expression false → multi-statement otherwise)"
  cat "$out" >&2 || true
  exit 729
fi
if ! rg -q 'AZL_SPINE_P48_OUTER' "$out" || ! rg -q 'AZL_SPINE_P48_A' "$out" || ! rg -q 'AZL_SPINE_P48_B' "$out"; then
  err "stdout missing forty-eighth-interpret markers AZL_SPINE_P48_OUTER / P48_A / P48_B"
  cat "$out" >&2 || true
  exit 730
fi
if ! awk '
  /AZL_SPINE_P48_OUTER/ && !o { o = NR }
  /AZL_SPINE_P48_A/ && !a { a = NR }
  /AZL_SPINE_P48_B/ && !b { b = NR }
  END { exit !(o && a && b && o < a && a < b) }
' "$out"; then
  err "stdout expected AZL_SPINE_P48_OUTER then P48_A then P48_B (multi-statement inner otherwise after expr false)"
  cat "$out" >&2 || true
  exit 731
fi
if rg -q 'AZL_SPINE_P49_BAD1' "$out" || rg -q 'AZL_SPINE_P49_BAD2' "$out"; then
  err "stdout must not contain AZL_SPINE_P49_BAD1 or AZL_SPINE_P49_BAD2 (outer otherwise then set + multi-statement then)"
  cat "$out" >&2 || true
  exit 732
fi
if ! rg -q 'AZL_SPINE_P49_OUTER' "$out" || ! rg -q 'AZL_SPINE_P49_A' "$out" || ! rg -q 'AZL_SPINE_P49_B' "$out"; then
  err "stdout missing forty-ninth-interpret markers AZL_SPINE_P49_OUTER / P49_A / P49_B"
  cat "$out" >&2 || true
  exit 733
fi
if ! awk '
  /AZL_SPINE_P49_OUTER/ && !o { o = NR }
  /AZL_SPINE_P49_A/ && !a { a = NR }
  /AZL_SPINE_P49_B/ && !b { b = NR }
  END { exit !(o && a && b && o < a && a < b) }
' "$out"; then
  err "stdout expected AZL_SPINE_P49_OUTER then P49_A then P49_B"
  cat "$out" >&2 || true
  exit 734
fi
if rg -q 'AZL_SPINE_P50_BAD1' "$out" || rg -q 'AZL_SPINE_P50_BAD2' "$out" || rg -q 'AZL_SPINE_P50_BAD3' "$out"; then
  err "stdout must not contain AZL_SPINE_P50_BAD1, AZL_SPINE_P50_BAD2, or AZL_SPINE_P50_BAD3 (three-level mixed expression nesting)"
  cat "$out" >&2 || true
  exit 735
fi
if ! rg -q 'AZL_SPINE_P50_L1' "$out" || ! rg -q 'AZL_SPINE_P50_L2' "$out" || ! rg -q 'AZL_SPINE_P50_L3' "$out"; then
  err "stdout missing fiftieth-interpret markers AZL_SPINE_P50_L1 / L2 / L3"
  cat "$out" >&2 || true
  exit 736
fi
if ! awk '
  /AZL_SPINE_P50_L1/ && !a { a = NR }
  /AZL_SPINE_P50_L2/ && !b { b = NR }
  /AZL_SPINE_P50_L3/ && !c { c = NR }
  END { exit !(a && b && c && a < b && b < c) }
' "$out"; then
  err "stdout expected AZL_SPINE_P50_L1 then L2 then L3"
  cat "$out" >&2 || true
  exit 737
fi
if rg -q 'AZL_SPINE_P51_BAD1' "$out" || rg -q 'AZL_SPINE_P51_BAD2' "$out" || rg -q 'AZL_SPINE_P51_BAD3' "$out"; then
  err "stdout must not contain AZL_SPINE_P51_BAD1, AZL_SPINE_P51_BAD2, or AZL_SPINE_P51_BAD3 (ordered mix ending nested otherwise)"
  cat "$out" >&2 || true
  exit 738
fi
if ! rg -q 'AZL_SPINE_P51_A' "$out" || ! rg -q 'AZL_SPINE_P51_B' "$out" || ! rg -q 'AZL_SPINE_P51_C' "$out"; then
  err "stdout missing fifty-first-interpret markers AZL_SPINE_P51_A / B / C"
  cat "$out" >&2 || true
  exit 739
fi
if ! awk '
  /AZL_SPINE_P51_A/ && !a { a = NR }
  /AZL_SPINE_P51_B/ && !b { b = NR }
  /AZL_SPINE_P51_C/ && !c { c = NR }
  END { exit !(a && b && c && a < b && b < c) }
' "$out"; then
  err "stdout expected AZL_SPINE_P51_A then B then C"
  cat "$out" >&2 || true
  exit 740
fi
if rg -q 'AZL_SPINE_P52_BAD1' "$out" || rg -q 'AZL_SPINE_P52_BAD2' "$out" || rg -q 'AZL_SPINE_P52_BAD3' "$out"; then
  err "stdout must not contain AZL_SPINE_P52_BAD1, AZL_SPINE_P52_BAD2, or AZL_SPINE_P52_BAD3 (mutation-driven branch flip + multi-statement then)"
  cat "$out" >&2 || true
  exit 741
fi
if ! rg -q 'AZL_SPINE_P52_A' "$out" || ! rg -q 'AZL_SPINE_P52_B' "$out" || ! rg -q 'AZL_SPINE_P52_C' "$out" || ! rg -q 'AZL_SPINE_P52_D' "$out"; then
  err "stdout missing fifty-second-interpret markers AZL_SPINE_P52_A / B / C / D"
  cat "$out" >&2 || true
  exit 742
fi
if ! awk '
  /AZL_SPINE_P52_A/ && !a { a = NR }
  /AZL_SPINE_P52_B/ && !b { b = NR }
  /AZL_SPINE_P52_C/ && !c { c = NR }
  /AZL_SPINE_P52_D/ && !d { d = NR }
  END { exit !(a && b && c && d && a < b && b < c && c < d) }
' "$out"; then
  err "stdout expected AZL_SPINE_P52_A then B then C then D"
  cat "$out" >&2 || true
  exit 743
fi
if rg -q 'AZL_SPINE_P53_BAD1' "$out" || rg -q 'AZL_SPINE_P53_BAD2' "$out" || rg -q 'AZL_SPINE_P53_BAD3' "$out"; then
  err "stdout must not contain AZL_SPINE_P53_BAD1, AZL_SPINE_P53_BAD2, or AZL_SPINE_P53_BAD3 (outer false inner true then expr else)"
  cat "$out" >&2 || true
  exit 744
fi
if ! rg -q 'AZL_SPINE_P53_A' "$out" || ! rg -q 'AZL_SPINE_P53_B' "$out" || ! rg -q 'AZL_SPINE_P53_C' "$out"; then
  err "stdout missing fifty-third-interpret markers AZL_SPINE_P53_A / B / C"
  cat "$out" >&2 || true
  exit 745
fi
if ! awk '
  /AZL_SPINE_P53_A/ && !a { a = NR }
  /AZL_SPINE_P53_B/ && !b { b = NR }
  /AZL_SPINE_P53_C/ && !c { c = NR }
  END { exit !(a && b && c && a < b && b < c) }
' "$out"; then
  err "stdout expected AZL_SPINE_P53_A then B then C"
  cat "$out" >&2 || true
  exit 746
fi
if rg -q 'AZL_SPINE_P54_BAD1' "$out" || rg -q 'AZL_SPINE_P54_BAD2' "$out" || rg -q 'AZL_SPINE_P54_BAD3' "$out" || rg -q 'AZL_SPINE_P54_BAD4' "$out" || rg -q 'AZL_SPINE_P54_BAD5' "$out"; then
  err "stdout must not contain AZL_SPINE_P54_BAD1 through AZL_SPINE_P54_BAD5 (long mixed five outputs)"
  cat "$out" >&2 || true
  exit 747
fi
if ! rg -q 'AZL_SPINE_P54_A' "$out" || ! rg -q 'AZL_SPINE_P54_B' "$out" || ! rg -q 'AZL_SPINE_P54_C' "$out" || ! rg -q 'AZL_SPINE_P54_D' "$out" || ! rg -q 'AZL_SPINE_P54_E' "$out"; then
  err "stdout missing fifty-fourth-interpret markers AZL_SPINE_P54_A / B / C / D / E"
  cat "$out" >&2 || true
  exit 748
fi
if ! awk '
  /AZL_SPINE_P54_A/ && !a { a = NR }
  /AZL_SPINE_P54_B/ && !b { b = NR }
  /AZL_SPINE_P54_C/ && !c { c = NR }
  /AZL_SPINE_P54_D/ && !d { d = NR }
  /AZL_SPINE_P54_E/ && !e { e = NR }
  END { exit !(a && b && c && d && e && a < b && b < c && c < d && d < e) }
' "$out"; then
  err "stdout expected AZL_SPINE_P54_A then B then C then D then E"
  cat "$out" >&2 || true
  exit 749
fi
if rg -q 'AZL_SPINE_P55_BAD' "$out"; then
  err "stdout must not contain AZL_SPINE_P55_BAD (fifty-fifth interpret spine_component_v1 wrong-path marker)"
  cat "$out" >&2 || true
  exit 751
fi
if ! rg -q 'AZL_SPINE_P55_INIT' "$out" || ! rg -q 'AZL_SPINE_P55_A' "$out" || ! rg -q 'AZL_SPINE_P55_FINAL' "$out" || ! rg -q 'AZL_SPINE_P55_MEM' "$out"; then
  err "stdout missing fifty-fifth interpret spine_component_v1 markers AZL_SPINE_P55_INIT / P55_A / P55_FINAL / P55_MEM"
  cat "$out" >&2 || true
  exit 750
fi
if ! awk '
  /^p55_chain_ok$/ && !c1 { c1 = NR; next }
  /^p55_chain_ok$/ && c1 && !c2 { c2 = NR }
  /AZL_SPINE_P55_INIT/ && !i { i = NR }
  /AZL_SPINE_P55_A/ && !a { a = NR }
  /AZL_SPINE_P55_FINAL/ && !f { f = NR }
  /AZL_SPINE_P55_MEM/ && !m { m = NR }
  END {
    exit !(i && a && c1 && f && m && c2 && i < a && a < c1 && c1 < f && f < m && m < c2)
  }
' "$out"; then
  err "stdout fifty-fifth interpret spine_component_v1 order wrong: expect P55_INIT then P55_A then first p55_chain_ok (listener B say ::flag) then P55_FINAL then P55_MEM then second p55_chain_ok (memory)"
  cat "$out" >&2 || true
  exit 752
fi

echo "azl-interpreter-semantic-spine-behavior-smoke-ok"
exit 0
