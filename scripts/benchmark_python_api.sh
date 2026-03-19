#!/usr/bin/env bash
# Benchmark Python HTTP server for AZL vs Python comparison.
# Requires Python 3. Uses stdlib only.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

REQS="${AZL_BENCH_REQS:-200}"
CONC="${AZL_BENCH_CONCURRENCY:-1}"
TOKEN="${AZL_BENCH_TOKEN:-azl_bench_token_2026}"
PORT="${BENCH_PYTHON_PORT:-$(( (RANDOM % 20000) + 30000 ))}"
LAT_FILE=".azl/benchmark_python_api.lat"
mkdir -p .azl
: > "$LAT_FILE"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found - cannot run Python benchmark"
  exit 91
fi

echo "[bench-python] starting server on 127.0.0.1:${PORT}"
BENCH_PYTHON_PORT="$PORT" BENCH_PYTHON_TOKEN="$TOKEN" python3 scripts/benchmark_python_server.py &
PY_PID=$!
trap "kill $PY_PID 2>/dev/null || true" EXIT

deadline=$((SECONDS + 10))
until curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; do
  if [ $SECONDS -ge $deadline ]; then
    echo "ERROR: Python server failed to become healthy"
    exit 92
  fi
  sleep 0.2
done

bench_one() {
  local endpoint="$1"
  local i
  local ok=0
  local fail=0
  local start_ns
  local end_ns
  local dur_us

  for i in $(seq 1 "$REQS"); do
    start_ns="$(date +%s%N)"
    if [ "$endpoint" = "exec_state" ]; then
      curl -fsS -H "Authorization: Bearer ${TOKEN}" "http://127.0.0.1:${PORT}/api/exec_state" >/dev/null 2>&1 || fail=$((fail+1))
    elif [ "$endpoint" = "status" ]; then
      curl -fsS "http://127.0.0.1:${PORT}/status" >/dev/null 2>&1 || fail=$((fail+1))
    else
      curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1 || fail=$((fail+1))
    fi
    end_ns="$(date +%s%N)"
    dur_us="$(( (end_ns - start_ns) / 1000 ))"
    echo "$endpoint,$dur_us" >> "$LAT_FILE"
    ok=$((ok+1))
  done
  echo "[bench-python] endpoint=${endpoint} requests=${ok} failures=${fail}"
}

if [ "$CONC" -ne 1 ]; then
  bench_one healthz &
  pid1=$!
  bench_one status &
  pid2=$!
  bench_one exec_state &
  pid3=$!
  wait "$pid1" "$pid2" "$pid3"
else
  bench_one healthz
  bench_one status
  bench_one exec_state
fi

summary() {
  local ep="$1"
  local tmp
  tmp="$(mktemp)"
  awk -F',' -v e="$ep" '$1==e { print $2 }' "$LAT_FILE" | sort -n > "$tmp"
  local n
  n="$(wc -l < "$tmp" | tr -d ' ')"
  if [ "$n" -eq 0 ]; then
    rm -f "$tmp"
    echo "$ep,0,0,0,0"
    return 0
  fi
  local mean
  mean="$(awk '{sum+=$1} END{ if(NR==0) print 0; else printf "%.2f", sum/NR }' "$tmp")"
  local p50_idx p95_idx
  p50_idx="$(( (n * 50 + 99) / 100 ))"
  p95_idx="$(( (n * 95 + 99) / 100 ))"
  [ "$p50_idx" -lt 1 ] && p50_idx=1
  [ "$p95_idx" -lt 1 ] && p95_idx=1
  local p50 p95
  p50="$(sed -n "${p50_idx}p" "$tmp")"
  p95="$(sed -n "${p95_idx}p" "$tmp")"
  rm -f "$tmp"
  echo "$ep,$n,$mean,$p50,$p95"
}

HEALTH_SUM="$(summary healthz)"
STATUS_SUM="$(summary status)"
EXEC_SUM="$(summary exec_state)"

RESULT_PATH=".azl/benchmark_python_api_$(date +%Y%m%d_%H%M%S).txt"
{
  echo "python_api_benchmark"
  echo "port=${PORT}"
  echo "requests_per_endpoint=${REQS}"
  echo "concurrency=${CONC}"
  echo "unit=us"
  echo "endpoint,count,mean,p50,p95"
  echo "$HEALTH_SUM"
  echo "$STATUS_SUM"
  echo "$EXEC_SUM"
} | tee "$RESULT_PATH"

echo "[bench-python] result saved: $RESULT_PATH"
echo "$RESULT_PATH"
