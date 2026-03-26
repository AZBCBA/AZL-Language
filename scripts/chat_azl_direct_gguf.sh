#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE=".azl/live_chat.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: missing $ENV_FILE (expected PORT, TOKEN, GGUF)." >&2
  exit 21
fi

PORT="$(awk -F= '/^PORT=/{print $2}' "$ENV_FILE" | tail -n1)"
TOKEN="$(awk -F= '/^TOKEN=/{print $2}' "$ENV_FILE" | tail -n1)"
GGUF="$(awk -F= '/^GGUF=/{print $2}' "$ENV_FILE" | tail -n1)"

if [[ -z "${PORT}" || -z "${TOKEN}" || -z "${GGUF}" ]]; then
  echo "ERROR: invalid $ENV_FILE (need PORT, TOKEN, GGUF)." >&2
  exit 22
fi
if [[ ! -f "${GGUF}" ]]; then
  echo "ERROR: GGUF not found: ${GGUF}" >&2
  exit 23
fi

LLAMA_CLI_BIN=""
if [[ -n "${AZL_LLAMA_CLI:-}" && -x "${AZL_LLAMA_CLI}" ]]; then
  LLAMA_CLI_BIN="${AZL_LLAMA_CLI}"
elif [[ -x "/tmp/llama-cpp-azl-verify/build-cli/bin/llama-completion" ]]; then
  LLAMA_CLI_BIN="/tmp/llama-cpp-azl-verify/build-cli/bin/llama-completion"
elif command -v llama-completion >/dev/null 2>&1; then
  LLAMA_CLI_BIN="$(command -v llama-completion)"
elif command -v llama-cli >/dev/null 2>&1; then
  LLAMA_CLI_BIN="$(command -v llama-cli)"
fi
if [[ -z "${LLAMA_CLI_BIN}" || ! -x "${LLAMA_CLI_BIN}" ]]; then
  echo "ERROR: llama CLI binary not found (need llama-completion or llama-cli on PATH, or AZL_LLAMA_CLI)." >&2
  echo "Build example:" >&2
  echo "  cmake -S /tmp/llama-cpp-azl-verify -B /tmp/llama-cpp-azl-verify/build-cli -DCMAKE_BUILD_TYPE=Release -DLLAMA_BUILD_TOOLS=ON -DLLAMA_BUILD_SERVER=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TESTS=OFF" >&2
  echo "  cmake --build /tmp/llama-cpp-azl-verify/build-cli -j\$(nproc)" >&2
  exit 24
fi

# Kill any previous listener on this port to avoid stale runtime mismatch.
OLD_PID="$(ss -ltnp 2>/dev/null | awk -v p=":${PORT}" '$4 ~ p {print $NF}' | sed -E 's/.*pid=([0-9]+).*/\1/' | head -n1 || true)"
if [[ -n "${OLD_PID}" ]]; then
  kill -KILL "${OLD_PID}" 2>/dev/null || true
  sleep 0.4
fi

export AZL_NATIVE_EXEC_CMD="${ROOT_DIR}/.azl/bin/azl-native-engine"
export AZL_BUILD_API_PORT="${PORT}"
export AZL_API_TOKEN="${TOKEN}"
export AZL_GGUF_PATH="${GGUF}"
export AZL_LLAMA_CLI="${LLAMA_CLI_BIN}"
export AZL_LLAMA_SIMPLE_IO=1

echo "Starting AZL direct GGUF server on ${PORT}..."
bash scripts/start_azl_native_mode.sh >/tmp/azl_direct_chat_start.log 2>&1

READY=0
for _ in $(seq 1 80); do
  if curl -fsS -m 1 "http://127.0.0.1:${PORT}/api/llm/capabilities" >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 0.2
done

if [[ "${READY}" != "1" ]]; then
  echo "ERROR: server did not become ready on ${PORT}." >&2
  echo "See: /tmp/azl_direct_chat_start.log" >&2
  exit 25
fi

echo "AZL direct GGUF chat is ready."
AZL_CHAT_BASE_URL="http://127.0.0.1:${PORT}" AZL_CHAT_TOKEN="${TOKEN}" bash scripts/chat_azl_session.sh
