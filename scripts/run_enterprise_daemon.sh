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
export AZL_NATIVE_ONLY="${AZL_NATIVE_ONLY:-1}"
export AZL_ENABLE_LEGACY_HOST="${AZL_ENABLE_LEGACY_HOST:-0}"
export AZL_NATIVE_RUNTIME_CMD="${AZL_NATIVE_RUNTIME_CMD:-bash scripts/azl_c_interpreter_runtime.sh}"

echo "🔑 API Token: $AZL_API_TOKEN"
echo "📁 Config: $AZL_BUILD_CONFIG"
echo "🌐 Port: $AZL_BUILD_API_PORT"

# Ensure sysproxy is running and listening (start locally if not)
ok=1
if command -v timeout >/dev/null 2>&1; then
  timeout 1 bash -lc 'exec 5<>/dev/tcp/127.0.0.1/9099; exec 5>&-' >/dev/null 2>&1 && ok=0 || ok=1
else
  {
    exec 5<>/dev/tcp/127.0.0.1/9099
    ok=$?
    exec 5>&-
  } 2>/dev/null || ok=1
fi
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
  "azl/runtime/bootstrap/azl_pure_azme_runtime.azl"
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
  "azl/stdlib/core/simd.azl"
  "azl/core/error_system.azl"
  "azl/runtime/interpreter/azl_interpreter.azl"
  "azl/bootstrap/azl_pure_launcher.azl"
  "azl/diag/env_probe.azl"
  "azl/diag/net_probe.azl"
  # Core wiring for command/training/runtime integration
  "azl/core/execution/command_processor.azl"
  "azl/extensions/training_plugin_manager.azl"
  "azl/runtime/integration/azl_runtime_integration.azl"
  "azl/orchestrator/parallel_training_orchestrator.azl"
  "azl/orchestrator/training_worker_pool.azl"
  "azl/orchestrator/metrics.azl"
  "azme/system/azme_plugin_host.azl"
  "azme/integrations/azme_plugin_registry.azl"
  "azme/security/security_policy_rules.azl"
  "azme/interface/azme_speech_synthesis.azl"
  "azme/perception/azme_vision_processor.azl"
  # Full training stack (AZME/AZL/Quantum/LHA3)
  "azl/orchestrator/comprehensive_training_controller.azl"
  "azl/nlp/advanced_training_system.azl"
  "azl/neural/model_loader.azl"
  "azl/neural/real_neural_network.azl"
  "azl/neural/qwen_72b_quantum_attention.azl"
  "azl/core/neural/neural.azl"
  "azl/core/memory/memory.azl"
  "azl/memory/lha3_memory_system.azl"
  "azl/memory/lha3_quantum_memory.azl"
  "azl/quantum/memory/lha3_quantum_engine.azl"
  "azl/memory/memory_optimization_system.azl"
  "azl/memory/fractal_memory_compression.azl"
  "azl/storage/memory_persistence_system.azl"
  "azl/system/advanced_event_system.azl"
  "azl/quantum/processor/quantum_processor.azl"
  "azl/quantum/processor/quantum_core.azl"
  "azl/quantum/processor/quantum_ai_pipeline.azl"
  "azl/quantum/processor/quantum_behavior_modeling.azl"
  "azl/quantum/memory/quantum_entanglement_network.azl"
  "azl/quantum/processor/quantum_encryption.azl"
  "azl/quantum/real_quantum_processor.azl"
  "azl/quantum/optimizer/quantum_optimizer.azl"
  "azl/quantum/mathematics/quantum_topology.azl"
  "azl/quantum/mathematics/quantum_geometry.azl"
  "azl/monitoring/quantum_dashboard.azl"
  "azl/monitoring/performance_analytics_system.azl"
  "azl/security/capabilities.azl"
  "azl/observability/runtime_inspector.azl"
  "azl/weights/registry.azl"
  # AZME interfaces
  "azme/core/agi_core.azl"
  "azme/core/autonomous_brain.azl"
  "azme/learning/azme_actual_dataset_training.azl"
  "azme/learning/azme_clean_dataset_training.azl"
  "azme/interface/azme_chat_interface.azl"
  "azme/interface/azme_command_interface.azl"
  "azme/interface/azme_voice_event_bridge.azl"
  "azme/interface/azme_action_decider.azl"
  "azme/cognitive/azme_cognitive_loop.azl"
  "azme/consciousness/azme_belief_system.azl"
  "azme/collaboration/azme_message_router.azl"
  "azme/collaboration/azme_peer_registry.azl"
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

