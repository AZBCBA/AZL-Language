#!/usr/bin/env bash
set -euo pipefail

INPUT="${1:-}"; ENTRY="${2:-${AZL_ENTRY:-::build.daemon.enterprise}}"
if [ -z "$INPUT" ]; then
  echo "usage: $0 <combined.azl> [::<entry.point>]" >&2
  exit 2
fi

# Re-entry guard (prevents recursive bootstrap)
if [ "${AZL_BOOTSTRAP_GUARD:-}" = "1" ]; then
  echo "bootstrap: guard active; refusing to re-enter" >&2
  exit 99
fi
export AZL_BOOTSTRAP_GUARD=1

# Ensure TMPDIR exists and is writable (systemd may not provide /tmp)
TMPDIR_DEFAULT="${TMPDIR:-}"
if [ -z "${TMPDIR_DEFAULT}" ]; then
  if [ -d ".azl/tmp" ]; then
    export TMPDIR="$(pwd)/.azl/tmp"
  else
    mkdir -p .azl/tmp
    export TMPDIR="$(pwd)/.azl/tmp"
  fi
else
  mkdir -p "${TMPDIR}"
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# If input already a bootstrap, do not re-wrap it
if head -n 1 "$INPUT" 2>/dev/null | grep -q '^# AZL-BOOTSTRAP v1'; then
  BUNDLE="$INPUT"
else
  BUNDLE="$(mktemp -p "${TMPDIR}" -t azl_bootstrap.XXXXXX.azl)"
  bash scripts/build_azl_bootstrap_bundle.sh "$INPUT" "$ENTRY" --out "$BUNDLE"
fi

# Set env vars for the launcher, but DO NOT spawn any more bootstrap steps
export AZL_COMBINED_PATH="$INPUT"
export AZL_ENTRY="$ENTRY"
echo "bootstrap: ready bundle $BUNDLE (entry=$ENTRY)"
echo "bootstrap: executing with seed runner..."

# Execute the bootstrap bundle with the seed runner
exec "$(dirname "$0")/azl_seed_runner.sh" "$BUNDLE"
