#!/usr/bin/env bash
# Enforces docs/LHA3_COMPRESSION_HONESTY.md + in-source markers for LHA3 "compression" honesty.
# No daemon; no network. See docs/ERROR_SYSTEM.md § LHA3 compression honesty contract.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

DOC="docs/LHA3_COMPRESSION_HONESTY.md"
ENGINE="azl/quantum/memory/lha3_quantum_engine.azl"
MEMORY="azl/memory/lha3_quantum_memory.azl"
ANCHOR="LHA3_COMPRESSION_HONESTY_CONTRACT_V1"
MARKER="LHA3_COMPRESSION_MODEL=heuristic_retention"

if [ ! -f "Makefile" ] || [ ! -d "azl" ]; then
  echo "ERROR[LHA3_COMPRESSION_HONESTY]: must run from repository root" >&2
  exit 220
fi

if [ ! -f "$DOC" ]; then
  echo "ERROR[LHA3_COMPRESSION_HONESTY]: missing honesty doc: $DOC" >&2
  exit 221
fi

if ! rg -q "$ANCHOR" "$DOC"; then
  echo "ERROR[LHA3_COMPRESSION_HONESTY]: contract anchor missing in $DOC (expected $ANCHOR)" >&2
  exit 222
fi

if ! command -v rg >/dev/null 2>&1; then
  echo "ERROR[LHA3_COMPRESSION_HONESTY]: rg (ripgrep) not found" >&2
  exit 225
fi

if ! rg -qF "$MARKER" "$ENGINE"; then
  echo "ERROR[LHA3_COMPRESSION_HONESTY]: implementation marker missing in $ENGINE (expected $MARKER)" >&2
  exit 223
fi

if ! rg -qF "$MARKER" "$MEMORY"; then
  echo "ERROR[LHA3_COMPRESSION_HONESTY]: implementation marker missing in $MEMORY (expected $MARKER)" >&2
  exit 224
fi

echo "lha3-compression-honesty-contract-ok"
exit 0
