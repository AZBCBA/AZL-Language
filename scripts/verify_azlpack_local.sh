#!/usr/bin/env bash
# Build azl-hello .azlpack and install from packages/registry into .azl/packages (then remove).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

chmod +x scripts/build_azlpack.sh 2>/dev/null || true
bash scripts/build_azlpack.sh

REG="$ROOT_DIR/packages/registry"
if [ ! -f "$REG/azl-hello/1.0.0/pkg.tar.gz" ]; then
  echo "ERROR: expected $REG/azl-hello/1.0.0/pkg.tar.gz after build" >&2
  exit 60
fi

rm -rf "$ROOT_DIR/.azl/packages/azl-hello"
AZL_REGISTRY_DIR="$REG" AZL_PACKAGES_DIR="$ROOT_DIR/.azl/packages" bash scripts/azl_install.sh azl-hello

M="$ROOT_DIR/.azl/packages/azl-hello/manifest.json"
if [ ! -f "$M" ]; then
  echo "ERROR: manifest missing after install" >&2
  exit 61
fi
if ! rg -q '"name"[[:space:]]*:[[:space:]]*"azl-hello"' "$M"; then
  echo "ERROR: installed manifest name mismatch" >&2
  exit 62
fi
if [ ! -f "$ROOT_DIR/.azl/packages/azl-hello/azl/hello_pkg.azl" ]; then
  echo "ERROR: hello_pkg.azl not installed" >&2
  exit 63
fi

echo "azlpack-local-dogfood-ok"
