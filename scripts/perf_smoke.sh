#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Thresholds (ms)
TH_HEALTH=1500
TH_STATUS=2000
TH_EXEC=2000

pass=0; total=3

measure_ms() {
  local cmd=("$@"); local start end
  start=$(date +%s%3N)
  "${cmd[@]}" >/dev/null 2>&1 || true
  end=$(date +%s%3N)
  echo $((end - start))
}

echo "⚡ Performance smoke (native API)"
PORT="${AZL_PERF_PORT:-37777}"
TOKEN="${AZL_PERF_TOKEN:-azl_perf_token}"
AZL_API_TOKEN="$TOKEN" AZL_BUILD_API_PORT="$PORT" AZL_BIND_HOST="127.0.0.1" bash scripts/start_azl_native_mode.sh >/tmp/azl_perf_smoke.log 2>&1 &
deadline=$((SECONDS + 30))
until curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; do
  if [ $SECONDS -ge $deadline ]; then
    echo "❌ Native runtime did not become healthy"
    exit 1
  fi
  sleep 1
done

t1=$(measure_ms curl -fsS "http://127.0.0.1:${PORT}/healthz")
echo "healthz: ${t1}ms (<= ${TH_HEALTH}ms)"
if [ "$t1" -le "$TH_HEALTH" ]; then pass=$((pass+1)); else echo "⚠️  healthz over threshold"; fi

t2=$(measure_ms curl -fsS "http://127.0.0.1:${PORT}/status")
echo "status: ${t2}ms (<= ${TH_STATUS}ms)"
if [ "$t2" -le "$TH_STATUS" ]; then pass=$((pass+1)); else echo "⚠️  status over threshold"; fi

t3=$(measure_ms curl -fsS -H "Authorization: Bearer ${TOKEN}" "http://127.0.0.1:${PORT}/api/exec_state")
echo "exec_state: ${t3}ms (<= ${TH_EXEC}ms)"
if [ "$t3" -le "$TH_EXEC" ]; then pass=$((pass+1)); else echo "⚠️  exec_state over threshold"; fi

if [ $total -eq 0 ]; then
  echo "⚠️  No perf tests executed"; exit 0
fi

rate=$(( pass * 100 / total ))
echo "Perf smoke pass rate: ${rate}% ($pass/$total)"
[ $pass -ge $total ] || exit 1
