#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

export AZL_STRICT=1
export AZL_TARGET_FILE="${AZL_TARGET_FILE:-azl/system/http_server.azl}"

: "${TMPDIR:=/tmp}"; mkdir -p "$TMPDIR"
COMBINED="${TMPDIR}/azl_http_chat_local_$$.azl"
cat azl/api/endpoints.azl \
    azl/system/http_server.azl \
    azme/interface/azme_chat_interface.azl \
    azl/core/error_system.azl \
    > "$COMBINED"

echo "Booting HTTP chat locally (native runtime)."
bash scripts/start_azl_native_mode.sh

