#!/usr/bin/env bash
# Emit a bootstrap bundle (# AZL-BOOTSTRAP v1) that wraps COMBINED + ENTRY.
# Same payload as scripts/azl_bootstrap.sh (single source of truth).
# Usage:
#   scripts/build_azl_bootstrap_bundle.sh <combined.azl> <::entry> > bundle.azl
#   scripts/build_azl_bootstrap_bundle.sh <combined> <::entry> --out path.azl
set -euo pipefail

COMBINED="${1:-}"
ENTRY="${2:-}"
OUT_PATH=""
if [ "${3:-}" = "--out" ] && [ -n "${4:-}" ]; then
  OUT_PATH="$4"
fi

if [ -z "$COMBINED" ] || [ -z "$ENTRY" ]; then
  echo "usage: $0 <combined.azl> <::entry> [--out bundle.azl]" >&2
  exit 2
fi
if [ ! -f "$COMBINED" ]; then
  echo "ERROR: combined file not found: $COMBINED" >&2
  exit 3
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

emit_bundle() {
  echo '# AZL-BOOTSTRAP v1'
  echo "## ENTRY: $ENTRY"
  echo "## COMBINED: $COMBINED"
  echo

  cat azl/kernel/azl_kernel.azl
  cat azl/system/azl_system_interface.azl
  cat azl/core/error_system.azl
  cat azl/runtime/interpreter/azl_interpreter.azl
  cat azl/runtime/vm/azl_vm.azl
  cat azl/core/compiler/azl_bytecode.azl
  cat azl/core/azl/self_execution_engine.azl
  cat azl/bootstrap/azl_pure_launcher.azl
  cat azl/host/exec_bridge.azl

  cat <<'AZL'
component ::boot.entry {
  init {
    say "exec_bridge: AZL_BOOT: calling pure launcher..."
    
    # Instead of calling the launcher on the combined file (which creates a loop),
    # we'll directly execute the exec_bridge component which contains our trampoline
    say "🚀 Direct execution of exec_bridge component..."
    
    # Link and execute the exec_bridge component
    link ::host.exec_bridge
    
    # The exec_bridge component should now run its init block with the trampoline
    say "✅ exec_bridge component linked and should be executing"
  }
}
AZL
}

if [ -n "$OUT_PATH" ]; then
  emit_bundle >"$OUT_PATH"
else
  emit_bundle
fi
