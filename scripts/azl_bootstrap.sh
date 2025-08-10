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

# If input already a bootstrap, do not re-wrap it
if head -n 1 "$INPUT" 2>/dev/null | grep -q '^# AZL-BOOTSTRAP v1'; then
  BUNDLE="$INPUT"
else
  BUNDLE="$(mktemp -t azl_bootstrap.XXXXXX.azl)"
  # trap 'rm -f "$BUNDLE"' EXIT  # Commented out for debugging

  {
    echo '# AZL-BOOTSTRAP v1'
    echo "## ENTRY: $ENTRY"
    echo "## COMBINED: $INPUT"
    echo

    # ===== Runtime (overwrite, not append) =====
    # IMPORTANT: every cat below is an append *to this one new file*,
    # but we started with a clean file thanks to the block above.
    cat azl/kernel/azl_kernel.azl
    cat azl/system/azl_system_interface.azl
    cat azl/core/error_system.azl
    cat azl/runtime/interpreter/azl_interpreter.azl
    cat azl/runtime/vm/azl_vm.azl
    cat azl/core/compiler/azl_bytecode.azl
    cat azl/core/azl/self_execution_engine.azl
    cat azl/bootstrap/azl_pure_launcher.azl
    cat azl/host/exec_bridge.azl

    # Final tiny boot component that calls the launcher on $INPUT/$ENTRY
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
  } > "$BUNDLE"
fi

# Set env vars for the launcher, but DO NOT spawn any more bootstrap steps
export AZL_COMBINED_PATH="$INPUT"
export AZL_ENTRY="$ENTRY"
echo "bootstrap: ready bundle $BUNDLE (entry=$ENTRY)"
echo "bootstrap: executing with seed runner..."

# Execute the bootstrap bundle with the seed runner
exec "$(dirname "$0")/azl_seed_runner.sh" "$BUNDLE"
