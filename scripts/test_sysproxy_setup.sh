#!/usr/bin/env bash
# Bring up sysproxy + wire + enterprise daemon for local / CI smoke tests.
# Must NOT invoke azme_e2e.sh (that script calls this one — recursion would exhaust the process table).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/azl_local_layout.sh"

PORT="${AZL_BUILD_API_PORT:-8080}"
echo "🔍 test_sysproxy_setup: starting enterprise daemon (run_enterprise_daemon.sh) port=${PORT}"

export AZL_WIRE_MANAGED="${AZL_WIRE_MANAGED:-1}"
bash scripts/run_enterprise_daemon.sh

echo "🔍 test_sysproxy_setup: waiting for /healthz"
deadline=$((SECONDS + 90))
H=()
if [ "${AZL_REQUIRE_API_TOKEN:-true}" != "false" ] && [ -n "${AZL_API_TOKEN:-}" ]; then
  H=( -H "Authorization: Bearer ${AZL_API_TOKEN}" )
fi
while [ "$SECONDS" -lt "$deadline" ]; do
  if curl -sf "${H[@]}" "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
    echo "✅ test_sysproxy_setup: daemon healthy"
    exit 0
  fi
  sleep 1
done

echo "ERROR[TEST_SYSPROXY_SETUP]: daemon did not become healthy within 90s (port=${PORT})" >&2
echo "See ${AZL_LOGS_DIR}/daemon.out and ${AZL_LOGS_DIR}/wire.log" >&2
exit 1
