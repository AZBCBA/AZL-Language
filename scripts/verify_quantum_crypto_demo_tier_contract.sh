#!/usr/bin/env bash
# Ensures quantum-surface modules that name encryption/VPN/TLS carry AZL_CRYPTO_DEMO_SURFACE=DEMO_NON_CRYPTO_STUB.
# No daemon; no network. Prefix ERROR[QUANTUM_CRYPTO_DEMO]: on stderr.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

MARKER="AZL_CRYPTO_DEMO_SURFACE=DEMO_NON_CRYPTO_STUB"
FILES=(
  "azl/quantum/processor/quantum_encryption.azl"
  "azl/quantum/processor/hpqvpn.azl"
  "azl/quantum/processor/agent_channels.azl"
)

if [ ! -f "Makefile" ] || [ ! -d "azl/quantum/processor" ]; then
  echo "ERROR[QUANTUM_CRYPTO_DEMO]: must run from repository root" >&2
  exit 905
fi

if ! command -v rg >/dev/null 2>&1; then
  echo "ERROR[QUANTUM_CRYPTO_DEMO]: rg (ripgrep) not found" >&2
  exit 906
fi

for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "ERROR[QUANTUM_CRYPTO_DEMO]: missing file $f" >&2
    exit 907
  fi
  if ! rg -qF "$MARKER" "$f"; then
    echo "ERROR[QUANTUM_CRYPTO_DEMO]: marker missing in $f (expected $MARKER)" >&2
    exit 908
  fi
done

echo "quantum-crypto-demo-tier-contract-ok"
exit 0
