#!/usr/bin/env bash
# Build .azlpack tarballs from packages/src/<name>/ into packages/registry/<name>/<version>/pkg.tar.gz
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SRC="${1:-$ROOT_DIR/packages/src/azl-hello}"
if [ ! -f "$SRC/manifest.json" ]; then
  echo "ERROR: $SRC/manifest.json missing" >&2
  exit 2
fi

export AZL_MANIFEST_PATH="$SRC/manifest.json"
NAME="$(python3 -c "import json,os; print(json.load(open(os.environ['AZL_MANIFEST_PATH']))['name'])")"
VER="$(python3 -c "import json,os; print(json.load(open(os.environ['AZL_MANIFEST_PATH']))['version'])")"
unset AZL_MANIFEST_PATH
if [ -z "$NAME" ] || [ -z "$VER" ]; then
  echo "ERROR: manifest must have name and version" >&2
  exit 3
fi

OUT_DIR="$ROOT_DIR/packages/registry/$NAME/$VER"
mkdir -p "$OUT_DIR"
STAGE="$(mktemp -d)"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

mkdir -p "$STAGE/$NAME"
cp -a "$SRC/." "$STAGE/$NAME/"
tar -czf "$OUT_DIR/pkg.tar.gz" -C "$STAGE" "$NAME"
echo "Built $OUT_DIR/pkg.tar.gz"
