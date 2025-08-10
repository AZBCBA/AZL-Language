#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Thresholds (ms)
TH_CORE=1500     # test_core end-to-end via JS
TH_INTEG=4000    # test_integration_final via Python

pass=0; total=2

measure_ms() {
  local cmd=("$@"); local start end
  start=$(date +%s%3N)
  "${cmd[@]}" >/dev/null 2>&1 || true
  end=$(date +%s%3N)
  echo $((end - start))
}

echo "⚡ Performance smoke"

# JS runtime test
if command -v node >/dev/null 2>&1; then
  t1=$(measure_ms node scripts/azl_runtime.js test_core.azl ::test.core)
  echo "JS core runtime: ${t1}ms (<= ${TH_CORE}ms)"
  if [ "$t1" -le "$TH_CORE" ]; then pass=$((pass+1)); else echo "⚠️  JS core over threshold"; fi
else
  echo "⚠️  Node not found, skipping JS runtime test"
  total=$((total-1))
fi

# Python runner test
if command -v python3 >/dev/null 2>&1; then
  t2=$(measure_ms python3 azl_runner.py test_integration_final.azl)
  echo "Python integration: ${t2}ms (<= ${TH_INTEG}ms)"
  if [ "$t2" -le "$TH_INTEG" ]; then pass=$((pass+1)); else echo "⚠️  Python integration over threshold"; fi
else
  echo "⚠️  Python3 not found, skipping Python runner test"
  total=$((total-1))
fi

if [ $total -eq 0 ]; then
  echo "⚠️  No perf tests executed"; exit 0
fi

rate=$(( pass * 100 / total ))
echo "Perf smoke pass rate: ${rate}% ($pass/$total)"
[ $pass -ge $total ] || exit 1
