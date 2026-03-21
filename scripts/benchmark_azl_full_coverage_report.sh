#!/usr/bin/env bash
# Full AZL coverage timing report: promoted doc pieces + full repo verify + perf smoke,
# optional reference C/Python spectral-norm (hyperfine). Writes Markdown under AZL_BENCHMARKS_DIR.
#
# This is the repo's honest answer to "test all of AZL" — not a single Benchmarks Game program.
#
# Usage: bash scripts/benchmark_azl_full_coverage_report.sh
# Exit: first failing AZL phase’s code; if AZL phases pass, non-zero if reference phase ran and failed (skipped reference → 0).
#
# ERROR[BENCHMARK_AZL_FULL_REPORT]: only for this script's own failures (see docs/ERROR_SYSTEM.md)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/azl_local_layout.sh"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT="${AZL_BENCHMARKS_DIR}/azl_full_coverage_report_${TS}.md"
REF_EXIT=0

die() {
  local c="${1:?}"; shift
  echo "ERROR[BENCHMARK_AZL_FULL_REPORT]: $*" >&2
  exit "$c"
}

if [ ! -f "Makefile" ] || [ ! -d "scripts" ]; then
  die 310 "must run from repository root"
fi

mkdir -p "$AZL_BENCHMARKS_DIR"

phase_row() {
  local name="$1" status="$2" sec="$3"
  printf '| %s | %s | %ss |\n' "$name" "$status" "$sec" >>"$REPORT"
}

run_phase() {
  local label="$1"
  shift
  local start end sec rc
  start=$(date +%s)
  set +e
  "$@"
  rc=$?
  set -e
  end=$(date +%s)
  sec=$((end - start))
  if [ "$rc" -eq 0 ]; then
    phase_row "$label" "PASS" "$sec"
  else
    phase_row "$label" "FAIL exit $rc" "$sec"
    echo "" >>"$REPORT"
    echo "**Stopped after failure — partial report.**" >>"$REPORT"
    echo "Report: $REPORT" >&2
    exit "$rc"
  fi
}

{
  echo "# AZL full coverage benchmark report"
  echo ""
  echo "**Generated (UTC):** $TS"
  echo ""
  echo "## What this measures (read this first)"
  echo ""
  echo "- **AZL phases** = everything this repository treats as **release truth** (docs + native gates + HTTP + tests). **This is not one tiny program** like the Benchmarks Game; it is **the whole integration bar**."
  echo "- **Reference phase** (if run) = **C vs Python** on **spectral-norm** — **other languages on a classic problem**, same machine. **It is not AZL code.**"
  echo "- For plain English, see **\`docs/BENCHMARKS_AZL_VS_REAL_WORLD.md\`**."
  echo ""
  echo "## Timings"
  echo ""
  echo "| Phase | Result | Wall seconds |"
  echo "|-------|--------|--------------|"
} >"$REPORT"

run_phase "1_doc_pieces_promoted" bash scripts/verify_documentation_pieces.sh --promoted-only
run_phase "2_full_repo_verify" env RUN_OPTIONAL_BENCHES=0 bash scripts/run_full_repo_verification.sh
run_phase "3_perf_smoke_native_api" bash scripts/perf_smoke.sh

ref_note=""
if command -v hyperfine >/dev/null 2>&1 && command -v gcc >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  REF_TMP="$(mktemp "${AZL_BENCHMARKS_DIR}/azl_full_ref.XXXXXX")"
  start=$(date +%s)
  set +e
  bash scripts/benchmark_language_real_world.sh >"$REF_TMP" 2>&1
  rc=$?
  set -e
  end=$(date +%s)
  sec=$((end - start))
  REF_EXIT="$rc"
  if [ "$rc" -eq 0 ]; then
    phase_row "4_reference_spectralnorm_c_vs_python" "PASS" "$sec"
    echo "" >>"$REPORT"
    echo "## Reference benchmark output (C vs Python, spectral-norm)" >>"$REPORT"
    echo "" >>"$REPORT"
    echo '```' >>"$REPORT"
    cat "$REF_TMP" >>"$REPORT"
    echo '```' >>"$REPORT"
  else
    phase_row "4_reference_spectralnorm_c_vs_python" "FAIL exit $rc" "$sec"
    echo "" >>"$REPORT"
    echo "## Reference benchmark — failed" >>"$REPORT"
    echo "" >>"$REPORT"
    echo '```' >>"$REPORT"
    cat "$REF_TMP" >>"$REPORT" 2>/dev/null || true
    echo '```' >>"$REPORT"
  fi
  rm -f "$REF_TMP"
else
  phase_row "4_reference_spectralnorm_c_vs_python" "SKIPPED (need hyperfine+gcc+python3)" "0"
  ref_note="Install **hyperfine**, **gcc**, and **python3** to append C vs Python spectral-norm timings to this report."
  REF_EXIT=0
fi

{
  echo ""
  echo "## Summary (plain English)"
  echo ""
  echo "- If phases **1–3** are **PASS**, your tree matches the project’s **full AZL verification** on this machine."
  echo "- Phase **4** (if PASS) shows how **fast C and Python** are on **one standard numeric benchmark** — use it as a **ruler**, not as “AZL speed.”"
  if [ -n "$ref_note" ]; then
    echo "- $ref_note"
  fi
  echo ""
  echo "## Files"
  echo ""
  echo "- This report: \`$REPORT\`"
  echo "- Hyperfine JSON (if phase 4 ran): \`${AZL_BENCHMARKS_DIR}/benchmark_language_real_world_hyperfine.json\`"
} >>"$REPORT"

echo "benchmark-azl-full-report-ok"
echo "$REPORT"
if [ "${REF_EXIT:-0}" -ne 0 ]; then
  echo "ERROR[BENCHMARK_AZL_FULL_REPORT]: reference benchmark phase failed (exit $REF_EXIT); see report" >&2
  exit "$REF_EXIT"
fi
exit 0
