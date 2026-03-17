#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

export AZL_STRICT=1

: "${TMPDIR:=/tmp}"; mkdir -p "$TMPDIR"
COMBINED="${TMPDIR}/azl_chat_console_$$.azl"
cat azl/ui/chat_console.azl \
    azme/interface/azme_chat_interface.azl \
    azl/core/error_system.azl \
    > "$COMBINED"

echo "Running chat console... (Ctrl+C to exit)"
/usr/bin/env python3 azl_runner.py "$COMBINED"

