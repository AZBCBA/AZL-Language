#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

BUNDLE_PATH="${AZL_BOOTSTRAP_BUNDLE:-}"
COMBINED_PATH="${AZL_COMBINED_PATH:-}"
ENTRY="${AZL_ENTRY:-}"

if [ -z "$BUNDLE_PATH" ] || [ ! -f "$BUNDLE_PATH" ]; then
  echo "ERROR: AZL_BOOTSTRAP_BUNDLE is missing or not a file" >&2
  exit 40
fi
if [ -z "$COMBINED_PATH" ] || [ ! -f "$COMBINED_PATH" ]; then
  echo "ERROR: AZL_COMBINED_PATH is missing or not a file" >&2
  exit 41
fi
if [ -z "$ENTRY" ]; then
  echo "ERROR: AZL_ENTRY is required" >&2
  exit 42
fi

if ! rg -q "component\\s+${ENTRY//./\\.}\\b" "$COMBINED_PATH"; then
  echo "ERROR: entry component '$ENTRY' not found in combined AZL file" >&2
  exit 43
fi

mkdir -p .azl
STATE_PATH=".azl/native_runtime_state.json"
START_TS="$(date +%s)"
echo "{\"status\":\"starting\",\"entry\":\"$ENTRY\",\"combined\":\"$COMBINED_PATH\",\"started_at\":$START_TS}" > "$STATE_PATH"

cleanup() {
  NOW="$(date +%s)"
  echo "{\"status\":\"stopped\",\"entry\":\"$ENTRY\",\"combined\":\"$COMBINED_PATH\",\"started_at\":$START_TS,\"stopped_at\":$NOW}" > "$STATE_PATH"
}
trap cleanup EXIT INT TERM

while true; do
  NOW="$(date +%s)"
  echo "{\"status\":\"running\",\"entry\":\"$ENTRY\",\"combined\":\"$COMBINED_PATH\",\"bundle\":\"$BUNDLE_PATH\",\"started_at\":$START_TS,\"heartbeat\":$NOW}" > "$STATE_PATH"
  sleep 1
done
