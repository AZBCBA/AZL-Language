#!/usr/bin/env bash
# One-shot: RELEASE_READY gate order + full test suite + optional product benches.
#
# Release block (must all exit 0):
#   0) verify_documentation_pieces.sh --promoted-only  (manifest: release/doc_verification_pieces.json)
#   1) enforce_canonical_stack
#   2) check_azl_native_gates  (gate 0: self_check_release_helpers + jq/manifest; includes gate H — P0 tokenizer + brace balance)
#   3) verify_azl_interpreter_semantic_spine_smoke  (Tier B P0.1: real azl_interpreter.azl + stub ::azl.security on Python spine; init only)
#   4) verify_azl_interpreter_semantic_spine_behavior_smoke  (Tier B P0.1c: stub + behavior-entry harness + interpreter; six emit interpret + cache hits + multi-line say depth + AZL_S6_ONLY; ERROR_SYSTEM 548–561)
#   5) enforce_legacy_entrypoint_blocklist
#   6) verify_native_runtime_live  (minimal bundle — fast C-engine HTTP contract before long suite)
#   7) run_all_tests  (scripts/run_tests.sh includes enterprise HTTP + qlha3 + grammar; see run_tests.sh)
#
# Optional tail (skips are non-fatal; if a bench runs, its non-zero exit fails this script):
#   If Ollama is up: LLM_BENCH_REQS=3 run_native_engine_llm_bench.sh
#   If AZL_API_TOKEN or .azl/local_api_token and POST /v1/chat != 404:
#     LLM_BENCH_REQS=3 benchmark_enterprise_v1_chat.sh (**ERROR[AZL_ENTERPRISE_V1_CHAT_BENCH]**, exits **2** / **91** / **93** / **94** / **95** — docs/ERROR_SYSTEM.md)
#
# Force-skip optional benches: RUN_OPTIONAL_BENCHES=0 (default is 1).
#
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "=============================================="
echo "  Full repo verification (RELEASE_READY + tests)"
echo "=============================================="

echo "[0/8] verify_documentation_pieces.sh --promoted-only"
bash scripts/verify_documentation_pieces.sh --promoted-only

echo "[1/8] enforce_canonical_stack.sh"
bash scripts/enforce_canonical_stack.sh

echo "[2/8] check_azl_native_gates.sh"
bash scripts/check_azl_native_gates.sh

echo "[3/8] verify_azl_interpreter_semantic_spine_smoke.sh"
bash scripts/verify_azl_interpreter_semantic_spine_smoke.sh

echo "[4/8] verify_azl_interpreter_semantic_spine_behavior_smoke.sh"
bash scripts/verify_azl_interpreter_semantic_spine_behavior_smoke.sh

echo "[5/8] enforce_legacy_entrypoint_blocklist.sh"
bash scripts/enforce_legacy_entrypoint_blocklist.sh

echo "[6/8] verify_native_runtime_live.sh"
bash scripts/verify_native_runtime_live.sh

echo "[7/8] run_all_tests.sh"
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
    echo "[optional] SKIP enterprise /v1/chat — probe http=$code on 127.0.0.1:${PORT} (need enterprise daemon: bash scripts/run_enterprise_daemon.sh; match AZL_BUILD_API_PORT and AZL_ENTERPRISE_PORT)"
  else
    echo "[optional] Enterprise /v1/chat probe http=$code — benchmark_enterprise_v1_chat.sh (3 reqs; **ERROR[AZL_ENTERPRISE_V1_CHAT_BENCH]** — docs/ERROR_SYSTEM.md)"
    LLM_BENCH_REQS=3 bash scripts/benchmark_enterprise_v1_chat.sh
  fi
else
  echo "[optional] SKIP enterprise /v1/chat — set AZL_API_TOKEN or create .azl/local_api_token (first line, chmod 600); see docs/ERROR_SYSTEM.md (enterprise bench exit **2**)"
fi

echo ""
echo "full-repo-verification-done"
