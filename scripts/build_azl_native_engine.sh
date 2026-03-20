#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/.azl/bin"
OUT_BIN="${OUT_DIR}/azl-native-engine"
SRC="${ROOT_DIR}/tools/azl_native_engine.c"

if [ ! -f "$SRC" ]; then
  echo "ERROR: missing source file: $SRC" >&2
  exit 2
fi

if ! command -v gcc >/dev/null 2>&1; then
  echo "ERROR: gcc is required to build azl-native-engine" >&2
  exit 3
fi

mkdir -p "$OUT_DIR"
# Default gate build: no llama.cpp. For in-process GGUF (linked llama.cpp), use:
#   LLAMA_CPP_ROOT=/path/to/llama.cpp ./scripts/build_azl_native_engine_with_llamacpp.sh
gcc -O2 -Wall -Wextra -o "$OUT_BIN" "$SRC"
chmod +x "$OUT_BIN"
echo "$OUT_BIN"
