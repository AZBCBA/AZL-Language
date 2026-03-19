#!/usr/bin/env bash
# Fail if the enterprise combined bundle script pulls host-shaped AnythingLLM files.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

DAEMON="scripts/run_enterprise_daemon.sh"
if [ ! -f "$DAEMON" ]; then
  echo "ERROR: missing $DAEMON" >&2
  exit 90
fi

patterns=(
  "azl/integrations/anythingllm/azme_bridge\\.azl"
  "azl/integrations/anythingllm/azme_anythingllm_provider\\.azl"
  "azl/integrations/anythingllm/azme_proxy\\.azl"
  "azl/integrations/anythingllm_integration\\.azl"
)

for p in "${patterns[@]}"; do
  if rg -n "$p" "$DAEMON" >/tmp/azl_bundle_rg.out 2>&1; then
    echo "ERROR: host-shaped integration must not be in native bundle: $p" >&2
    cat /tmp/azl_bundle_rg.out >&2
    exit 91
  fi
done

echo "native-bundle-host-integrations-ok"
