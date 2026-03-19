#!/usr/bin/env bash
# Benchmark gate: block CI if AZL regresses >10% vs baseline
# Baseline: store mean latency from last known good run
# Usage: AZL_BENCH_BASELINE_healthz=5500 AZL_BENCH_BASELINE_status=5200 AZL_BENCH_BASELINE_exec_state=5200 bash scripts/benchmark_gate.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

REQS="${AZL_BENCH_REQS:-100}"
BASELINE_HEALTHZ="${AZL_BENCH_BASELINE_healthz:-6000}"
BASELINE_STATUS="${AZL_BENCH_BASELINE_status:-5500}"
BASELINE_EXEC="${AZL_BENCH_BASELINE_exec_state:-5500}"
THRESHOLD_PCT="${AZL_BENCH_REGRESSION_THRESHOLD:-10}"

mkdir -p .azl

echo "=== Benchmark Gate ==="
echo "Baseline (us): healthz=$BASELINE_HEALTHZ status=$BASELINE_STATUS exec_state=$BASELINE_EXEC"
echo "Regression threshold: ${THRESHOLD_PCT}%"
echo ""

AZL_BENCH_REQS="$REQS" bash scripts/benchmark_azl_vs_python.sh >/dev/null 2>&1 || true

AZL_RESULT="$(ls -t .azl/benchmark_native_api_*.txt 2>/dev/null | head -1)"
if [ -z "$AZL_RESULT" ] || [ ! -f "$AZL_RESULT" ]; then
  echo "ERROR: No AZL benchmark result found"
  exit 1
fi

healthz_mean=""
status_mean=""
exec_mean=""
while IFS=',' read -r ep count mean p50 p95; do
  case "$ep" in
    healthz) healthz_mean="$mean" ;;
    status)  status_mean="$mean" ;;
    exec_state) exec_mean="$mean" ;;
  esac
done < <(grep -E "^(healthz|status|exec_state)," "$AZL_RESULT" 2>/dev/null || true)

fail=0
check() {
  local name="$1" current="$2" baseline="$3"
  if [ -z "$current" ] || [ -z "$baseline" ]; then
    echo "⚠️  $name: missing data (current=$current baseline=$baseline)"
    return 0
  fi
  local pct
  pct=$(awk -v c="$current" -v b="$baseline" 'BEGIN{printf "%.1f", (c-b)/b*100}')
  if awk -v c="$current" -v b="$baseline" -v t="$THRESHOLD_PCT" 'BEGIN{exit (c <= b*(1+t/100)) ? 0 : 1}'; then
    echo "✅ $name: ${current}us (baseline ${baseline}us, ${pct}%)"
  else
    echo "❌ $name: ${current}us exceeds baseline ${baseline}us by >${THRESHOLD_PCT}% (${pct}%)"
    fail=1
  fi
}

check "healthz"    "$healthz_mean" "$BASELINE_HEALTHZ"
check "status"     "$status_mean"  "$BASELINE_STATUS"
check "exec_state" "$exec_mean"    "$BASELINE_EXEC"

[ $fail -eq 0 ] || exit 1
echo ""
echo "Benchmark gate passed"