# Canonical native bootstrap entry expected by seed/native launcher.
cat >> "$COMBINED" <<'AZL'
# ===== EMBEDDED: Native Boot Entry =====
component ::boot.entry {
  init {
    emit "build.daemon.enterprise.start"
  }
}
AZL

# Activate memory/quantum optimization modules early in startup.
cat >> "$COMBINED" <<'AZL'
# ===== EMBEDDED: Native Performance Activation =====
component ::native.performance.activation {
  init {
    emit "initialize_memory_optimization"
    emit "initialize_fractal_compression"
    emit "initialize_performance_analytics"
    emit "start_quantum_monitoring"
    emit "initialize_lha3_memory" to ::memory.lha3_quantum with {
      p_adic_prime: 7,
      precision: 10,
      max_dimensions: 64,
      ram_limit_gb: 2
    }
    emit "initialize_lha3_quantum_engine" to ::quantum.memory.lha3_quantum_engine with {
      p_adic_prime: 7,
      precision: 10,
      max_dimensions: 64,
      target_compression_ratio: 0.85
    }
    emit "initialize_hyperdimensional_vectors" to ::quantum.memory.lha3_quantum_engine with {
      vector_count: 16,
      dimensions: 64
    }
    emit "initialize_memory_persistence" with { system_id: "native_enterprise", config: {} }
    emit "initialize_advanced_event_system" with { system_id: "native_enterprise", config: {} }
    emit "start_performance_measurement" with {}
    emit "quantum.core.initialize" to ::quantum.core with {
      mode: "canonical_native"
    }
    emit "initialize_quantum_entanglement_network" to ::quantum.entanglement.network with {
      network_id: "native_quantum_mesh",
      config: { topology: "mesh", coherence_mode: "stable" }
    }
    emit "inspector.snapshot" to ::azl.runtime_inspector with {}
    emit "register_peer" to ::azme.peer_registry with {
      peer_id: "azme_local_core",
      capabilities: ["quantum_enhanced", "communication", "routing", "command_execution"],
      metadata: { role: "core", status: "active" }
    }
    emit "send_message" to ::azme.message_router with {
      peer_id: "azme_local_core",
      message: {
        type: "status_update",
        timestamp: ::internal.now(),
        quantum_enhanced: true,
        sender_id: "native.performance.activation",
        session_id: "bootstrap"
      }
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
DAEMON_LOG_PATH=".azl/daemon.out"
# Some environments may leave a root-owned daemon.out from prior runs.
# Fall back to a user-owned log file if daemon.out is not writable.
if ! (touch "$DAEMON_LOG_PATH" >/dev/null 2>&1); then
  DAEMON_LOG_PATH=".azl/daemon.${USER:-user}.out"
  touch "$DAEMON_LOG_PATH"
fi
if [ "${AZL_SYSTEMD:-0}" = "1" ]; then
  # Under systemd: avoid extra tee/stdbuf processes; log directly
  scripts/azl_bootstrap.sh "$COMBINED" "::build.daemon.enterprise" >> "$DAEMON_LOG_PATH" 2>&1 &
  echo $! > .azl/daemon.pid
else
  # Interactive/dev mode: keep previous behavior with tees
  stdbuf -oL -eL scripts/azl_bootstrap.sh "$COMBINED" "::build.daemon.enterprise" 2>&1 \
    | stdbuf -oL tee "$DAEMON_LOG_PATH" \
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
