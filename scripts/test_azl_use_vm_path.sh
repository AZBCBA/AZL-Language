#!/usr/bin/env bash
# Option B: AZL_USE_VM contract — static wiring + source parity + eligible fixture.
# Full interpreter E2E (same process, AZL_USE_VM=0 vs 1) is not the default
# enterprise path (C minimal runtime); see docs/AZL_NATIVE_RUNTIME_CONTRACT.md.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 required" >&2
  exit 60
fi

bash scripts/verify_azl_use_vm_path.sh
python3 scripts/check_azl_vm_tree_parity.py

FIXTURE="${ROOT_DIR}/azl/tests/fixtures/vm_parity_minimal.azl"
if [ ! -f "$FIXTURE" ]; then
  echo "ERROR: missing fixture $FIXTURE" >&2
  exit 61
fi

# Fixture must stay within VM-eligible surface (no listen / set / if / fn in source)
if rg -n '\blisten\s+for\b' "$FIXTURE" >/tmp/azl_vm_fix_listen.out 2>&1; then
  echo "ERROR: fixture must not use listen (VM init/behavior contract)" >&2
  cat /tmp/azl_vm_fix_listen.out >&2
  exit 62
fi
if rg -n '\bset\s+' "$FIXTURE" >/tmp/azl_vm_fix_set.out 2>&1; then
  echo "ERROR: fixture must not use set (not VM-compiled yet)" >&2
  cat /tmp/azl_vm_fix_set.out >&2
  exit 63
fi
if rg -n '\bif\s+' "$FIXTURE" >/tmp/azl_vm_fix_if.out 2>&1; then
  echo "ERROR: fixture must not use if (not VM-compiled yet)" >&2
  cat /tmp/azl_vm_fix_if.out >&2
  exit 64
fi
if rg -n '\bfn\s+' "$FIXTURE" >/tmp/azl_vm_fix_fn.out 2>&1; then
  echo "ERROR: fixture must not use fn (not VM-compiled yet)" >&2
  cat /tmp/azl_vm_fix_fn.out >&2
  exit 65
fi

echo "azl-use-vm-test-ok"
