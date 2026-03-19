#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR="${AZL_OUT_DIR:-.azl/bin}"
mkdir -p "$OUT_DIR"
OUT_BIN="${OUT_DIR}/azl-interpreter-minimal"

if ! command -v gcc >/dev/null 2>&1; then
  echo "ERROR: gcc is required to build azl-interpreter-minimal" >&2
  exit 1
fi

echo "Building azl-interpreter-minimal..."
gcc -O2 -Wall -Wextra -o "$OUT_BIN" tools/azl_interpreter_minimal.c
echo "Built: $OUT_BIN"
echo "$OUT_BIN"
