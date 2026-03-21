#!/usr/bin/env bash
# Ensures off-tree Rust workspace guidance stays anchored in docs (no Cargo in this repo).
# Prefix ERROR[RUST_OFFTREE_DOC]: on stderr.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

DOC="docs/RELATED_WORKSPACES.md"
ANCHOR="RUST_OFFTREE_CONTRACT_V1"

if [ ! -f "$DOC" ]; then
  echo "ERROR[RUST_OFFTREE_DOC]: missing $DOC" >&2
  exit 240
fi

if ! command -v rg >/dev/null 2>&1; then
  echo "ERROR[RUST_OFFTREE_DOC]: rg (ripgrep) not found" >&2
  exit 241
fi

if ! rg -q "$ANCHOR" "$DOC"; then
  echo "ERROR[RUST_OFFTREE_DOC]: contract anchor missing in $DOC (expected $ANCHOR)" >&2
  exit 242
fi

if ! rg -q "azme-azl" "$DOC"; then
  echo "ERROR[RUST_OFFTREE_DOC]: expected azme-azl path discussion in $DOC" >&2
  exit 243
fi

echo "rust-offtree-doc-contract-ok"
exit 0
