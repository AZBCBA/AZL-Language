AZL/AZME architecture overview
==============================

**Architecture Status [VERIFIED]:**
- Runtime: Pure AZL interpreter (`azl/runtime/interpreter/azl_interpreter.azl`) executes components, say/set/emit, with listener registry, payloads, and cycle guard.
- Stdlib: Pure AZL (`azl/stdlib/core/azl_stdlib.azl`) with deterministic RNG/time, in-memory FS/HTTP, arrays/strings/math; no external dependencies.
- System Interface: Virtual OS in pure AZL (`azl/system/azl_system_interface.azl`) providing a unified syscall surface (fs/http/console/proc) for build and tools.
- Gaps: Native compiler and kernel syscalls are design-only; bytecode/VM docs are aspirational (see deprecation note below).

Production path [VERIFIED current path]
---------------
- Boot: `runtime_boot.azl` (deferred `azl.begin` → emits application events)
- Error: `azl/core/error_system.azl` (collects `log_error`, summarizes)
- NLP: `azl/nlp/{nlp_orchestrator,quantum_byte_processor,utf8_aggregator,weight_storage}.azl`
- Quantum: `azl/quantum/processor/{quantum_core,quantum_ai_pipeline,quantum_behavior_modeling,quantum_processor}.azl`
- AZME (root entry bundles): `project/entries/azl/azme_chat_integration.azl`, `azme/runtime/{azme_unified_runtime,azme_runtime_bootstrap}.azl`, `azme/cognitive/azme_cognitive_loop.azl`

Event contracts
---------------
- chat.request → generate.text.bytes → stream.utf8 → azme.chat.response (under test; behavior execution path wired)
- system.boot → unified_runtime + runtime_bootstrap → azme.runtime_ready → cognitive_loop (WIP)
- weights.load → weights.loaded|weights.error (WIP)

Run [VERIFIED]
---
- Load components via the interpreter; listeners registered first, boot last.

Policy [VERIFIED]
------
- Deterministic mode by default; non-daemon default exits after first response (`azl.exit`).

Deprecated/Design-only docs
---------------------------
- `docs/RUST_INTERPRETER_SPEC.md` and `docs/BYTECODE_VM_SPEC.md` are design documents and not representative of the current pure-AZL runtime. Use this overview and the files cited above as the source of truth.


