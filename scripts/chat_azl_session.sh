#!/usr/bin/env bash
set -euo pipefail

# Interactive terminal chat against AZL /api/llm/chat_session.
# Usage:
#   bash scripts/chat_azl_session.sh
#   AZL_CHAT_BASE_URL=http://127.0.0.1:18270 AZL_CHAT_TOKEN=... bash scripts/chat_azl_session.sh
#   AZL_CHAT_SESSION_ID=my-session bash scripts/chat_azl_session.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
_lc_env="${ROOT}/.azl/live_chat.env"

# Port: AZL_CHAT_PORT / AZL_BUILD_API_PORT override; else PORT= in .azl/live_chat.env; else 8080.
if [[ -n "${AZL_CHAT_PORT:-}" ]]; then
  PORT="${AZL_CHAT_PORT}"
elif [[ -n "${AZL_BUILD_API_PORT:-}" ]]; then
  PORT="${AZL_BUILD_API_PORT}"
elif [[ -f "${_lc_env}" ]]; then
  PORT="$(grep -E '^PORT=' "${_lc_env}" | head -1 | cut -d= -f2- || true)"
  PORT="${PORT:-8080}"
else
  PORT="8080"
fi
BASE_URL="${AZL_CHAT_BASE_URL:-http://127.0.0.1:${PORT}}"

# Token: AZL_CHAT_TOKEN / AZL_API_TOKEN, or TOKEN= in .azl/live_chat.env (no weak default).
TOKEN="${AZL_CHAT_TOKEN:-${AZL_API_TOKEN:-}}"
if [[ -z "${TOKEN}" ]]; then
  if [[ -f "${_lc_env}" ]]; then
    TOKEN="$(grep -E '^TOKEN=' "${_lc_env}" | head -1 | cut -d= -f2- || true)"
  fi
fi
if [[ -z "${TOKEN}" ]]; then
  echo "ERROR: Set AZL_CHAT_TOKEN or AZL_API_TOKEN, or add TOKEN= to .azl/live_chat.env" >&2
  exit 2
fi
SESSION_ID="${AZL_CHAT_SESSION_ID:-user-$(date +%s)}"
N_PREDICT="${AZL_CHAT_N_PREDICT:-512}"

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required but not found in PATH." >&2
  exit 11
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required but not found in PATH." >&2
  exit 12
fi

echo "AZL chat started."
echo "Base URL : ${BASE_URL}"
echo "Session  : ${SESSION_ID}"
echo "Commands : /exit, /reset"
echo

reset_flag="false"

while true; do
  printf "You> "
  if ! IFS= read -r user_msg; then
    echo
    echo "Input closed. Exiting."
    exit 0
  fi

  if [[ -z "${user_msg}" ]]; then
    continue
  fi

  case "${user_msg}" in
    /exit|/quit)
      echo "Bye."
      exit 0
      ;;
    /reset)
      reset_flag="true"
      user_msg="Start a fresh conversation."
      ;;
  esac

  payload="$(
    python3 - <<'PY' "${SESSION_ID}" "${user_msg}" "${N_PREDICT}" "${reset_flag}"
import json
import sys
sid, msg, n_predict, reset = sys.argv[1:5]
print(json.dumps({
    "session_id": sid,
    "message": msg,
    "n_predict": int(n_predict),
    "reset": reset.lower() == "true",
}))
PY
  )"

  response="$(
    curl -sS --fail-with-body \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -X POST "${BASE_URL}/api/llm/chat_session" \
      --data "${payload}"
  )" || {
    echo "ERROR: request failed."
    echo "Details:"
    echo "${response:-<no response body>}"
    reset_flag="false"
    continue
  }

  assistant_text="$(
    python3 - <<'PY' "${response}"
import json
import sys
raw = sys.argv[1]
try:
    obj = json.loads(raw)
except Exception:
    print(f"[invalid_json_response] {raw}")
    raise SystemExit(0)
if obj.get("ok") is True:
    print(obj.get("text", ""))
else:
    err = obj.get("error", "unknown_error")
    reason = obj.get("reason")
    msg = f"[error] {err}"
    if reason:
        msg += f" ({reason})"
    print(msg)
PY
  )"

  echo "AZL> ${assistant_text}"
  echo
  reset_flag="false"
done
