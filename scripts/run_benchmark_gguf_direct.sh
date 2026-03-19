#!/usr/bin/env bash
# Build azl-native-engine, start it with AZL_GGUF_PATH set, then run
# scripts/benchmark_llm_gguf_direct.py (Python llama-cli vs POST /api/llm/gguf_infer).
# No Ollama — real .gguf on disk + llama.cpp llama-cli.
#
# Prerequisites:
#   - llama-cli on PATH (or AZL_LLAMA_CLI)
#   - AZL_GGUF_PATH=/path/to/model.gguf
#
# Env: LLM_BENCH_* passed through; AZL_LLAMA_SKIP_NO_CNV=1 if your llama-cli has no -no-cnv
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

GGUF="${AZL_GGUF_PATH:-}"
if [ -z "$GGUF" ] || [ ! -f "$GGUF" ]; then
  echo "ERROR: set AZL_GGUF_PATH to an existing .gguf file (local weights)." >&2
  exit 91
fi

CLI_BIN="${AZL_LLAMA_CLI:-llama-cli}"
if ! command -v "$CLI_BIN" >/dev/null 2>&1; then
  echo "ERROR: '$CLI_BIN' not found on PATH. Build llama.cpp and install llama-cli, or set AZL_LLAMA_CLI." >&2
  exit 93
fi

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
BUNDLE=".azl/tmp/gguf_bench_bundle.azl"
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
  export AZL_API_TOKEN="bench_gguf_$(openssl rand -hex 16)"
  echo "[bench-gguf] AZL_API_TOKEN generated"
fi
export AZL_BUILD_API_PORT="$PORT"
export AZL_GGUF_PATH="$GGUF"
export AZL_NATIVE_RUNTIME_CMD="$(bash scripts/azl_resolve_native_runtime_cmd.sh)"

echo "[bench-gguf] starting engine on 127.0.0.1:$PORT GGUF=$GGUF"
"$BIN" "$BUNDLE" >>.azl/native_gguf_bench_engine.log 2>&1 &
ENGINE_PID=$!

ready=0
for _ in $(seq 1 75); do
  if curl -fsS --max-time 1 "http://127.0.0.1:${PORT}/api/llm/capabilities" 2>/dev/null | grep -q '"ok":true'; then
    ready=1
    break
  fi
  sleep 0.2
done
if [ "$ready" != 1 ]; then
  echo "ERROR: engine did not respond (see .azl/native_gguf_bench_engine.log)" >&2
  exit 12
fi

export AZL_BENCH_GGUF_URL="http://127.0.0.1:${PORT}"
export AZL_BENCH_TOKEN="$AZL_API_TOKEN"
echo "[bench-gguf] running scripts/benchmark_llm_gguf_direct.py"
python3 scripts/benchmark_llm_gguf_direct.py
echo "[bench-gguf] done"
