#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

COMBINED="/tmp/azl_full_$$.azl"
cat \
  azl/kernel/azl_kernel.azl \
  azl/core/modules/azl_module_system.azl \
  azl/bootstrap/azl_pure_launcher.azl \
  azl/core/compiler/azl_compiler.azl \
  azl/core/compiler/azl_bytecode.azl \
  azl/runtime/vm/azl_vm.azl \
  azl/stdlib/core/azl_stdlib.azl \
  azl/core/ast_event_bus.azl \
  azl/memory/lha3_adaptive_quantum_engine.azl \
  azl/core/error_system.azl \
  azl/runtime/bootstrap/azl_pure_azme_runtime.azl \
  azl/nlp/nlp_orchestrator.azl azl/nlp/utf8_aggregator.azl \
  azl/nlp/quantum_byte_processor.azl azl/nlp/weight_storage.azl \
  azl/quantum/processor/quantum_core.azl \
  azl/quantum/processor/quantum_ai_pipeline.azl \
  azl/quantum/processor/quantum_behavior_modeling.azl \
  azl/quantum/processor/quantum_processor.azl \
  azme_chat_integration.azl \
  azme/runtime/azme_unified_runtime.azl azme/runtime/azme_runtime_bootstrap.azl \
  azme/cognitive/azme_cognitive_loop.azl \
  runtime_boot.azl > "$COMBINED"

echo "Combined AZL created at: $COMBINED"
echo "Invoking pure AZL launcher to run: $COMBINED"

# Run through pure launcher main (compile → vm execute) by emitting a run command via a tiny driver
DRIVER="/tmp/azl_driver_$$.azl"
cat > "$DRIVER" <<'AZL'
component ::driver.run {
  init {
    say "🔧 driver: launching"
    # Expect ::internal.args[1] to be file path
    set path = ::internal.args[1]
    emit launcher.main with { args: ["azl", "run", path] }
  }
}
AZL

cat "$DRIVER" "$COMBINED" > "$COMBINED.run"
echo "Prepared: $COMBINED.run"
echo "Load $COMBINED.run into your pure AZL runner to execute"
