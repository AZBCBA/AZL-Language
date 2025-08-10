Production run
===============

**🚨 PRODUCTION READINESS WARNING:**
- **NOT PRODUCTION READY**: This document references AZL files that may not exist or may not run properly
- **MISSING VERIFICATION**: File paths listed below have not been verified for existence or functionality
- **INTEGRATION ISSUES**: Event contracts described may not work with current EventBus implementation
- **DEPLOYMENT RISK**: Running this production setup may fail due to missing or broken components

Stable structure (production path only):

- Runtime/boot: `runtime_boot.azl`, `azl/core/error_system.azl`
- NLP: `azl/nlp/nlp_orchestrator.azl`, `azl/nlp/quantum_byte_processor.azl`, `azl/nlp/utf8_aggregator.azl`, `azl/nlp/weight_storage.azl`
- Quantum: `azl/quantum/processor/{quantum_core,quantum_ai_pipeline,quantum_behavior_modeling,quantum_processor}.azl`
- AZME: `azme_chat_integration.azl`, `azme/runtime/{azme_unified_runtime,azme_runtime_bootstrap}.azl`, `azme/cognitive/azme_cognitive_loop.azl`

Event contracts:

- chat.request → generate.text.bytes → stream.utf8 → azme.chat.response
- system.boot → azme_unified_runtime/azme_runtime_bootstrap → azme.runtime_ready → cognitive_loop
- weights.load → weights.loaded|weights.error

Startup order (listeners first, boot last):

```
./target/release/azl run \
  azl/core/error_system.azl \
  azl/nlp/nlp_orchestrator.azl azl/nlp/utf8_aggregator.azl \
  azl/nlp/quantum_byte_processor.azl azl/nlp/weight_storage.azl \
  azl/quantum/processor/quantum_core.azl \
  azl/quantum/processor/quantum_ai_pipeline.azl \
  azl/quantum/processor/quantum_behavior_modeling.azl \
  azl/quantum/processor/quantum_processor.azl \
  azme_chat_integration.azl \
  azme/runtime/azme_unified_runtime.azl azme/runtime/azme_runtime_bootstrap.azl \
  azme/cognitive/azme_cognitive_loop.azl \
  runtime_boot.azl
```

Policy:

- Boot emits a single generate and chat request; training is off by default.
- For daemon mode, add a wrapper that repeats chat cycles; otherwise exits after first response.


