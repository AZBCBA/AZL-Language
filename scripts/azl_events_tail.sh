#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

HOST="${AZL_HOST:-127.0.0.1}"
PORT="${AZL_PORT:-8080}"
TOKEN="${AZL_API_TOKEN:-}"
URL="http://$HOST:$PORT/events"

echo "== Tailing AZL events (Ctrl-C to stop) =="
while true; do
  if [ -n "$TOKEN" ]; then
    curl -sS --max-time 5 -H "Authorization: Bearer $TOKEN" "$URL" | jq -r '.events[] | ("[" + (.ts|tostring) + "] " + .type + " " + (.data|tostring))' 2>/dev/null || curl -sS --max-time 5 -H "Authorization: Bearer $TOKEN" "$URL"
  else
    curl -sS --max-time 5 "$URL" | jq -r '.events[] | ("[" + (.ts|tostring) + "] " + .type + " " + (.data|tostring))' 2>/dev/null || curl -sS --max-time 5 "$URL"
  fi
  sleep 3
done

