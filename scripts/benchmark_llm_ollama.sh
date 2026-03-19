#!/usr/bin/env bash
# LLM Benchmark: AZL vs Python via Ollama
# Compares latency of calling Ollama from:
#   1) Python client (urllib)
#   2) AZL native API proxy (/api/ollama/generate)
#   3) Curl (baseline)
#
# Requires: Ollama running with a small model (e.g. ollama run llama3.2:1b)
# Optional: AZL native engine running for AZL path
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

OLLAMA_HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"
REQS="${LLM_BENCH_REQS:-20}"
MODEL="${LLM_BENCH_MODEL:-llama3.2:1b}"
PROMPT="${LLM_BENCH_PROMPT:-Say hello in one word.}"
TOKEN="${AZL_BENCH_TOKEN:-azl_bench_token_2026}"
mkdir -p .azl

# Check Ollama is reachable
if ! curl -sf --max-time 5 "${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
  echo "ERROR: Ollama not reachable at ${OLLAMA_HOST}. Start with: ollama serve"
  echo "  Then: ollama run llama3.2:1b"
  exit 91
fi

echo "=== LLM Benchmark (Ollama backend) ==="
echo "  OLLAMA_HOST=$OLLAMA_HOST MODEL=$MODEL REQS=$REQS"
echo ""

# --- 1) Python client ---
echo "[1/3] Python client -> Ollama"
LLM_BENCH_LAT_FILE=".azl/benchmark_llm_python.lat" \
OLLAMA_HOST="$OLLAMA_HOST" LLM_BENCH_REQS="$REQS" LLM_BENCH_MODEL="$MODEL" LLM_BENCH_PROMPT="$PROMPT" \
  python3 scripts/benchmark_llm_python_client.py 2>/dev/null | tail -1 > .azl/llm_python_summary.txt || true
PY_LINE="$(cat .azl/llm_python_summary.txt 2>/dev/null || echo "generate,0,0,0,0")"

# --- 2) Curl baseline ---
echo "[2/3] Curl -> Ollama"
: > .azl/benchmark_llm_curl.lat
PAYLOAD="$(printf '{"model":"%s","prompt":"%s","stream":false,"options":{"num_predict":16}}' "$MODEL" "$PROMPT")"
for i in $(seq 1 "$REQS"); do
  start_ns="$(date +%s%N)"
  curl -sfS -m 120 -X POST -H "Content-Type: application/json" -d "$PAYLOAD" \
    "${OLLAMA_HOST}/api/generate" >/dev/null 2>&1 || true
  end_ns="$(date +%s%N)"
  dur_us=$(( (end_ns - start_ns) / 1000 ))
  echo "generate,$dur_us" >> .azl/benchmark_llm_curl.lat
done
summary_curl() {
  local tmp; tmp="$(mktemp)"
  awk -F',' '$1=="generate"{print $2}' .azl/benchmark_llm_curl.lat | sort -n > "$tmp"
  local n; n="$(wc -l < "$tmp" | tr -d ' ')"
  if [ "$n" -eq 0 ]; then echo "generate,0,0,0,0"; rm -f "$tmp"; return; fi
  local mean; mean="$(awk '{sum+=$1} END{printf "%.2f", sum/NR}' "$tmp")"
  local p50; p50="$(sed -n "$(( (n*50+99)/100 ))p" "$tmp")"
  local p95; p95="$(sed -n "$(( (n*95+99)/100 ))p" "$tmp")"
  [ -z "$p50" ] && p50=0; [ -z "$p95" ] && p95=0
  rm -f "$tmp"
  echo "generate,$n,$mean,$p50,$p95"
}
CURL_LINE="$(summary_curl)"

# --- 3) C native engine Ollama proxy (if running) ---
# Port 8080 is often the *enterprise* AZL HTTP stack (different routes). Only treat a port
# as the LLM proxy if GET /api/llm/capabilities returns ollama_http_proxy:true (see tools/azl_native_engine.c).
is_native_llm_proxy_port() {
  local p="$1"
  curl -fsS --max-time 3 "http://127.0.0.1:${p}/api/llm/capabilities" 2>/dev/null | grep -q '"ollama_http_proxy":true'
}

