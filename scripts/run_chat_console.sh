#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

export AZL_STRICT=1
export AZL_TARGET_FILE="${AZL_TARGET_FILE:-azl/ui/chat_console.azl}"

: "${TMPDIR:=/tmp}"; mkdir -p "$TMPDIR"
COMBINED="${TMPDIR}/azl_chat_console_$$.azl"
cat azl/ui/chat_console.azl \
    azme/interface/azme_chat_interface.azl \
    azl/core/error_system.azl \
    > "$COMBINED"

echo "Running chat console via native runtime... (Ctrl+C to exit)"
bash scripts/start_azl_native_mode.sh

