#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

: "${TMPDIR:=/tmp}"; mkdir -p "$TMPDIR"
COMBINED="${TMPDIR}/azl_full_$$.azl"
cat \
  azl/kernel/azl_kernel.azl \
  azl/core/modules/azl_module_system.azl \
  azl/bootstrap/azl_pure_launcher.azl \
  azl/core/compiler/azl_compiler.azl \
  azl/core/compiler/azl_bytecode.azl \
  azl/runtime/vm/azl_vm.azl \
  azl/stdlib/core/azl_stdlib.azl \
  azl/core/ast_event_bus.azl \
  azl/memory/lha3_memory_system.azl \
  azl/core/error_system.azl \
  azl/runtime/bootstrap/azl_pure_azme_runtime.azl \
  azl/nlp/nlp_orchestrator.azl azl/nlp/utf8_aggregator.azl \
  azl/nlp/quantum_byte_processor.azl azl/nlp/weight_storage.azl \
  azl/ffi/fs.azl \
  azl/ffi/torch.azl \
  azl/system/azl_system_interface.azl \
  azl/quantum/processor/quantum_core.azl \
  azl/quantum/processor/quantum_ai_pipeline.azl \
  azl/quantum/processor/quantum_behavior_modeling.azl \
  azl/quantum/processor/quantum_processor.azl \
  azme_chat_integration.azl \
  azme/runtime/azme_unified_runtime.azl azme/runtime/azme_runtime_bootstrap.azl \
  azme/cognitive/azme_cognitive_loop.azl \
  runtime_boot.azl \
  train_real_models.azl > "$COMBINED"

echo "Combined AZL created at: $COMBINED"
echo "Invoking pure AZL launcher to run: $COMBINED"

# Run through pure launcher main (compile → vm execute) by emitting a run command via a tiny driver
DRIVER="${TMPDIR}/azl_driver_$$.azl"
cat > "$DRIVER" <<'AZL'
component ::driver.run {
  init {
    say "🔧 driver: launching"
    # Directly kick the unified boot path instead of CLI indirection
    emit "azl.begin" with {}
    emit "system.boot" with { origin: "run_full" }
    # Auto-start advanced training via orchestrator when AZL_TRAIN_ADVANCED=1
    set ds = (::internal.env("AZL_DATASET") or "")
    set dev = (::internal.env("AZL_DEVICE") or "auto")
    set gl  = parseInt((::internal.env("AZL_GPU_LIMIT") or "0"))
    set ep  = parseInt((::internal.env("AZL_EPOCHS") or "1"))
    set bs  = parseInt((::internal.env("AZL_BATCH") or "1"))
    set adv = (::internal.env("AZL_TRAIN_ADVANCED") or "0")
    # Ensure training orchestrator is linked and ready
    link ::train.real_models
    link ::ffi.torch
    # Kick orchestrator-mode training queue if requested
    if ((::internal.env("AZL_TRAIN_RM_MODE") or "orchestrator") == "orchestrator") {
      emit "start_advanced_training_from_list" to ::train.real_models
    } else if (adv == "1" && ds != "") {
      # Legacy direct path (kept for compatibility)
      say "🚀 driver: requesting direct advanced training"
      emit "train_file" to ::ffi.torch with { data_path: ds, device: dev, steps: ep, batch_size: bs, lr: 0.0003, save: "weights/direct.pt", save_every: 10000, log_tsv: "logs/direct.tsv" }
    }
  }
}
AZL

cat "$DRIVER" "$COMBINED" > "$COMBINED.run"
echo "Prepared: $COMBINED.run"
echo "Load $COMBINED.run into your pure AZL runner to execute"
