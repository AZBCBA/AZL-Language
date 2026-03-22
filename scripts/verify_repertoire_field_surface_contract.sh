#!/usr/bin/env bash
# Ensures RepertoireField public naming + canonical quantum surface files stay documented and on disk.
# See docs/AZL_GPU_NEURAL_SURFACE_MAP.md §0. Prefix ERROR[REPERTOIREFIELD_SURFACE]: on stderr.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

DOC="docs/AZL_GPU_NEURAL_SURFACE_MAP.md"
ANCHOR="REPERTOIREFIELD_SURFACE_CONTRACT_V1"
CANON="azl/quantum/real_quantum_processor.azl"
IMPL_SCOPE_MARK="REPERTOIREFIELD_IMPL_SCOPE=canonical_qc_numeric_processor"

if [ ! -f "Makefile" ] || [ ! -d "azl/quantum" ]; then
  echo "ERROR[REPERTOIREFIELD_SURFACE]: must run from repository root" >&2
  exit 230
fi

if [ ! -f "$DOC" ]; then
  echo "ERROR[REPERTOIREFIELD_SURFACE]: missing $DOC" >&2
  exit 231
fi

if ! command -v rg >/dev/null 2>&1; then
  echo "ERROR[REPERTOIREFIELD_SURFACE]: rg (ripgrep) not found" >&2
  exit 232
fi

if ! rg -q "$ANCHOR" "$DOC"; then
  echo "ERROR[REPERTOIREFIELD_SURFACE]: contract anchor missing in $DOC (expected $ANCHOR)" >&2
  exit 233
fi

if ! rg -q "RepertoireField" "$DOC"; then
  echo "ERROR[REPERTOIREFIELD_SURFACE]: public name RepertoireField missing in $DOC" >&2
  exit 234
fi

if [ ! -f "$CANON" ]; then
  echo "ERROR[REPERTOIREFIELD_SURFACE]: canonical processor missing: $CANON" >&2
  exit 235
fi

if ! rg -qF "$IMPL_SCOPE_MARK" "$CANON"; then
  echo "ERROR[REPERTOIREFIELD_SURFACE]: impl scope marker missing in $CANON (expected $IMPL_SCOPE_MARK)" >&2
  exit 236
fi

echo "repertoire-field-surface-contract-ok"
exit 0
