#!/usr/bin/env bash
# Start azl-native-engine with local .gguf and open an interactive terminal chat
# (POST /api/llm/chat_session — same stack as benchmarks, with conversation memory).
#
# Usage:
#   bash scripts/azl_gguf_terminal_chat.sh
#   AZL_GGUF_PATH=/path/to/model.gguf bash scripts/azl_gguf_terminal_chat.sh
#   AZL_LLAMA_CLI=/path/to/llama-cli AZL_GGUF_PATH=... bash scripts/azl_gguf_terminal_chat.sh
#
# In the chat: type your message, Enter.  /exit or /quit  to stop.  /reset  to clear history.
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/azl_local_layout.sh"

GGUF="${AZL_GGUF_PATH:-}"
if [ -z "$GGUF" ]; then
  DEF="$ROOT_DIR/.azl/tmp/bench_tinyllama.Q4_K_M.gguf"
  if [ -f "$DEF" ]; then
    GGUF="$DEF"
    echo "[azl-chat] Using default GGUF: $GGUF"
  else
    echo "ERROR: set AZL_GGUF_PATH to your .gguf file (or download TinyLlama into .azl/tmp/ — see scripts/run_benchmark_gguf_direct.sh)." >&2
    exit 91
  fi
fi
if [ ! -f "$GGUF" ]; then
  echo "ERROR: not a file: $GGUF" >&2
  exit 92
fi

if [ -z "${AZL_LLAMA_CLI:-}" ] && [ -x "/tmp/azl_llama_cpp_cli/build/bin/llama-cli" ]; then
  export AZL_LLAMA_CLI="/tmp/azl_llama_cpp_cli/build/bin/llama-cli"
fi
CLI_USE="${AZL_LLAMA_CLI:-llama-cli}"
if command -v "$CLI_USE" >/dev/null 2>&1 || [ -x "$CLI_USE" ]; then
  export AZL_LLAMA_CLI="$CLI_USE"
else
  echo "ERROR: llama-cli not found (install llama.cpp or set AZL_LLAMA_CLI)." >&2
  exit 93
fi

pick_free_port() {
  python3 - <<'PY'
import socket
for port in range(18080, 18250):
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
BUNDLE=".azl/tmp/gguf_chat_bundle.azl"
bash scripts/build_azl_bootstrap_bundle.sh "$COMBINED" "::boot.entry" --out "$BUNDLE"

PORT="${AZL_BENCH_NATIVE_PORT:-${AZL_BUILD_API_PORT:-}}"
if [ -z "$PORT" ]; then
  PORT="$(pick_free_port)"
fi
if [ -z "$PORT" ]; then
  echo "ERROR: no free TCP port in 18080–18249" >&2
  exit 11
fi

if [ -z "${AZL_API_TOKEN:-}" ]; then
  export AZL_API_TOKEN="azl_gguf_chat_$(openssl rand -hex 12)"
fi
export AZL_BUILD_API_PORT="$PORT"
export AZL_GGUF_PATH="$GGUF"
export AZL_LLAMA_SIMPLE_IO="${AZL_LLAMA_SIMPLE_IO:-1}"
export AZL_NATIVE_RUNTIME_CMD="$(bash scripts/azl_resolve_native_runtime_cmd.sh)"

echo "[azl-chat] Starting engine on 127.0.0.1:$PORT"
echo "[azl-chat] GGUF=$GGUF"
"$BIN" "$BUNDLE" >>"${AZL_LOGS_DIR}/native_gguf_chat_engine.log" 2>&1 &
ENGINE_PID=$!

ready=0
for _ in $(seq 1 90); do
  if curl -fsS --max-time 1 "http://127.0.0.1:${PORT}/api/llm/capabilities" 2>/dev/null | grep -q '"ok":true'; then
    ready=1
    break
  fi
  sleep 0.2
done
if [ "$ready" != 1 ]; then
  echo "ERROR: engine did not become ready (log: ${AZL_LOGS_DIR}/native_gguf_chat_engine.log)" >&2
  exit 12
fi

export AZL_CHAT_BASE_URL="http://127.0.0.1:${PORT}"
export AZL_CHAT_TOKEN="$AZL_API_TOKEN"
echo ""
exec bash "$ROOT_DIR/scripts/chat_azl_session.sh"
