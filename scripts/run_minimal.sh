#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
AZL_LOG_LEVEL=quiet AZL_STRICT=1 ./target/release/azl run \
  azl/core/ast_event_bus.azl \
  azl/memory/lha3_adaptive_quantum_engine.azl \
  azl/nlp/utf8_aggregator.azl \
  azl/nlp/nlp_orchestrator.azl \
  azl/nlp/quantum_byte_processor.azl \
  runtime_boot.azl | cat


