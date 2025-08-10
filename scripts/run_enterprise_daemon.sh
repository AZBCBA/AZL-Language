#!/bin/bash
set -eu

# AZL Enterprise Daemon Runner - Pure AZL Execution
# This script combines all components and executes the daemon

echo "🚀 AZL Enterprise Daemon Runner"
echo "⚡ PURE AZL EXECUTION - NO EXTERNAL DEPENDENCIES!"
echo ""

# Set environment variables
export AZL_API_TOKEN="${AZL_API_TOKEN:-$(openssl rand -hex 32)}"
export AZL_BUILD_CONFIG="config/prod.azl.json"
export AZL_BUILD_API_ENABLED="true"
export AZL_BUILD_API_PORT="8080"
export AZL_WIRE_MANAGED=1

echo "🔑 API Token: $AZL_API_TOKEN"
echo "📁 Config: $AZL_BUILD_CONFIG"
echo "🌐 Port: $AZL_BUILD_API_PORT"

# Create cache directory and ensure FIFOs exist
mkdir -p .azl/cache
rm -f .azl/engine.out .azl/engine.in
mkfifo .azl/engine.out .azl/engine.in 2>/dev/null || true

# Start the wire first (so FIFO has a reader before engine writes)
echo "🔌 Starting wire..."
bash scripts/azl_syswire.sh .azl/engine.out .azl/engine.in 2>.azl/wire.log &
echo $! > .azl/syswire.pid
sleep 0.2  # Give wire time to start

# Create combined AZL file with all components
COMBINED="/tmp/azl_enterprise_$$.azl"
echo "📦 Creating combined AZL file..."

cat > "$COMBINED" << 'AZL'
# AZL Enterprise Daemon Combined File
# This file contains all components needed for the enterprise daemon

# Core components
AZL

# Add all the required components
COMPONENTS=(
  "azl/host/exec_bridge.azl"
  "azl/runtime/bootstrap.azl"
  "azl/core/events.azl"
  "azl/core/internal.azl"
  "azl/api/endpoints.azl"
  "azl/system/http_server.azl"
  "azl/build/build_daemon_enterprise.azl"
  "azl/build/build_orchestrator.azl"
  "azl/build/worker_pool.azl"
  "azl/build/cache_manager.azl"
  "azl/system/azl_system_interface.azl"
  "azl/stdlib/core/azl_stdlib.azl"
  "azl/core/error_system.azl"
  "azl/runtime/interpreter/azl_interpreter.azl"
  "azl/bootstrap/azl_pure_launcher.azl"
  "azl/compat/launcher_shim.azl"
  "azl/compat/interpreter_shim.azl"
  "azl/diag/env_probe.azl"
  "azl/diag/net_probe.azl"
)

for component in "${COMPONENTS[@]}"; do
  if [ -f "$component" ]; then
    echo "📦 Adding: $component"
    echo "" >> "$COMBINED"
    echo "# ===== FILE: $component ===== " >> "$COMBINED"
    cat "$component" >> "$COMBINED"
  else
    echo "⚠️  Warning: Component not found: $component"
  fi
done

echo "✅ Combined file created: $COMBINED"

# Set environment for execution bridge
export AZL_COMBINED_PATH="$COMBINED"
export AZL_ENTRY="::build.daemon.enterprise"

echo "🚀 Starting AZL Enterprise Daemon..."
echo "📁 Combined file: $COMBINED"
echo "🎯 Entry point: $AZL_ENTRY"
echo ""

# Execute the combined file using the Stage-0 bootstrap
# Line-buffer stdout & stderr, tee to daemon log, then tee to the FIFO
echo "🧠 Loading and executing AZL components..."
stdbuf -oL -eL scripts/azl_bootstrap.sh "$COMBINED" "::build.daemon.enterprise" 2>&1 \
  | stdbuf -oL tee .azl/daemon.out \
  | stdbuf -oL tee .azl/engine.out \
  >/dev/null &
echo $! > .azl/daemon.pid

echo ""
echo "🎉 AZL Enterprise Daemon execution initiated!"
echo "🌐 API: http://localhost:$AZL_BUILD_API_PORT"
echo "🔑 Token: $AZL_API_TOKEN"
echo ""
echo ""
echo "📊 Test endpoints:"
echo "  curl http://localhost:$AZL_BUILD_API_PORT/healthz"
echo "  curl http://localhost:$AZL_BUILD_API_PORT/readyz"
echo "  curl http://localhost:$AZL_BUILD_API_PORT/status"
echo ""
