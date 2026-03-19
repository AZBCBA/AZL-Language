#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

TOKEN="${AZL_VERIFY_TOKEN:-azl_verify_token_2026}"
PORT="${AZL_VERIFY_PORT:-$(( (RANDOM % 20000) + 30000 ))}"
LOG_PATH="${AZL_VERIFY_GRAMMAR_LOG:-.azl/verify_azl_grammar_conformance.log}"

mkdir -p .azl

echo "[verify-grammar] starting native mode on 127.0.0.1:${PORT}"
AZL_API_TOKEN="$TOKEN" \
AZL_BUILD_API_PORT="$PORT" \
AZL_BIND_HOST="127.0.0.1" \
bash scripts/start_azl_native_mode.sh >"$LOG_PATH" 2>&1 &

deadline=$((SECONDS + 35))
while [ $SECONDS -lt $deadline ]; do
  if curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
  echo "ERROR: native runtime did not become healthy"
  exit 101
fi

STATUS_JSON="$(curl -fsS "http://127.0.0.1:${PORT}/status")"
COMBINED_PATH="$(echo "$STATUS_JSON" | sed -n 's/.*\"combined\":\"\([^\"]*\)\".*/\1/p')"
if [ -z "$COMBINED_PATH" ] || [ ! -f "$COMBINED_PATH" ]; then
  echo "ERROR: unable to resolve active combined AZL path from /status"
  exit 102
fi

# Guard canonical runtime bundle from non-AZL host-language constructs.
if rg -n "\\bclass\\s+[A-Za-z_][A-Za-z0-9_]*\\s*\\{" "$COMBINED_PATH" >/tmp/azl_grammar_class_hits.out 2>&1; then
  echo "ERROR: combined runtime contains class-based host syntax"
  cat /tmp/azl_grammar_class_hits.out
  exit 103
fi
if rg -n "constructor\\(|\\bimport\\s+.*\\s+from\\s+" "$COMBINED_PATH" >/tmp/azl_grammar_js_hits.out 2>&1; then
  echo "ERROR: combined runtime contains JS-style host syntax"
  cat /tmp/azl_grammar_js_hits.out
  exit 104
fi
if rg -n "def\\s+[A-Za-z_]|lambda\\s+|__name__\\s*==\\s*['\\\"]__main__['\\\"]" "$COMBINED_PATH" >/tmp/azl_grammar_py_hits.out 2>&1; then
  echo "ERROR: combined runtime contains Python-style host syntax"
  cat /tmp/azl_grammar_py_hits.out
  exit 105
fi
if rg -n "\\bvar\\s+[A-Za-z_]|\\bconst\\s+[A-Za-z_]|(?<![a-zA-Z0-9_])print\\s*\\(" "$COMBINED_PATH" >/tmp/azl_grammar_var_hits.out 2>&1; then
  echo "ERROR: combined runtime contains host syntax (var/const/print); use set/let/say"
  cat /tmp/azl_grammar_var_hits.out
  exit 106
fi
if rg -n "export\\s+default|^[^#]*\\binterface\\s+[A-Z][A-Za-z0-9_]*\\s*\\{" "$COMBINED_PATH" >/tmp/azl_grammar_export_hits.out 2>&1; then
  echo "ERROR: combined runtime contains JS/TS export/interface syntax"
  cat /tmp/azl_grammar_export_hits.out
  exit 107
fi

echo "[verify-grammar] success"
echo "  port: ${PORT}"
echo "  token: ${TOKEN}"
echo "  combined: ${COMBINED_PATH}"
echo "  log: ${LOG_PATH}"
