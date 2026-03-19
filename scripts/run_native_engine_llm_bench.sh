#!/usr/bin/env bash
# Build azl-native-engine, start it on a free localhost port with a minimal bootstrap bundle,
# wait for GET /api/llm/capabilities, then run scripts/benchmark_llm_ollama.sh (Python/Curl/AZL proxy).
#
# Requires: Ollama (ollama serve) and a pulled model (default LLM_BENCH_MODEL=llama3.2:1b).
#
# Env:
#   AZL_API_TOKEN       — if unset, a random token is generated and used for engine + bench
#   AZL_BENCH_NATIVE_PORT / AZL_BUILD_API_PORT — force port (default: first free 18080–18149)
#   LLM_BENCH_*         — passed through to benchmark_llm_ollama.sh
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

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
  export AZL_API_TOKEN="bench_llm_$(openssl rand -hex 16)"
  echo "[bench-native] AZL_API_TOKEN generated (export AZL_BENCH_TOKEN to reuse for a manual curl)."
fi
export AZL_BUILD_API_PORT="$PORT"
export AZL_NATIVE_RUNTIME_CMD="$(bash scripts/azl_resolve_native_runtime_cmd.sh)"

echo "[bench-native] starting $BIN on 127.0.0.1:$PORT (bundle=$BUNDLE)"
"$BIN" "$BUNDLE" >>.azl/native_llm_bench_engine.log 2>&1 &
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
  echo "ERROR: native engine did not expose /api/llm/capabilities in time (see .azl/native_llm_bench_engine.log)" >&2
  exit 12
fi

export AZL_BENCH_PORT="$PORT"
export AZL_BENCH_TOKEN="$AZL_API_TOKEN"
echo "[bench-native] running scripts/benchmark_llm_ollama.sh (AZL_BENCH_PORT=$AZL_BENCH_PORT)"
bash scripts/benchmark_llm_ollama.sh
echo "[bench-native] done"
