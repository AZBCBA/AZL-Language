#!/usr/bin/env bash
# Proof: N identical requests — Python direct to Ollama vs AZL native POST /api/ollama/generate.
# Default N=1000 each. Report: .azl/benchmarks/proof_llm_python_vs_azl_*.md (via AZL_BENCHMARKS_DIR)
#
# Requires: ollama serve + model (default LLM_BENCH_MODEL=llama3.2:1b)
#
# Env (optional):
#   PROOF_REQS LLM_BENCH_NUM_PREDICT LLM_BENCH_PROMPT LLM_BENCH_MODEL PROOF_WARMUP
#   OLLAMA_HOST  AZL_BENCH_NATIVE_PORT / AZL_BUILD_API_PORT  AZL_API_TOKEN
#
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/azl_local_layout.sh"

pick_free_port() {
  python3 - <<'PY'
import socket
for port in range(18080, 18150):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.bind(("127.0.0.1", port))
        print(port)
        break
    except OSError:
        pass
    finally:
        s.close()
PY
}

cleanup() {
  if [ -n "${ENGINE_PID:-}" ] && kill -0 "$ENGINE_PID" 2>/dev/null; then
    kill -TERM "$ENGINE_PID" 2>/dev/null || true
    sleep 0.4
    kill -KILL "$ENGINE_PID" 2>/dev/null || true
    wait "$ENGINE_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

BIN="$(bash scripts/build_azl_native_engine.sh)"
mkdir -p .azl/tmp
COMBINED="$(realpath azl/tests/c_minimal_link_ping.azl)"
BUNDLE=".azl/tmp/llm_bench_bundle.azl"
bash scripts/build_azl_bootstrap_bundle.sh "$COMBINED" "::boot.entry" --out "$BUNDLE"

PORT="${AZL_BENCH_NATIVE_PORT:-${AZL_BUILD_API_PORT:-}}"
if [ -z "$PORT" ]; then
  PORT="$(pick_free_port)"
fi
if [ -z "$PORT" ]; then
  echo "ERROR: no free TCP port in 18080–18149" >&2
  exit 11
fi

if [ -z "${AZL_API_TOKEN:-}" ]; then
  export AZL_API_TOKEN="proof_llm_$(openssl rand -hex 16)"
  echo "[proof] AZL_API_TOKEN generated for this run."
fi
export AZL_BUILD_API_PORT="$PORT"
export AZL_NATIVE_RUNTIME_CMD="$(bash scripts/azl_resolve_native_runtime_cmd.sh)"

echo "[proof] starting $BIN on 127.0.0.1:$PORT"
"$BIN" "$BUNDLE" >>.azl/native_proof_llm_engine.log 2>&1 &
ENGINE_PID=$!

ready=0
for _ in $(seq 1 75); do
  if curl -fsS --max-time 1 "http://127.0.0.1:${PORT}/api/llm/capabilities" 2>/dev/null | grep -q '"ollama_http_proxy":true'; then
    ready=1
    break
  fi
  sleep 0.2
done
if [ "$ready" != 1 ]; then
  echo "ERROR: native engine did not expose /api/llm/capabilities (see ${AZL_LOGS_DIR}/native_proof_llm_engine.log)" >&2
  exit 12
fi

export AZL_BASE_URL="http://127.0.0.1:${PORT}"
export PROOF_REQS="${PROOF_REQS:-1000}"
export PROOF_WARMUP="${PROOF_WARMUP:-5}"

echo "[proof] PROOF_REQS=$PROOF_REQS PROOF_WARMUP=$PROOF_WARMUP LLM_BENCH_NUM_PREDICT=${LLM_BENCH_NUM_PREDICT:-16}"
python3 scripts/proof_llm_python_vs_azl.py
echo "[proof] done"
