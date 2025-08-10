#!/usr/bin/env bash
set -euo pipefail
root_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root_dir"

live_files=(
  azl/core/error_system.azl
  azl/nlp/nlp_orchestrator.azl
  azl/nlp/utf8_aggregator.azl
  azl/nlp/quantum_byte_processor.azl
  azl/nlp/weight_storage.azl
  azl/quantum/processor/quantum_core.azl
  azl/quantum/processor/quantum_ai_pipeline.azl
  azl/quantum/processor/quantum_behavior_modeling.azl
  azl/quantum/processor/quantum_processor.azl
  azme_chat_integration.azl
  azme/runtime/azme_unified_runtime.azl
  azme/runtime/azme_runtime_bootstrap.azl
  azme/cognitive/azme_cognitive_loop.azl
  azl/ui/chat_console.azl
  runtime_boot.azl
)

fail=0

for f in "${live_files[@]}"; do
  # Flag only event-bus style handlers, not local function-style blocks
  # - Quoted event names: on "event.name" { ... }
  # - Dotted event names: on namespace.event { ... }
  if grep -nE '(^|[[:space:]])on[[:space:]]+"[^"]+"[[:space:]]*\{' "$f" >/dev/null \
     || grep -nE '(^|[[:space:]])on[[:space:]]+[A-Za-z0-9_]+\.[A-Za-z0-9_.]+[[:space:]]*\{' "$f" >/dev/null; then
    echo "❌ Handler uses on in live file: $f"
    fail=1
  fi
  if grep -nE "weights_loaded|load_weights" "$f" >/dev/null; then
    echo "❌ Legacy weights events in live file: $f"
    fail=1
  fi
  echo "✅ Audited: $f"
done

if [ $fail -ne 0 ]; then
  echo "Audit failed"; exit 1
fi

echo "Audit passed"
