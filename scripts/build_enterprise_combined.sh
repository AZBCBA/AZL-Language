#!/usr/bin/env bash
# Emit the same concatenated enterprise .azl as scripts/run_enterprise_daemon.sh (quantum, LHA3, neural, AZME, …).
# Keep COMPONENT list in sync with that script.
# Usage: scripts/build_enterprise_combined.sh <output.azl>
set -euo pipefail

OUT="${1:-}"
if [ -z "$OUT" ]; then
  echo "usage: $0 <output-combined.azl>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p "$(dirname "$OUT")"
COMBINED="$OUT"

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
  "azl/core/types/tensor.azl"
  "azl/core/error_system.azl"
  "azl/runtime/interpreter/azl_interpreter.azl"
  "azl/core/compiler/azl_bytecode.azl"
  "azl/runtime/vm/azl_vm.azl"
  "azl/bootstrap/azl_pure_launcher.azl"
  "azl/diag/env_probe.azl"
  "azl/diag/net_probe.azl"
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

if [ "${AZL_BUNDLE_INCLUDE_OLLAMA_NATIVE:-0}" = "1" ]; then
  COMPONENTS+=( "azl/integrations/anythingllm/azme_ollama_native.azl" )
fi

for component in "${COMPONENTS[@]}"; do
  if [ -f "$component" ]; then
    echo "" >> "$COMBINED"
    echo "# ===== FILE: $component ===== " >> "$COMBINED"
    cat "$component" >> "$COMBINED"
  else
    echo "ERROR: Component not found: $component" >&2
    exit 3
  fi
done

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

cat >> "$COMBINED" <<'AZL'
# ===== EMBEDDED: Native Boot Entry =====
component ::boot.entry {
  init {
    emit "build.daemon.enterprise.start"
  }
}
AZL

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

echo "build_enterprise_combined: wrote $COMBINED ($(wc -c < "$COMBINED") bytes)"
