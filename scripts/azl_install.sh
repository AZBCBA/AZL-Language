#!/usr/bin/env bash
# azl install <package> - Install AZL package from registry
# Uses .azlpack format; registry URL from AZL_REGISTRY_URL
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

REGISTRY="${AZL_REGISTRY_URL:-https://registry.azl.dev}"
INSTALL_DIR="${AZL_PACKAGES_DIR:-.azl/packages}"
PKG="${1:-}"

if [ -z "$PKG" ]; then
  echo "Usage: bash scripts/azl_install.sh <package>"
  echo "Example: bash scripts/azl_install.sh azl-memory-lha3"
  echo ""
  echo "Env: AZL_REGISTRY_URL, AZL_PACKAGES_DIR"
  exit 1
fi

mkdir -p "$INSTALL_DIR"
TARGET="$INSTALL_DIR/$PKG"

if [ -d "$TARGET" ]; then
  echo "Package $PKG already installed at $TARGET"
  exit 0
fi

echo "Installing $PKG from $REGISTRY..."
URL="${REGISTRY}/${PKG}/latest"
TARBALL="/tmp/azl_install_${PKG}_$$.tar.gz"

if command -v curl >/dev/null 2>&1; then
  if curl -fsSL -o "$TARBALL" "$URL" 2>/dev/null; then
    mkdir -p "$TARGET"
    tar -xzf "$TARBALL" -C "$TARGET" 2>/dev/null || true
    rm -f "$TARBALL"
    if [ -f "$TARGET/manifest.json" ]; then
      echo "✅ Installed $PKG to $TARGET"
      echo "Add to AZL_COMPONENT_PATH: $TARGET"
    else
      echo "⚠️  Downloaded but manifest.json not found (registry may not be live)"
      echo "Package dir: $TARGET"
    fi
  else
    echo "Registry not reachable at $URL (azl install is design-phase)"
    echo "Create package manually: mkdir -p $TARGET, add manifest.json + azl/"
    mkdir -p "$TARGET"
    echo '{"name":"'"$PKG"'","version":"0.0.0","components":[],"dependencies":[]}' > "$TARGET/manifest.json"
    echo "Created stub $TARGET/manifest.json for local development"
  fi
else
  echo "curl required for azl install"
  exit 1
fi
