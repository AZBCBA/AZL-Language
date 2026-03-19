#!/usr/bin/env bash
# Run AZL and Python benchmarks and produce comparison table.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

REQS="${AZL_BENCH_REQS:-200}"
CONC="${AZL_BENCH_CONCURRENCY:-1}"
mkdir -p .azl

echo "=== AZL Native API Benchmark ==="
AZL_BENCH_REQS="$REQS" AZL_BENCH_CONCURRENCY="$CONC" bash scripts/benchmark_native_api.sh
AZL_RESULT="$(ls -t .azl/benchmark_native_api_*.txt 2>/dev/null | head -1)"

echo ""
echo "=== Python API Benchmark ==="
AZL_BENCH_REQS="$REQS" AZL_BENCH_CONCURRENCY="$CONC" bash scripts/benchmark_python_api.sh
PY_RESULT="$(ls -t .azl/benchmark_python_api_*.txt 2>/dev/null | head -1)"

# Parse results into vars
azl_healthz_mean=""
azl_healthz_p50=""
azl_status_mean=""
azl_status_p50=""
azl_exec_mean=""
azl_exec_p50=""
py_healthz_mean=""
py_healthz_p50=""
py_status_mean=""
py_status_p50=""
py_exec_mean=""
py_exec_p50=""

while IFS=',' read -r ep count mean p50 p95; do
  case "$ep" in
    healthz) azl_healthz_mean="$mean"; azl_healthz_p50="$p50" ;;
    status)  azl_status_mean="$mean";  azl_status_p50="$p50" ;;
    exec_state) azl_exec_mean="$mean"; azl_exec_p50="$p50" ;;
  esac
done < <(grep -E "^(healthz|status|exec_state)," "$AZL_RESULT" 2>/dev/null || true)

while IFS=',' read -r ep count mean p50 p95; do
  case "$ep" in
    healthz) py_healthz_mean="$mean"; py_healthz_p50="$p50" ;;
    status)  py_status_mean="$mean";  py_status_p50="$p50" ;;
    exec_state) py_exec_mean="$mean"; py_exec_p50="$p50" ;;
  esac
done < <(grep -E "^(healthz|status|exec_state)," "$PY_RESULT" 2>/dev/null || true)

# Compute faster (use awk for portable float compare)
faster_healthz="tie"
[ -n "$azl_healthz_mean" ] && [ -n "$py_healthz_mean" ] && {
  cmp="$(awk -v a="$azl_healthz_mean" -v b="$py_healthz_mean" 'BEGIN{if(a<b) print "AZL"; else if(b<a) print "Python"; else print "tie"}')"
  faster_healthz="$cmp"
}
faster_status="tie"
[ -n "$azl_status_mean" ] && [ -n "$py_status_mean" ] && {
  cmp="$(awk -v a="$azl_status_mean" -v b="$py_status_mean" 'BEGIN{if(a<b) print "AZL"; else if(b<a) print "Python"; else print "tie"}')"
  faster_status="$cmp"
}
faster_exec="tie"
[ -n "$azl_exec_mean" ] && [ -n "$py_exec_mean" ] && {
  cmp="$(awk -v a="$azl_exec_mean" -v b="$py_exec_mean" 'BEGIN{if(a<b) print "AZL"; else if(b<a) print "Python"; else print "tie"}')"
  faster_exec="$cmp"
}

# Comparison table
REPORT=".azl/benchmark_azl_vs_python_$(date +%Y%m%d_%H%M%S).txt"
{
  echo "=============================================="
  echo "  AZL vs Python API Latency Comparison"
  echo "  Requests per endpoint: $REQS | Concurrency: $CONC"
  echo "  Unit: microseconds (us)"
  echo "=============================================="
  echo ""
  printf "%-12s %12s %12s %12s %12s %8s\n" "Endpoint" "AZL mean(us)" "Python mean(us)" "AZL p50(us)" "Python p50(us)" "Faster"
  printf "%-12s %12s %12s %12s %12s %8s\n" "--------" "----------" "-------------" "----------" "-------------" "------"
  printf "%-12s %12s %12s %12s %12s %8s\n" "healthz" "${azl_healthz_mean:-N/A}" "${py_healthz_mean:-N/A}" "${azl_healthz_p50:-N/A}" "${py_healthz_p50:-N/A}" "$faster_healthz"
  printf "%-12s %12s %12s %12s %12s %8s\n" "status" "${azl_status_mean:-N/A}" "${py_status_mean:-N/A}" "${azl_status_p50:-N/A}" "${py_status_p50:-N/A}" "$faster_status"
  printf "%-12s %12s %12s %12s %12s %8s\n" "exec_state" "${azl_exec_mean:-N/A}" "${py_exec_mean:-N/A}" "${azl_exec_p50:-N/A}" "${py_exec_p50:-N/A}" "$faster_exec"
  echo ""
  echo "AZL result:    $AZL_RESULT"
  echo "Python result: $PY_RESULT"
} | tee "$REPORT"

echo ""
echo "[bench] comparison saved: $REPORT"