AZL_PORT="${AZL_BENCH_PORT:-}"
if [ -z "$AZL_PORT" ]; then
  for p in 8080 30000 30001 30002; do
    if is_native_llm_proxy_port "$p"; then
      AZL_PORT=$p
      break
    fi
  done
elif ! is_native_llm_proxy_port "$AZL_PORT"; then
  echo "WARN: AZL_BENCH_PORT=$AZL_PORT does not expose GET /api/llm/capabilities (native engine LLM honesty contract)."
  AZL_PORT=""
fi

AZL_LINE="generate,0,0,0,0"
if [ -n "$AZL_PORT" ]; then
  echo "[3/3] C native engine -> Ollama (port $AZL_PORT, POST /api/ollama/generate)"
  : > .azl/benchmark_llm_azl.lat
  for i in $(seq 1 "$REQS"); do
    start_ns="$(date +%s%N)"
    curl -sfS -m 120 -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d "{\"model\":\"$MODEL\",\"prompt\":\"$PROMPT\",\"stream\":false,\"options\":{\"num_predict\":16}}" \
      "http://127.0.0.1:${AZL_PORT}/api/ollama/generate" >/dev/null 2>&1 || true
    end_ns="$(date +%s%N)"
    dur_us=$(( (end_ns - start_ns) / 1000 ))
    echo "generate,$dur_us" >> .azl/benchmark_llm_azl.lat
  done
  tmp="$(mktemp)"
  awk -F',' '$1=="generate"{print $2}' .azl/benchmark_llm_azl.lat | sort -n > "$tmp"
  n="$(wc -l < "$tmp" | tr -d ' ')"
  if [ "$n" -gt 0 ]; then
    mean="$(awk '{sum+=$1} END{printf "%.2f", sum/NR}' "$tmp")"
    p50_idx=$(( (n*50+99)/100 )); [ "$p50_idx" -lt 1 ] && p50_idx=1
    p95_idx=$(( (n*95+99)/100 )); [ "$p95_idx" -lt 1 ] && p95_idx=1
    p50="$(sed -n "${p50_idx}p" "$tmp")"
    p95="$(sed -n "${p95_idx}p" "$tmp")"
    AZL_LINE="generate,$n,$mean,${p50:-0},${p95:-0}"
  fi
  rm -f "$tmp"
else
  echo "[3/3] C native engine LLM proxy: SKIP (no port with GET /api/llm/capabilities + ollama_http_proxy)"
  echo "      Build: bash scripts/build_azl_native_engine.sh"
  echo "      Run engine with bootstrap (see scripts/run_enterprise_daemon.sh / azl_bootstrap) on a free port, or use a minimal bundle +:"
  echo "      AZL_BUILD_API_PORT=18080 AZL_API_TOKEN=your_token .azl/bin/azl-native-engine <bootstrap.azl> <entry>"
  echo "      Then: AZL_BENCH_PORT=18080 AZL_BENCH_TOKEN=your_token $0"
fi

# --- Report ---
REPORT=".azl/benchmark_llm_ollama_$(date +%Y%m%d_%H%M%S).txt"
{
  echo "=============================================="
  echo "  LLM Benchmark: AZL vs Python vs Curl"
  echo "  Backend: Ollama @ $OLLAMA_HOST"
  echo "  Model: $MODEL | Requests: $REQS"
  echo "  Unit: microseconds (us)"
  echo "=============================================="
  echo ""
  printf "%-12s %12s %12s %12s\n" "Client" "mean(us)" "p50(us)" "p95(us)"
  printf "%-12s %12s %12s %12s\n" "------" "--------" "--------" "--------"
  echo "$PY_LINE" | awk -F',' '{printf "%-12s %12s %12s %12s\n","Python",$3,$4,$5}'
  echo "$CURL_LINE" | awk -F',' '{printf "%-12s %12s %12s %12s\n","Curl",$3,$4,$5}'
  echo "$AZL_LINE" | awk -F',' '{printf "%-12s %12s %12s %12s\n","AZL",$3,$4,$5}'
  echo ""
  echo "Python:  .azl/benchmark_llm_python.lat"
  echo "Curl:    .azl/benchmark_llm_curl.lat"
  echo "AZL:     .azl/benchmark_llm_azl.lat (if engine was running)"
} | tee "$REPORT"

echo ""
echo "[bench] LLM comparison saved: $REPORT"
