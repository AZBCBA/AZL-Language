#!/bin/bash
set -eu

# AZL Enterprise Daemon Runner - Pure AZL Execution
# This script combines all components and executes the daemon

echo "🚀 AZL Enterprise Daemon Runner"
echo "⚡ PURE AZL EXECUTION - NO EXTERNAL DEPENDENCIES!"
echo ""

# Set environment variables (respect existing values; provide sane defaults)
export AZL_API_TOKEN="${AZL_API_TOKEN:-$(openssl rand -hex 32)}"
export AZL_BUILD_CONFIG="${AZL_BUILD_CONFIG:-config/prod.azl.json}"
export AZL_BUILD_API_ENABLED="${AZL_BUILD_API_ENABLED:-true}"
export AZL_BUILD_API_PORT="${AZL_BUILD_API_PORT:-8080}"
export AZL_HTTP_PORT="${AZL_HTTP_PORT:-}"  # optional separate AZL http server port
export AZL_WIRE_MANAGED=1

echo "🔑 API Token: $AZL_API_TOKEN"
echo "📁 Config: $AZL_BUILD_CONFIG"
echo "🌐 Port: $AZL_BUILD_API_PORT"

# Ensure sysproxy is running and listening (start locally if not)
{
  exec 5<>/dev/tcp/127.0.0.1/9099
  ok=$?
  exec 5>&-
} 2>/dev/null || ok=1
if [ "${ok}" != "0" ]; then
  echo "🔧 Starting local sysproxy on 127.0.0.1:9099"
  mkdir -p .azl || true
  if [ ! -x .azl/sysproxy ]; then
    echo "🛠️  Building sysproxy..."
    gcc -O2 -o .azl/sysproxy tools/sysproxy.c
  fi
  SYSPROXY_TCP=127.0.0.1:9099 SYSFIFO_IN=.azl/engine.in SYSFIFO_IN_KEEP=1 .azl/sysproxy 2>.azl/sysproxy.log &
  echo $! > .azl/sysproxy.pid
  sleep 0.2
fi

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
: "${TMPDIR:=/tmp}"; mkdir -p "$TMPDIR"
COMBINED="${TMPDIR}/azl_enterprise_$$.azl"
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
  "azl/diag/env_probe.azl"
  "azl/diag/net_probe.azl"
  # Full training stack (AZME/AZL/Quantum/LHA3)
  "azl/orchestrator/comprehensive_training_controller.azl"
  "azl/nlp/advanced_training_system.azl"
  "azl/neural/model_loader.azl"
  "azl/neural/real_neural_network.azl"
  "azl/neural/qwen_72b_quantum_attention.azl"
  "azl/memory/lha3_memory_system.azl"
  "azl/memory/lha3_adaptive_quantum_engine.azl"
  "azl/quantum/real_quantum_processor.azl"
  "azl/monitoring/quantum_dashboard.azl"
  "azl/weights/registry.azl"
  # AZME memory and interfaces
  "azme/memory/azme_unified_memory_system.azl"
  "azme/core/agi_core.azl"
  "azme/core/autonomous_brain.azl"
  "azme/learning/azme_actual_dataset_training.azl"
  "azme/learning/azme_clean_dataset_training.azl"
  "azme/interface/azme_chat_interface.azl"
  "azme/interface/azme_action_decider.azl"
  "azme/cognitive/azme_cognitive_loop.azl"
  "azme/consciousness/azme_belief_system.azl"
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

# Optional: embed a tiny launcher to start the AZME provider during E2E
cat >> "$COMBINED" <<'AZL'
# ===== EMBEDDED: AZME Provider E2E Launcher =====
component ::e2e.azme_provider_launcher {
  init {
    if ::internal.env("AZME_PROVIDER_E2E") == "1" {
      say "🔌 E2E: Starting AZME Provider on :5000"
      run_server(5000)
    }
  }
}
AZL

# Set environment for execution bridge
export AZL_COMBINED_PATH="$COMBINED"
export AZL_ENTRY="::build.daemon.enterprise"

echo "🚀 Starting AZL Enterprise Daemon..."
echo "📁 Combined file: $COMBINED"
echo "🎯 Entry point: $AZL_ENTRY"
echo ""

echo "🧠 Loading and executing AZL components..."
if [ "${AZL_SYSTEMD:-0}" = "1" ]; then
  # Under systemd: avoid extra tee/stdbuf processes; log directly
  scripts/azl_bootstrap.sh "$COMBINED" "::build.daemon.enterprise" >> .azl/daemon.out 2>&1 &
  echo $! > .azl/daemon.pid
else
  # Interactive/dev mode: keep previous behavior with tees
  stdbuf -oL -eL scripts/azl_bootstrap.sh "$COMBINED" "::build.daemon.enterprise" 2>&1 \
    | stdbuf -oL tee .azl/daemon.out \
    | stdbuf -oL tee .azl/engine.out \
    >/dev/null &
  echo $! > .azl/daemon.pid
fi

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
