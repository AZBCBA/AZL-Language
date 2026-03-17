#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== AZL cold vs warm benchmark =="
export AZL_STRICT=1
export AZL_PARSE_CACHE=256
export AZL_FILE_CACHE=128

TARGET="azl/testing/integration/test_arithmetic.azl"
if [ $# -gt 0 ]; then TARGET="$1"; fi

echo "Target: $TARGET"

echo "-- Cold run --"
/usr/bin/time -f '%E real %M KB maxrss' python3 azl_runner.py "$TARGET" >/dev/null || true

echo "-- Warm pass (seed caches) --"
python3 azl_runner.py "$TARGET" >/dev/null || true

echo "-- Warm run --"
/usr/bin/time -f '%E real %M KB maxrss' python3 azl_runner.py "$TARGET" >/dev/null || true

echo "Done"

