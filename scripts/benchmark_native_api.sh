#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/azl_local_layout.sh"

REQS="${AZL_BENCH_REQS:-200}"
CONC="${AZL_BENCH_CONCURRENCY:-1}"
TOKEN="${AZL_BENCH_TOKEN:-azl_bench_token_2026}"

pick_port() {
  local p code
  while :; do
    p="$(( (RANDOM % 20000) + 30000 ))"
    code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 0.25 "http://127.0.0.1:${p}/healthz" 2>/dev/null || true)"
    case "$code" in
    000 | '') echo "$p"; return 0 ;;
    *) continue ;;
    esac
  done
}

PORT="${AZL_BENCH_PORT:-$(pick_port)}"
LOG_PATH="${AZL_BENCHMARKS_DIR}/benchmark_native_api.log"
LAT_FILE="${AZL_BENCHMARKS_DIR}/benchmark_native_api.lat"
mkdir -p "$AZL_BENCHMARKS_DIR"
: > "$LAT_FILE"

echo "[bench] starting native mode on 127.0.0.1:${PORT}"
AZL_API_TOKEN="$TOKEN" \
AZL_BUILD_API_PORT="$PORT" \
AZL_BIND_HOST="127.0.0.1" \
bash scripts/start_azl_native_mode.sh >"$LOG_PATH" 2>&1 &

deadline=$((SECONDS + 30))
until curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; do
  if [ $SECONDS -ge $deadline ]; then
    echo "ERROR: native API failed to become healthy"
    exit 90
  fi
  sleep 1
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
  echo "[bench] endpoint=${endpoint} requests=${ok} failures=${fail}"
}

# Keep single concurrency default for deterministic CI-like runs.
if [ "$CONC" -ne 1 ]; then
  echo "[bench] CONCURRENCY>1 requested; running endpoint workers in parallel"
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
  local p50_idx
  local p95_idx
  p50_idx="$(( (n * 50 + 99) / 100 ))"
  p95_idx="$(( (n * 95 + 99) / 100 ))"
  [ "$p50_idx" -lt 1 ] && p50_idx=1
  [ "$p95_idx" -lt 1 ] && p95_idx=1
  local p50
  local p95
  p50="$(sed -n "${p50_idx}p" "$tmp")"
  p95="$(sed -n "${p95_idx}p" "$tmp")"
  rm -f "$tmp"
  echo "$ep,$n,$mean,$p50,$p95"
}

HEALTH_SUM="$(summary healthz)"
STATUS_SUM="$(summary status)"
EXEC_SUM="$(summary exec_state)"

RESULT_PATH="${AZL_BENCHMARKS_DIR}/benchmark_native_api_$(date +%Y%m%d_%H%M%S).txt"
{
  echo "native_api_benchmark"
  echo "port=${PORT}"
  echo "requests_per_endpoint=${REQS}"
  echo "concurrency=${CONC}"
  echo "unit=us"
  echo "endpoint,count,mean,p50,p95"
  echo "$HEALTH_SUM"
  echo "$STATUS_SUM"
  echo "$EXEC_SUM"
} | tee "$RESULT_PATH"

echo "[bench] result saved: $RESULT_PATH"
