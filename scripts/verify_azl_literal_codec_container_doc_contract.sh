#!/usr/bin/env bash
# Enforces docs/AZL_LITERAL_CODEC_CONTAINER_V0.md presence + contract anchor.
# No network. See docs/ERROR_SYSTEM.md § AZL literal codec container (doc contract).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

DOC="docs/AZL_LITERAL_CODEC_CONTAINER_V0.md"
ANCHOR="AZL_LITERAL_CODEC_CONTAINER_CONTRACT_V1"

if [ ! -f "Makefile" ] || [ ! -d "azl" ]; then
  echo "ERROR[AZL_LITERAL_CODEC_CONTAINER_DOC]: must run from repository root" >&2
  exit 250
fi

if [ ! -f "$DOC" ]; then
  echo "ERROR[AZL_LITERAL_CODEC_CONTAINER_DOC]: missing spec doc: $DOC" >&2
  exit 251
fi

if ! command -v rg >/dev/null 2>&1; then
  echo "ERROR[AZL_LITERAL_CODEC_CONTAINER_DOC]: rg (ripgrep) not found" >&2
  exit 253
fi

if ! rg -q "$ANCHOR" "$DOC"; then
  echo "ERROR[AZL_LITERAL_CODEC_CONTAINER_DOC]: contract anchor missing in $DOC (expected $ANCHOR)" >&2
  exit 252
fi

# Required normative sections (headings) — prevents empty shell doc
for heading in "2. Wire format" "3. Decoder algorithm" "6. Error identifiers"; do
  if ! rg -qF "$heading" "$DOC"; then
    echo "ERROR[AZL_LITERAL_CODEC_CONTAINER_DOC]: required section heading missing in $DOC: $heading" >&2
    exit 254
  fi
done

echo "azl-literal-codec-container-doc-contract-ok"
exit 0
