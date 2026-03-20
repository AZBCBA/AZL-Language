#!/usr/bin/env bash
# Start llama.cpp llama-server (model loaded once), then azl-native-engine with
# AZL_LLAMA_SERVER_URL, then benchmark_llm_llama_server.py (direct vs /api/llm/llama_server/completion).
#
# Requires:
#   AZL_GGUF_PATH — path to .gguf
#   llama-server on PATH, or LLAMA_SERVER_BIN
#
# Env: LLM_BENCH_*; optional AZL_LLAMA_SERVER_PORT / AZL_BENCH_NATIVE_PORT
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/azl_local_layout.sh"

GGUF="${AZL_GGUF_PATH:-}"
if [ -z "$GGUF" ] || [ ! -f "$GGUF" ]; then
  echo "ERROR: set AZL_GGUF_PATH to an existing .gguf file." >&2
  exit 91
fi

if [ -n "${LLAMA_SERVER_BIN:-}" ] && [ -x "$LLAMA_SERVER_BIN" ]; then
  LS_BIN="$LLAMA_SERVER_BIN"
elif command -v llama-server >/dev/null 2>&1; then
  LS_BIN="$(command -v llama-server)"
else
  echo "ERROR: llama-server not found. Set LLAMA_SERVER_BIN to the built binary or install on PATH." >&2
  echo "  Build: cmake -S llama.cpp -B build -DLLAMA_BUILD_SERVER=ON && cmake --build build --target llama-server" >&2
  exit 93
fi

pick_two_ephemeral_ports() {
  python3 - <<'PY'
import socket
s1 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s1.bind(("127.0.0.1", 0))
p1 = s1.getsockname()[1]
s2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s2.bind(("127.0.0.1", 0))
p2 = s2.getsockname()[1]
print(p1)
print(p2)
s1.close()
s2.close()
PY
}

LL_PORT="${AZL_LLAMA_SERVER_PORT:-}"
AZ_PORT="${AZL_BENCH_NATIVE_PORT:-}"
if [ -z "$LL_PORT" ] || [ -z "$AZ_PORT" ]; then
  readarray -t _ports < <(pick_two_ephemeral_ports)
  if [ "${#_ports[@]}" -lt 2 ]; then
    echo "ERROR: could not pick two free ports" >&2
    exit 11
  fi
  [ -z "$LL_PORT" ] && LL_PORT="${_ports[0]}"
  [ -z "$AZ_PORT" ] && AZ_PORT="${_ports[1]}"
fi
if [ -z "$LL_PORT" ] || [ -z "$AZ_PORT" ] || [ "$LL_PORT" = "$AZ_PORT" ]; then
  echo "ERROR: invalid ports LL=$LL_PORT AZ=$AZ_PORT" >&2
  exit 11
fi

cleanup() {
  if [ -n "${LS_PID:-}" ] && kill -0 "$LS_PID" 2>/dev/null; then
    kill -TERM "$LS_PID" 2>/dev/null || true
    wait "$LS_PID" 2>/dev/null || true
  fi
  if [ -n "${ENGINE_PID:-}" ] && kill -0 "$ENGINE_PID" 2>/dev/null; then
    kill -TERM "$ENGINE_PID" 2>/dev/null || true
    sleep 0.3
    kill -KILL "$ENGINE_PID" 2>/dev/null || true
    wait "$ENGINE_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

mkdir -p .azl
echo "[bench-llama-srv] starting llama-server on 127.0.0.1:$LL_PORT model=$GGUF"
"$LS_BIN" -m "$GGUF" --host 127.0.0.1 --port "$LL_PORT" >>"${AZL_LOGS_DIR}/llama_server_bench.log" 2>&1 &
LS_PID=$!

ready_ls=0
for _ in $(seq 1 240); do
  if curl -fsS --max-time 2 "http://127.0.0.1:${LL_PORT}/health" >/dev/null 2>&1; then
    ready_ls=1
    break
  fi
  sleep 0.5
done
if [ "$ready_ls" != 1 ]; then
  echo "ERROR: llama-server not healthy on :$LL_PORT (see ${AZL_LOGS_DIR}/llama_server_bench.log)" >&2
  exit 12
fi
echo "[bench-llama-srv] llama-server healthy"

BIN="$(bash scripts/build_azl_native_engine.sh)"
COMBINED="$(realpath azl/tests/c_minimal_link_ping.azl)"
BUNDLE=".azl/tmp/llama_srv_bench_bundle.azl"
bash scripts/build_azl_bootstrap_bundle.sh "$COMBINED" "::boot.entry" --out "$BUNDLE"

if [ -z "${AZL_API_TOKEN:-}" ]; then
  export AZL_API_TOKEN="bench_llsrv_$(openssl rand -hex 16)"
fi
export AZL_BUILD_API_PORT="$AZ_PORT"
export AZL_LLAMA_SERVER_URL="http://127.0.0.1:${LL_PORT}"
export AZL_NATIVE_RUNTIME_CMD="$(bash scripts/azl_resolve_native_runtime_cmd.sh)"

echo "[bench-llama-srv] starting azl-native-engine on 127.0.0.1:$AZ_PORT"
"$BIN" "$BUNDLE" >>"${AZL_LOGS_DIR}/native_llama_srv_bench.log" 2>&1 &
ENGINE_PID=$!

ready_az=0
for _ in $(seq 1 75); do
  if curl -fsS --max-time 1 "http://127.0.0.1:${AZ_PORT}/api/llm/capabilities" 2>/dev/null | grep -q '"ok":true'; then
    ready_az=1
    break
  fi
  sleep 0.2
done
if [ "$ready_az" != 1 ]; then
  echo "ERROR: native engine not up on :$AZ_PORT (see ${AZL_LOGS_DIR}/native_llama_srv_bench.log)" >&2
  exit 13
fi

export AZL_BENCH_ENGINE_URL="http://127.0.0.1:${AZ_PORT}"
export AZL_BENCH_TOKEN="$AZL_API_TOKEN"
echo "[bench-llama-srv] running scripts/benchmark_llm_llama_server.py"
python3 scripts/benchmark_llm_llama_server.py
echo "[bench-llama-srv] done"
