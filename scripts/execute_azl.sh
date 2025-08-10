#!/usr/bin/env bash
# Executes AZL by delegating to the Stage-0 bootstrap (no fake runner).
set -euo pipefail

if [ "${1:-}" = "" ]; then
  echo "usage: $0 <combined.azl> [::<entry.point>]" >&2
  exit 2
fi

COMBINED="$1"
ENTRY="${2:-${AZL_ENTRY:-::build.daemon.enterprise}}"

# Hand off to Stage-0 (this actually executes the real engine).
exec "$(dirname "$0")/azl_bootstrap.sh" "$COMBINED" "$ENTRY"
