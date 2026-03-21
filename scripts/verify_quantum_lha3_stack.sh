#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/azl_local_layout.sh"

TOKEN="${AZL_VERIFY_TOKEN:-azl_verify_token_2026}"
PORT="${AZL_VERIFY_PORT:-$(( (RANDOM % 20000) + 30000 ))}"
LOG_PATH="${AZL_VERIFY_Q_LHA3_LOG:-${AZL_LOGS_DIR}/verify_quantum_lha3.log}"

mkdir -p .azl

echo "[verify-qlha3] LHA3 compression honesty contract (docs + source markers)"
bash scripts/verify_lha3_compression_honesty_contract.sh

cleanup_verify_qlha3() {
  chmod +x scripts/azl_teardown_verify_native_stack.sh 2>/dev/null || true
  bash scripts/azl_teardown_verify_native_stack.sh "$PORT" "$TOKEN" || true
}
trap cleanup_verify_qlha3 EXIT

echo "[verify-qlha3] starting native mode on 127.0.0.1:${PORT}"
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
  exit 91
fi

# Wait for startup events to flush into daemon logs.
sleep 2

STATUS_JSON="$(curl -fsS "http://127.0.0.1:${PORT}/status")"
COMBINED_PATH="$(echo "$STATUS_JSON" | sed -n 's/.*"combined":"\([^"]*\)".*/\1/p')"
if [ -z "$COMBINED_PATH" ] || [ ! -f "$COMBINED_PATH" ]; then
  echo "ERROR: unable to resolve active combined AZL path from /status"
  exit 92
fi

if ! rg -q "component ::quantum.memory.lha3_quantum_engine" "$COMBINED_PATH"; then
  echo "ERROR: combined runtime missing lha3 quantum engine component"
  exit 93
fi
if ! rg -q "component ::monitoring.quantum_dashboard" "$COMBINED_PATH"; then
  echo "ERROR: combined runtime missing quantum dashboard component"
  exit 94
fi
if ! rg -q "initialize_hyperdimensional_vectors" "$COMBINED_PATH"; then
  echo "ERROR: combined runtime missing hyperdimensional vector initialization event"
  exit 95
fi

echo "[verify-qlha3] success"
echo "  port: ${PORT}"
echo "  token: ${TOKEN}"
echo "  log: ${LOG_PATH}"
