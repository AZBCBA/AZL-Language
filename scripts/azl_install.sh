#!/usr/bin/env bash
# azl install <package> — .azlpack install
# Priority: 1) AZL_REGISTRY_DIR local tree  2) HTTP AZL_REGISTRY_URL
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

REGISTRY="${AZL_REGISTRY_URL:-https://registry.azl.dev}"
REGISTRY_DIR="${AZL_REGISTRY_DIR:-}"
INSTALL_DIR="${AZL_PACKAGES_DIR:-.azl/packages}"
PKG="${1:-}"

if [ -z "$PKG" ]; then
  echo "Usage: bash scripts/azl_install.sh <package>" >&2
  echo "Example: AZL_REGISTRY_DIR=\$PWD/packages/registry bash scripts/azl_install.sh azl-hello" >&2
  echo "" >&2
  echo "Env: AZL_REGISTRY_DIR (local), AZL_REGISTRY_URL, AZL_PACKAGES_DIR, AZL_PACKAGE_VERSION" >&2
  exit 1
fi

flatten_unpack() {
  local tmp="$1"
  local dest="$2"
  shopt -s nullglob
  local items=( "$tmp"/* )
  shopt -u nullglob
  if [ "${#items[@]}" -eq 1 ] && [ -d "${items[0]}" ] && [ -f "${items[0]}/manifest.json" ]; then
    mkdir -p "$dest"
    mv "${items[0]}"/* "$dest/"
    rmdir "${items[0]}"
    return 0
  fi
  echo "ERROR: .azlpack must contain one top-level directory with manifest.json" >&2
  return 1
}

install_from_tarball() {
  local tarpath="$1"
  local dest="$2"
  local tmp
  tmp="$(mktemp -d)"
  cleanup() { rm -rf "$tmp"; }
  trap cleanup EXIT
  tar -xzf "$tarpath" -C "$tmp"
  flatten_unpack "$tmp" "$dest"
  trap - EXIT
  rm -rf "$tmp"
}

mkdir -p "$INSTALL_DIR"
TARGET="$INSTALL_DIR/$PKG"

if [ -d "$TARGET" ] && [ -f "$TARGET/manifest.json" ]; then
  echo "Package $PKG already installed at $TARGET"
  exit 0
fi

# --- 1) Local registry: packages/registry/<name>/<ver>/pkg.tar.gz ---
if [ -n "$REGISTRY_DIR" ]; then
  RD="$REGISTRY_DIR/$PKG"
  if [ -d "$RD" ]; then
    VER="${AZL_PACKAGE_VERSION:-}"
    if [ -z "$VER" ]; then
      VER="$(ls -1 "$RD" 2>/dev/null | sort -V | tail -1 || true)"
    fi
    LT="$RD/$VER/pkg.tar.gz"
    if [ -f "$LT" ]; then
      echo "Installing $PKG from local registry ($LT)..."
      mkdir -p "$TARGET"
      install_from_tarball "$LT" "$TARGET"
      if [ ! -f "$TARGET/manifest.json" ]; then
        echo "ERROR: local unpack did not produce manifest.json at $TARGET" >&2
        exit 2
      fi
      echo "✅ Installed $PKG to $TARGET"
      echo "Add components to your bundle or AZL_COMPONENT_PATH as needed."
      exit 0
    fi
    echo "ERROR: local registry dir $RD exists but $LT not found (run scripts/build_azlpack.sh)" >&2
    exit 3
  fi
fi

# --- 2) Remote HTTP ---
echo "Installing $PKG from $REGISTRY..."
URL="${REGISTRY}/${PKG}/latest"
TARBALL="/tmp/azl_install_${PKG}_$$.tar.gz"

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl required for remote install (or set AZL_REGISTRY_DIR for local .azlpack)" >&2
  exit 1
fi

if curl -fsSL -o "$TARBALL" "$URL" 2>/dev/null; then
  mkdir -p "$TARGET"
  if install_from_tarball "$TARBALL" "$TARGET"; then
    rm -f "$TARBALL"
    if [ -f "$TARGET/manifest.json" ]; then
      echo "✅ Installed $PKG to $TARGET"
      exit 0
    fi
  fi
  rm -f "$TARBALL"
  echo "⚠️  Downloaded but unpack/manifest failed; see $TARGET" >&2
  exit 4
fi

rm -f "$TARBALL"
echo "Registry not reachable at $URL" >&2
if [ -n "$REGISTRY_DIR" ]; then
  echo "ERROR: set AZL_REGISTRY_DIR but package $PKG not under $REGISTRY_DIR/$PKG" >&2
  exit 5
fi
echo "Stub: mkdir -p $TARGET + manifest (offline dev only)" >&2
mkdir -p "$TARGET"
echo '{"name":"'"$PKG"'","version":"0.0.0","components":[],"dependencies":[]}' > "$TARGET/manifest.json"
echo "Created stub $TARGET/manifest.json"
