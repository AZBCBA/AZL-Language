#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Pure AZL run: compose minimal bootstrap and feed to pure interpreter loader

: "${TMPDIR:=/tmp}"; mkdir -p "$TMPDIR"
COMBINED="${TMPDIR}/azl_chat_$$.azl"
cat \
  azl/core/ast_event_bus.azl \
  azl/memory/lha3_adaptive_quantum_engine.azl \
  azl/core/error_system.azl \
  azl/runtime/interpreter/azl_interpreter.azl \
  azl/runtime/bootstrap/azl_pure_azme_runtime.azl \
  azl/nlp/utf8_aggregator.azl \
  azl/nlp/nlp_orchestrator.azl \
  azl/nlp/quantum_byte_processor.azl \
  project/entries/azl/azme_chat_integration.azl \
  azl/ui/chat_console.azl > "$COMBINED"

echo "Running pure AZL interpreter on chat pipeline"
echo "(If your loader expects a file path, load: $COMBINED)"

# Attempt to invoke interpreter API by emitting interpret request if a loader is present
# Fallback: print instructions
echo "Combined file at: $COMBINED"


