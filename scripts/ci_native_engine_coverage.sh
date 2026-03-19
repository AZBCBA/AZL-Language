#!/usr/bin/env bash
# Build azl-native-engine with GCC coverage flags, run live verify (exercises binary), emit lcov + HTML.
# Requires: gcc, lcov, curl, ripgrep, openssl (same as verify_native_runtime_live.sh).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

for cmd in gcc lcov genhtml curl rg openssl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $cmd" >&2
    exit 2
  fi
done

SRC="${ROOT_DIR}/tools/azl_native_engine.c"
OUT_BIN="${ROOT_DIR}/.azl/bin/azl-native-engine"
if [ ! -f "$SRC" ]; then
  echo "ERROR: missing native engine source: $SRC" >&2
  exit 3
fi

mkdir -p .azl/bin
rm -f "$OUT_BIN"
find "$ROOT_DIR" -maxdepth 3 \( -name '*.gcda' -o -name '*.gcno' \) -delete 2>/dev/null || true

gcc --coverage -O0 -g -Wall -Wextra -o "$OUT_BIN" "$SRC"
chmod +x "$OUT_BIN"

bash scripts/verify_native_runtime_live.sh

# Stop daemons so instrumented processes flush .gcda before lcov.
pkill -f 'azl-native-engine' 2>/dev/null || true
pkill -f 'run_enterprise_daemon' 2>/dev/null || true
pkill -f 'sysproxy' 2>/dev/null || true
sleep 1

if ! lcov --capture --directory "$ROOT_DIR" --output-file "${ROOT_DIR}/.azl/coverage.info" 2>/dev/null; then
  echo "ERROR: lcov --capture failed" >&2
  exit 4
fi

lcov --remove "${ROOT_DIR}/.azl/coverage.info" '/usr/*' -o "${ROOT_DIR}/.azl/coverage.info" || true

if ! genhtml "${ROOT_DIR}/.azl/coverage.info" --output-directory "${ROOT_DIR}/.azl/coverage-html" 2>/dev/null; then
  echo "ERROR: genhtml failed" >&2
  exit 5
fi

echo "OK: coverage report at .azl/coverage-html/index.html"
