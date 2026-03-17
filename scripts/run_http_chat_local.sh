#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

export AZL_STRICT=1

: "${TMPDIR:=/tmp}"; mkdir -p "$TMPDIR"
COMBINED="${TMPDIR}/azl_http_chat_local_$$.azl"
cat azl/api/endpoints.azl \
    azl/system/http_server.azl \
    azme/interface/azme_chat_interface.azl \
    azl/core/error_system.azl \
    > "$COMBINED"

echo "Booting HTTP chat locally (runner simulation)."
/usr/bin/env python3 azl_runner.py "$COMBINED"

