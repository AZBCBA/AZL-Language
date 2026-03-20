#!/usr/bin/env bash
# Live HTTP checks against azl-native-engine + minimal bootstrap bundle (c_minimal_link_ping).
# This matches the stack used by native gate F and scripts/run_native_engine_llm_bench.sh.
#
# Full enterprise combined startup (scripts/start_azl_native_mode.sh) is heavier and can fail
# independently when the large interpreter slice errors; the C engine + LLM honesty API is
# what release gates need to prove here.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/azl_local_layout.sh"

TOKEN="${AZL_VERIFY_TOKEN:-azl_verify_token_2026}"
LOG_PATH="${AZL_VERIFY_LOG:-${AZL_LOGS_DIR}/verify_native_runtime.log}"

mkdir -p .azl/tmp

pick_port() {
  local p code
  while :; do
    p="$(( (RANDOM % 20000) + 30000 ))"
    code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 0.25 "http://127.0.0.1:${p}/healthz" 2>/dev/null || true)"
    case "$code" in
    000 | '') echo "$p"; return 0 ;;
    *) continue ;;
    esac
  done
}

PORT="${AZL_VERIFY_PORT:-$(pick_port)}"

cleanup() {
  if [ -n "${ENGINE_PID:-}" ] && kill -0 "$ENGINE_PID" 2>/dev/null; then
    kill -TERM "$ENGINE_PID" 2>/dev/null || true
    sleep 0.3
    kill -KILL "$ENGINE_PID" 2>/dev/null || true
    wait "$ENGINE_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

BIN="$(bash scripts/build_azl_native_engine.sh)"
COMBINED="$(realpath azl/tests/c_minimal_link_ping.azl)"
BUNDLE=".azl/tmp/verify_native_live_bundle.azl"
bash scripts/build_azl_bootstrap_bundle.sh "$COMBINED" "::boot.entry" --out "$BUNDLE"

export AZL_API_TOKEN="$TOKEN"
export AZL_BUILD_API_PORT="$PORT"
export AZL_BIND_HOST="${AZL_BIND_HOST:-127.0.0.1}"
export AZL_NATIVE_RUNTIME_CMD="$(bash scripts/azl_resolve_native_runtime_cmd.sh)"

echo "[verify] starting azl-native-engine on 127.0.0.1:${PORT} bundle=${BUNDLE}"
: >"$LOG_PATH"
"$BIN" "$BUNDLE" >>"$LOG_PATH" 2>&1 &
ENGINE_PID=$!

http_code() {
  curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://127.0.0.1:${PORT}${1}" 2>/dev/null || echo "000"
}

wait_for_engine_ready() {
  local deadline=$((SECONDS + 90))
  while [ $SECONDS -lt $deadline ]; do
    if [ "$(http_code /healthz)" = "200" ] && [ "$(http_code /readyz)" = "200" ]; then
      return 0
    fi
    sleep 0.3
  done
  return 1
}

if ! wait_for_engine_ready; then
  echo "ERROR: native engine did not reach healthz+readyz HTTP 200 within timeout"
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
# Default gate binary: gguf_in_process false + ERR_NATIVE_GGUF_NOT_IN_PROCESS (honest stub).
# Optional llama.cpp-linked binary: gguf_in_process true + gguf_embedded_llamacpp + error:null.
if echo "$CAP_JSON" | rg -q '"gguf_in_process":false'; then
  if ! echo "$CAP_JSON" | rg -q 'ERR_NATIVE_GGUF_NOT_IN_PROCESS'; then
    echo "ERROR: /api/llm/capabilities missing ERR_NATIVE_GGUF_NOT_IN_PROCESS (stub build): ${CAP_JSON}"
    exit 77
  fi
elif echo "$CAP_JSON" | rg -q '"gguf_in_process":true'; then
  if ! echo "$CAP_JSON" | rg -q '"gguf_embedded_llamacpp":true'; then
    echo "ERROR: /api/llm/capabilities expected gguf_embedded_llamacpp when gguf_in_process true: ${CAP_JSON}"
    exit 76
  fi
  if ! echo "$CAP_JSON" | rg -q '"error":null'; then
    echo "ERROR: /api/llm/capabilities expected error:null for embedded llama.cpp build: ${CAP_JSON}"
    exit 77
  fi
else
  echo "ERROR: /api/llm/capabilities missing valid gguf_in_process boolean: ${CAP_JSON}"
  exit 76
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
