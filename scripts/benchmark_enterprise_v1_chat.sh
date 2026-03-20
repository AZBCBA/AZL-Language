#!/usr/bin/env bash
# Latency benchmark: enterprise AZL HTTP stack POST /v1/chat (azl/system/http_server.azl).
# This is NOT the C native engine Ollama proxy (/api/ollama/generate).
#
# Requires:
#   - Enterprise daemon listening (e.g. scripts/run_enterprise_daemon.sh)
#   - AZL_API_TOKEN matching the daemon (Bearer auth)
#
# Env:
#   AZL_ENTERPRISE_PORT  — default 8080
#   AZL_API_TOKEN        — required (no placeholder token)
#   LLM_BENCH_REQS       — default 10
#   LLM_BENCH_PROMPT     — plain-text body sent as the chat message
#
# Optional: .azl/local_api_token — first line used as AZL_API_TOKEN if env unset (.azl/ is gitignored).
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/azl_local_layout.sh"

PORT="${AZL_ENTERPRISE_PORT:-8080}"
REQS="${LLM_BENCH_REQS:-10}"
PROMPT="${LLM_BENCH_PROMPT:-Say hello in one word.}"
mkdir -p "$AZL_BENCHMARKS_DIR"

if [ -z "${AZL_API_TOKEN:-}" ] && [ -f .azl/local_api_token ]; then
  export AZL_API_TOKEN="$(head -1 .azl/local_api_token | tr -d '\r\n')"
  echo "[bench] AZL_API_TOKEN loaded from .azl/local_api_token"
fi

if [ -z "${AZL_API_TOKEN:-}" ]; then
  echo "ERROR: AZL_API_TOKEN is required (Bearer for /v1/chat)." >&2
  echo "  Example: AZL_API_TOKEN=\$AZL_API_TOKEN bash scripts/benchmark_enterprise_v1_chat.sh" >&2
  exit 2
fi

if ! curl -fsS --max-time 3 "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
  echo "ERROR: nothing answered healthz on 127.0.0.1:${PORT}. Start: bash scripts/run_enterprise_daemon.sh" >&2
  exit 91
fi

HZ="$(curl -fsS --max-time 3 "http://127.0.0.1:${PORT}/healthz" 2>/dev/null || true)"
# C native engine healthz uses ok:true + service azl-native-engine — wrong surface for this bench
if echo "$HZ" | grep -q '"ok":true' && echo "$HZ" | grep -q 'azl-native-engine'; then
  echo "ERROR: port ${PORT} looks like the C native engine (healthz is azl-native-engine)." >&2
  echo "  For Ollama via C proxy use: bash scripts/run_native_engine_llm_bench.sh" >&2
  echo "  Or: bash scripts/benchmark_llm_ollama.sh with AZL_BENCH_PORT / AZL_BENCH_TOKEN" >&2
  exit 93
fi

if curl -fsS --max-time 2 "http://127.0.0.1:${PORT}/api/llm/capabilities" 2>/dev/null | grep -q '"ollama_http_proxy":true'; then
  echo "ERROR: port ${PORT} exposes C native GET /api/llm/capabilities; this script targets enterprise POST /v1/chat only." >&2
  exit 93
fi

# Route must exist (401 with bad token is OK; 404 means not enterprise http_server.azl)
probe="$(curl -sS -o /dev/null -w "%{http_code}" -m 5 -X POST \
  -H "Authorization: Bearer __invalid_probe__" \
  -H "Content-Type: text/plain; charset=utf-8" \
  --data-binary "ping" \
  "http://127.0.0.1:${PORT}/v1/chat" 2>/dev/null || echo "000")"
if [ "$probe" = "404" ]; then
  echo "ERROR: POST /v1/chat returned 404 on 127.0.0.1:${PORT}." >&2
  echo "  Nothing is serving the enterprise HTTP routes (see azl/system/http_server.azl)." >&2
  echo "  Start: bash scripts/run_enterprise_daemon.sh  (check AZL_BUILD_API_PORT matches AZL_ENTERPRISE_PORT)" >&2
  exit 95
fi

echo "=== Enterprise /v1/chat benchmark ==="
echo "  PORT=$PORT REQS=$REQS"
echo ""

: > "${AZL_BENCHMARKS_DIR}/benchmark_enterprise_v1_chat.lat"
ok=0
fail=0
for i in $(seq 1 "$REQS"); do
  start_ns="$(date +%s%N)"
  code=0
  curl -sfS -m 120 -X POST \
    -H "Authorization: Bearer ${AZL_API_TOKEN}" \
    -H "Content-Type: text/plain; charset=utf-8" \
    --data-binary "$PROMPT" \
    "http://127.0.0.1:${PORT}/v1/chat" -o /dev/null || code=$?
  end_ns="$(date +%s%N)"
  dur_us=$(( (end_ns - start_ns) / 1000 ))
  if [ "$code" -eq 0 ]; then
    echo "chat,$dur_us" >> "${AZL_BENCHMARKS_DIR}/benchmark_enterprise_v1_chat.lat"
    ok=$((ok + 1))
  else
    echo "chat_fail,$dur_us" >> "${AZL_BENCHMARKS_DIR}/benchmark_enterprise_v1_chat.lat"
    fail=$((fail + 1))
  fi
done

summary() {
  local tmp
  tmp="$(mktemp)"
  awk -F',' '$1=="chat"{print $2}' "${AZL_BENCHMARKS_DIR}/benchmark_enterprise_v1_chat.lat" | sort -n > "$tmp"
  local n
  n="$(wc -l < "$tmp" | tr -d ' ')"
  if [ "$n" -eq 0 ]; then echo "chat,0,0,0,0"; rm -f "$tmp"; return; fi
  local mean p50 p95
  mean="$(awk '{sum+=$1} END{printf "%.2f", sum/NR}' "$tmp")"
  p50="$(sed -n "$(( (n * 50 + 99) / 100 ))p" "$tmp")"
  p95="$(sed -n "$(( (n * 95 + 99) / 100 ))p" "$tmp")"
  [ -z "$p50" ] && p50=0
  [ -z "$p95" ] && p95=0
  rm -f "$tmp"
  echo "chat,$n,$mean,$p50,$p95"
}

LINE="$(summary)"
REPORT="${AZL_BENCHMARKS_DIR}/benchmark_enterprise_v1_chat_$(date +%Y%m%d_%H%M%S).txt"
{
  echo "=============================================="
  echo "  Enterprise POST /v1/chat latency"
  echo "  http://127.0.0.1:${PORT}/v1/chat"
  echo "  Requests ok=$ok fail=$fail | Unit: microseconds (us)"
  echo "=============================================="
  echo ""
  printf "%-20s %12s %12s %12s\n" "Path" "mean(us)" "p50(us)" "p95(us)"
  printf "%-20s %12s %12s %12s\n" "----" "--------" "--------" "--------"
  echo "$LINE" | awk -F',' '{printf "%-20s %12s %12s %12s\n","/v1/chat",$3,$4,$5}'
  echo ""
  echo "Raw: ${AZL_BENCHMARKS_DIR}/benchmark_enterprise_v1_chat.lat"
} | tee "$REPORT"

echo ""
echo "[bench] saved: $REPORT"
if [ "$fail" -gt 0 ]; then
  echo "ERROR: $fail request(s) failed (401 wrong token, 404 route, or daemon not serving http_server)." >&2
  exit 94
fi
