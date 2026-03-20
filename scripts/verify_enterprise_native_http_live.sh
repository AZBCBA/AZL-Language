#!/usr/bin/env bash
# Live HTTP checks: azl-native-engine + enterprise combined bundle (same component list as
# scripts/build_enterprise_combined.sh / run_enterprise_daemon.sh), entry ::build.daemon.enterprise.
# Proves the full native enterprise graph reaches the same C-engine HTTP contract as
# scripts/verify_native_runtime_live.sh (minimal bundle), without optional Ollama/enterprise chat.
#
# Env:
#   AZL_VERIFY_TOKEN — bearer token (default: azl_verify_token_2026)
#   AZL_VERIFY_PORT — fixed port; otherwise random high port
#   AZL_ENTERPRISE_VERIFY_DEADLINE_SEC — wait for healthz+readyz (default: 240)
#   AZL_VERIFY_ENTERPRISE_LOG — log path (default: ${AZL_LOGS_DIR}/verify_enterprise_native_http.log)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/azl_local_layout.sh"

TOKEN="${AZL_VERIFY_TOKEN:-azl_verify_token_2026}"
LOG_PATH="${AZL_VERIFY_ENTERPRISE_LOG:-${AZL_LOGS_DIR}/verify_enterprise_native_http.log}"
DEADLINE_SEC="${AZL_ENTERPRISE_VERIFY_DEADLINE_SEC:-240}"

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

echo "[verify-enterprise-http] building enterprise combined (canonical list)..."
COMBINED="${ROOT_DIR}/.azl/tmp/verify_enterprise_combined.azl"
bash scripts/build_enterprise_combined.sh "$COMBINED"
COMBINED_REAL="$(realpath "$COMBINED")"

BUNDLE="${ROOT_DIR}/.azl/tmp/verify_enterprise_live_bundle.azl"
bash scripts/build_azl_bootstrap_bundle.sh "$COMBINED_REAL" "::build.daemon.enterprise" --out "$BUNDLE"

BIN="$(bash scripts/build_azl_native_engine.sh)"

export AZL_API_TOKEN="$TOKEN"
export AZL_BUILD_API_PORT="$PORT"
export AZL_BIND_HOST="${AZL_BIND_HOST:-127.0.0.1}"
export AZL_NATIVE_RUNTIME_CMD="$(bash scripts/azl_resolve_native_runtime_cmd.sh)"

echo "[verify-enterprise-http] starting azl-native-engine on 127.0.0.1:${PORT}"
echo "[verify-enterprise-http] combined=${COMBINED_REAL}"
echo "[verify-enterprise-http] bundle=${BUNDLE}"
echo "[verify-enterprise-http] log=${LOG_PATH}"
: >"$LOG_PATH"
"$BIN" "$BUNDLE" >>"$LOG_PATH" 2>&1 &
ENGINE_PID=$!

http_code() {
  curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://127.0.0.1:${PORT}${1}" 2>/dev/null || echo "000"
}

