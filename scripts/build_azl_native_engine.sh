#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/.azl/bin"
OUT_BIN="${OUT_DIR}/azl-native-engine"
SRC_ENGINE="${ROOT_DIR}/tools/azl_native_engine.c"
SRC_CORE="${ROOT_DIR}/tools/azl_core_engine.c"
SRC_HOST="${ROOT_DIR}/tools/azl_native_engine_core_host.c"

for f in "$SRC_ENGINE" "$SRC_CORE" "$SRC_HOST"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: missing source file: $f" >&2
    exit 2
  fi
done

if ! command -v gcc >/dev/null 2>&1; then
  echo "ERROR: gcc is required to build azl-native-engine" >&2
  exit 3
fi

mkdir -p "$OUT_DIR"
# Default gate build: no llama.cpp. For in-process GGUF (linked llama.cpp), use:
#   LLAMA_CPP_ROOT=/path/to/llama.cpp ./scripts/build_azl_native_engine_with_llamacpp.sh
gcc -O2 -Wall -Wextra -pthread -I"${ROOT_DIR}/tools" \
  -o "$OUT_BIN" "$SRC_ENGINE" "$SRC_CORE" "$SRC_HOST"
chmod +x "$OUT_BIN"
echo "$OUT_BIN"
