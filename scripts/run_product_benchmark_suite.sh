#!/usr/bin/env bash
# Product / ops: run LLM-related benchmarks in a safe order.
# 1) C native engine + Ollama (starts ephemeral engine; needs ollama serve + model).
# 2) Enterprise POST /v1/chat only if AZL_API_TOKEN is set (daemon on AZL_ENTERPRISE_PORT).
#
# Env: LLM_BENCH_REQS, LLM_BENCH_MODEL, LLM_BENCH_PROMPT, OLLAMA_HOST, AZL_ENTERPRISE_PORT
# Optional: if AZL_API_TOKEN is unset, first line of .azl/local_api_token is used (gitignored dir).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [ -z "${AZL_API_TOKEN:-}" ] && [ -f .azl/local_api_token ]; then
  export AZL_API_TOKEN="$(head -1 .azl/local_api_token | tr -d '\r\n')"
  echo "[suite] AZL_API_TOKEN loaded from .azl/local_api_token"
fi

REQS="${LLM_BENCH_REQS:-10}"
export LLM_BENCH_REQS="$REQS"

echo "=== Product benchmark suite ==="
echo "  LLM_BENCH_REQS=$REQS LLM_BENCH_MODEL=${LLM_BENCH_MODEL:-llama3.2:1b}"
echo ""

echo "[suite 1/2] Native engine + Ollama (run_native_engine_llm_bench.sh)"
bash scripts/run_native_engine_llm_bench.sh

echo ""
if [ -n "${AZL_API_TOKEN:-}" ]; then
  echo "[suite 2/2] Enterprise POST /v1/chat (benchmark_enterprise_v1_chat.sh)"
  bash scripts/benchmark_enterprise_v1_chat.sh
else
  echo "[suite 2/2] SKIP enterprise /v1/chat — set AZL_API_TOKEN (and run enterprise daemon on AZL_ENTERPRISE_PORT, default 8080)"
fi

echo ""
echo "product-benchmark-suite-done"
