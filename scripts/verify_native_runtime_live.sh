#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

TOKEN="${AZL_VERIFY_TOKEN:-azl_verify_token_2026}"
LOG_PATH="${AZL_VERIFY_LOG:-.azl/verify_native_runtime.log}"

mkdir -p .azl

pick_port() {
  local p
  while :; do
    p="$(( (RANDOM % 20000) + 30000 ))"
    if ! curl -fsS "http://127.0.0.1:${p}/healthz" >/dev/null 2>&1; then
      echo "$p"
      return 0
    fi
  done
}

PORT="${AZL_VERIFY_PORT:-$(pick_port)}"

echo "[verify] starting native mode on 127.0.0.1:${PORT}"
AZL_API_TOKEN="$TOKEN" \
AZL_BUILD_API_PORT="$PORT" \
AZL_BIND_HOST="127.0.0.1" \
bash scripts/start_azl_native_mode.sh >"$LOG_PATH" 2>&1 &

wait_for_health() {
  local deadline=$((SECONDS + 30))
  while [ $SECONDS -lt $deadline ]; do
    if curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

if ! wait_for_health; then
  echo "ERROR: native engine did not become healthy within timeout"
  echo "See log: ${LOG_PATH}"
  exit 70
fi

HEALTH_JSON="$(curl -fsS "http://127.0.0.1:${PORT}/healthz")"
READY_JSON="$(curl -fsS "http://127.0.0.1:${PORT}/readyz")"
STATUS_JSON="$(curl -fsS "http://127.0.0.1:${PORT}/status")"
EXEC_JSON="$(curl -fsS -H "Authorization: Bearer ${TOKEN}" "http://127.0.0.1:${PORT}/api/exec_state")"

if ! echo "$HEALTH_JSON" | rg -q '"ok":true'; then
  echo "ERROR: healthz not ok: ${HEALTH_JSON}"
  exit 71
fi
if ! echo "$READY_JSON" | rg -q '"status":"ready"'; then
  echo "ERROR: readyz not ready: ${READY_JSON}"
  exit 71
fi
if ! echo "$STATUS_JSON" | rg -q '"running":true'; then
  echo "ERROR: status runtime not running: ${STATUS_JSON}"
  exit 71
fi
if ! echo "$EXEC_JSON" | rg -q '"running":true'; then
  echo "ERROR: exec_state runtime not running: ${EXEC_JSON}"
  exit 71
fi

CAP_JSON="$(curl -fsS "http://127.0.0.1:${PORT}/api/llm/capabilities")"
if ! echo "$CAP_JSON" | rg -q '"ok":true'; then
  echo "ERROR: /api/llm/capabilities not ok: ${CAP_JSON}"
  exit 74
fi
if ! echo "$CAP_JSON" | rg -q '"ollama_http_proxy":true'; then
  echo "ERROR: /api/llm/capabilities missing ollama_http_proxy: ${CAP_JSON}"
  exit 75
fi
if ! echo "$CAP_JSON" | rg -q '"gguf_in_process":false'; then
  echo "ERROR: /api/llm/capabilities expected gguf_in_process false until native GGUF exists: ${CAP_JSON}"
  exit 76
fi
if ! echo "$CAP_JSON" | rg -q 'ERR_NATIVE_GGUF_NOT_IN_PROCESS'; then
  echo "ERROR: /api/llm/capabilities missing ERR_NATIVE_GGUF_NOT_IN_PROCESS: ${CAP_JSON}"
  exit 77
fi

echo "live-native-api-ok"

set +e
AZL_NATIVE_ONLY=1 bash scripts/azl run smoke_test.azl >/tmp/azl_verify_block_runner.out 2>&1
runner_rc=$?
set -e

if [ "$runner_rc" -ne 64 ]; then
  echo "ERROR: scripts/azl run was not blocked in native-only mode (rc=$runner_rc)"
  exit 72
fi

echo "[verify] success"
echo "  port: ${PORT}"
echo "  token: ${TOKEN}"
echo "  healthz: ${HEALTH_JSON}"
echo "  readyz: ${READY_JSON}"
echo "  status: ${STATUS_JSON}"
echo "  api/exec_state: ${EXEC_JSON}"
echo "  api/llm/capabilities: ${CAP_JSON}"
