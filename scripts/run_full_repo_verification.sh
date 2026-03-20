#!/usr/bin/env bash
# One-shot: RELEASE_READY gate order + full test suite + optional product benches.
#
# Release block (must all exit 0):
#   1) enforce_canonical_stack
#   2) check_azl_native_gates  (includes gate H — P0 tokenizer + brace balance)
#   3) enforce_legacy_entrypoint_blocklist
#   4) verify_native_runtime_live  (minimal bundle — fast C-engine HTTP contract before long suite)
#   5) run_all_tests  (scripts/run_tests.sh includes enterprise HTTP + qlha3 + grammar; see run_tests.sh)
#
# Optional tail (does not fail the script if skipped):
#   If Ollama is up: LLM_BENCH_REQS=3 run_native_engine_llm_bench.sh
#   If AZL_API_TOKEN or .azl/local_api_token and POST /v1/chat != 404:
#     LLM_BENCH_REQS=3 benchmark_enterprise_v1_chat.sh
#
# Force-skip optional benches: RUN_OPTIONAL_BENCHES=0 (default is 1).
#
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "=============================================="
echo "  Full repo verification (RELEASE_READY + tests)"
echo "=============================================="

echo "[1/5] enforce_canonical_stack.sh"
bash scripts/enforce_canonical_stack.sh

echo "[2/5] check_azl_native_gates.sh"
bash scripts/check_azl_native_gates.sh

echo "[3/5] enforce_legacy_entrypoint_blocklist.sh"
bash scripts/enforce_legacy_entrypoint_blocklist.sh

echo "[4/5] verify_native_runtime_live.sh"
bash scripts/verify_native_runtime_live.sh

echo "[5/5] run_all_tests.sh"
bash scripts/run_all_tests.sh

echo ""
echo "=============================================="
echo "  Release block: OK"
echo "=============================================="

OPT="${RUN_OPTIONAL_BENCHES:-1}"
if [ "$OPT" != "1" ]; then
  echo "[optional] RUN_OPTIONAL_BENCHES=$OPT — skipping product benches"
  echo "full-repo-verification-done"
  exit 0
fi

echo ""
echo "=== Optional product benches (best effort) ==="

if curl -sf --max-time 3 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  echo "[optional] Ollama reachable — native engine LLM bench (3 reqs)"
  LLM_BENCH_REQS=3 bash scripts/run_native_engine_llm_bench.sh
else
  echo "[optional] SKIP native LLM bench — Ollama not at 127.0.0.1:11434"
fi

if [ -z "${AZL_API_TOKEN:-}" ] && [ -f .azl/local_api_token ]; then
  export AZL_API_TOKEN="$(head -1 .azl/local_api_token | tr -d '\r\n')"
fi

PORT="${AZL_ENTERPRISE_PORT:-8080}"
if [ -n "${AZL_API_TOKEN:-}" ]; then
  code="$(curl -sS -o /dev/null -w "%{http_code}" -m 5 -X POST \
    -H "Authorization: Bearer __probe__" \
    -H "Content-Type: text/plain; charset=utf-8" \
    --data-binary "ping" \
    "http://127.0.0.1:${PORT}/v1/chat" 2>/dev/null || echo "000")"
  if [ "$code" = "404" ] || [ "$code" = "000" ]; then
    echo "[optional] SKIP enterprise /v1/chat — no route or unreachable (http=$code on port $PORT)"
  else
    echo "[optional] Enterprise /v1/chat probe http=$code — bench (3 reqs)"
    LLM_BENCH_REQS=3 bash scripts/benchmark_enterprise_v1_chat.sh
  fi
else
  echo "[optional] SKIP enterprise /v1/chat — no AZL_API_TOKEN or .azl/local_api_token"
fi

echo ""
echo "full-repo-verification-done"