wait_for_engine_ready() {
  local deadline=$((SECONDS + DEADLINE_SEC))
  while [ $SECONDS -lt "$deadline" ]; do
    if [ "$(http_code /healthz)" = "200" ] && [ "$(http_code /readyz)" = "200" ]; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

if ! wait_for_engine_ready; then
  echo "ERROR[AZL_ENTERPRISE_HTTP]: native engine + enterprise bundle did not reach healthz+readyz HTTP 200 within ${DEADLINE_SEC}s"
  echo "See log: ${LOG_PATH}"
  exit 80
fi

HEALTH_JSON="$(curl -fsS "http://127.0.0.1:${PORT}/healthz")"
READY_JSON="$(curl -fsS "http://127.0.0.1:${PORT}/readyz")"
STATUS_JSON="$(curl -fsS "http://127.0.0.1:${PORT}/status")"
EXEC_JSON="$(curl -fsS -H "Authorization: Bearer ${TOKEN}" "http://127.0.0.1:${PORT}/api/exec_state")"

if ! echo "$HEALTH_JSON" | rg -q '"ok":true'; then
  echo "ERROR[AZL_ENTERPRISE_HTTP]: healthz not ok: ${HEALTH_JSON}"
  exit 81
fi
if ! echo "$HEALTH_JSON" | rg -q 'build\.daemon\.enterprise'; then
  echo "ERROR[AZL_ENTERPRISE_HTTP]: healthz missing enterprise entry hint (expected build.daemon.enterprise): ${HEALTH_JSON}"
  exit 82
fi
if ! echo "$READY_JSON" | rg -q '"status":"ready"'; then
  echo "ERROR[AZL_ENTERPRISE_HTTP]: readyz not ready: ${READY_JSON}"
  exit 81
fi
if ! echo "$STATUS_JSON" | rg -q '"running":true'; then
  echo "ERROR[AZL_ENTERPRISE_HTTP]: status runtime not running: ${STATUS_JSON}"
  exit 81
fi

STATUS_COMBINED="$(printf '%s' "$STATUS_JSON" | sed -n 's/.*\"combined\":\"\([^\"]*\)\".*/\1/p')"
if [ -z "$STATUS_COMBINED" ]; then
  echo "ERROR[AZL_ENTERPRISE_HTTP]: unable to parse combined path from /status"
  exit 83
fi
if [ "$STATUS_COMBINED" != "$COMBINED_REAL" ]; then
  echo "ERROR[AZL_ENTERPRISE_HTTP]: /status combined path mismatch"
  echo "  expected: ${COMBINED_REAL}"
  echo "  got:      ${STATUS_COMBINED}"
  exit 84
fi

if ! echo "$EXEC_JSON" | rg -q '"running":true'; then
  echo "ERROR[AZL_ENTERPRISE_HTTP]: exec_state runtime not running: ${EXEC_JSON}"
  exit 81
fi

CAP_JSON="$(curl -fsS "http://127.0.0.1:${PORT}/api/llm/capabilities")"
if ! echo "$CAP_JSON" | rg -q '"ok":true'; then
  echo "ERROR[AZL_ENTERPRISE_HTTP]: /api/llm/capabilities not ok: ${CAP_JSON}"
  exit 85
fi
if ! echo "$CAP_JSON" | rg -q '"ollama_http_proxy":true'; then
  echo "ERROR[AZL_ENTERPRISE_HTTP]: /api/llm/capabilities missing ollama_http_proxy: ${CAP_JSON}"
  exit 86
fi
if echo "$CAP_JSON" | rg -q '"gguf_in_process":false'; then
  if ! echo "$CAP_JSON" | rg -q 'ERR_NATIVE_GGUF_NOT_IN_PROCESS'; then
    echo "ERROR[AZL_ENTERPRISE_HTTP]: /api/llm/capabilities missing ERR_NATIVE_GGUF_NOT_IN_PROCESS (stub build): ${CAP_JSON}"
    exit 87
  fi
elif echo "$CAP_JSON" | rg -q '"gguf_in_process":true'; then
  if ! echo "$CAP_JSON" | rg -q '"gguf_embedded_llamacpp":true'; then
    echo "ERROR[AZL_ENTERPRISE_HTTP]: /api/llm/capabilities expected gguf_embedded_llamacpp when gguf_in_process true: ${CAP_JSON}"
    exit 88
  fi
  if ! echo "$CAP_JSON" | rg -q '"error":null'; then
    echo "ERROR[AZL_ENTERPRISE_HTTP]: /api/llm/capabilities expected error:null for embedded llama.cpp build: ${CAP_JSON}"
    exit 87
  fi
else
  echo "ERROR[AZL_ENTERPRISE_HTTP]: /api/llm/capabilities missing valid gguf_in_process boolean: ${CAP_JSON}"
  exit 88
fi

echo "live-enterprise-native-http-ok"

echo "[verify-enterprise-http] success"
echo "  port: ${PORT}"
echo "  token: ${TOKEN}"
echo "  combined: ${COMBINED_REAL}"
echo "  healthz: ${HEALTH_JSON}"
echo "  readyz: ${READY_JSON}"
echo "  status: ${STATUS_JSON}"
echo "  api/exec_state: ${EXEC_JSON}"
echo "  api/llm/capabilities: ${CAP_JSON}"
