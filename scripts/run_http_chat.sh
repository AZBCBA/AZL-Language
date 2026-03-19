#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

export AZL_STRICT=1
export AZL_API_TOKEN=${AZL_API_TOKEN:-$(openssl rand -hex 16)}
export AZL_REQUIRE_API_TOKEN=false
export AZL_TARGET_FILE="${AZL_TARGET_FILE:-azl/system/http_server.azl}"

: "${TMPDIR:=/tmp}"; mkdir -p "$TMPDIR"
COMBINED="${TMPDIR}/azl_http_chat_$$.azl"
cat azl/system/http_server.azl \
    azl/api/endpoints.azl \
    azme/interface/azme_chat_interface.azl \
    azl/core/error_system.azl \
    > "$COMBINED"

echo "HTTP chat starting with token: $AZL_API_TOKEN"
bash scripts/start_azl_native_mode.sh

