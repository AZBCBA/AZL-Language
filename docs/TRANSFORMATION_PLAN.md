## AZL Program Transformation Plan (Production)

This document specifies the end-to-end transformation from a prototype-heavy ecosystem to a production-grade AZL platform. It defines deliverables, acceptance criteria, quality gates, and error-handling requirements for each phase. All features MUST adhere to strict-mode defaults and error-first behavior.

### Status (Phase 1 progress)
- **Completed**: expanded `AzlError` taxonomy (added `Timeout`, `Cycle`, `Ffi`); strict-mode gating wired into runtime hooks; EventBus recursion guard, cycle detection and per-listener timeout; `nalgebra`/`tokio`/`tracing` dependencies added; initial FFI math bridge implemented (`ffi_matmul`, `ffi_eigen_symmetric`, `ffi_complex_mul`); runtime matrix multiply now uses `nalgebra`; EventBus now includes bounded batch processing with priority queues (critical/high/medium/low) and non-recursive dispatch loop; tracing spans added for `emit`, `process_events`, `dispatch_event`, and handler execution; FFI placeholder elimination completed in model forward path (attention/LM head/sampling now placeholder-free). *[VERIFIED: src/lib.rs spans on emit/process/dispatch/handler; src/ffi.rs forward/attention/LM/sampling cleaned]*
- **In progress**: comprehensive type coercion rules + unit tests; scoped memory management (usage metrics, cleanup); tracing span wiring across event enqueue/dispatch and handlers; CI test stages and coverage gates. *[STATUS: Basic type ops implemented (src/lib.rs:118-153); memory tracking exists but scoped cleanup missing; tracing deps added but spans not wired yet]*
 - **In progress**: comprehensive type coercion rules + unit tests; scoped memory management (usage metrics, cleanup); tracing span wiring across event enqueue/dispatch and handlers; CI test stages and coverage gates. *[STATUS UPDATE: Precedence-aware expression evaluation for `+`/`*` and parentheses added (src/lib.rs:evaluate_expression), basic scoped cleanup for handler vars added; tracing span on `emit` merged]*
- **Not started (per plan)**: v2 interpreter/bytecode compiler/VM (Phases 2–3). *[CONFIRMED: No lexer/parser/AST/VM code in src/, correctly following phased approach]*

### Guiding Principles
- Build real functionality first; no placeholders in production paths
- Strict mode on by default (CI, releases); opt-in for experimental hooks
- Error system everywhere: typed errors, spans, context, recovery
- Deterministic behavior; testable seams; reproducible builds
- Documentation, observability, and tests are required parts of "done"

**🚨 CURRENT PRODUCTION READINESS STATUS:**
- **PHASE 1**: ~85% complete but has critical gaps (comprehensive tests, scoped memory cleanup, tracing spans)
- **PHASE 2-10**: NOT STARTED - all documentation for these phases describes THEORETICAL FEATURES
- **CRITICAL PLACEHOLDERS FOUND**: 17+ placeholder implementations across AZL codebase
- **DEPLOYMENT RISK**: System not ready for production deployment despite documentation claims
- **INTEGRATION GAPS**: Many documented features not integrated with actual runtime implementation

### Phases, Scope and Acceptance Criteria

1. Phase 1 (Weeks 1–2): Solidify Core Foundation
   - Runtime: enhanced type system validation, runtime type checking, minimal type inference for assignment, improved `AzlValue` operations and coercions
   - Memory: scoped variable lifetimes; deterministic cleanup on scope exit; memory usage metrics; no leaks under soak tests
   - Events: FIFO queue with optional priority; recursion guard; timeouts; trace logs; batch dispatch without starvation
   - Errors: unified error taxonomy; span + context capture; non-fatal recovery policies
   - FFI: safe bridges; explicit error surfaces; hard-disable speculative hooks under `AZL_STRICT=1`
   - Acceptance: cargo build + 90% unit coverage for runtime core; property tests for expression evaluation; 0 panics in strict CI; benchmarks stable within regression thresholds

2. Phase 2 (Weeks 3–5): Real AZL Interpreter (Rust)
   - Lexer/Parser: recursive-descent aligned to `docs/language/azl_v2_grammar.bnf` with position tracking and recovery
   - AST + Interpreter: lexical scoping, functions, control flow, events; integration with Rust EventBus; span-rich errors
   - Acceptance: golden tests for parsing; end-to-end execution tests for variables/functions/events; fuzz tests for parser stability

3. Phase 3 (Weeks 6–8): Bytecode Compiler + VM
   - Compiler: AST → bytecode with constant pool, symbol tables, and basic optimizations (const folding, DCE)
   - VM: stack machine with instruction set, call frames, error checks, GC hooks
   - Acceptance: bytecode disassembly tests; VM conformance suite; interpreter-vs-VM equivalence tests for a shared corpus

4. Phase 4 (Weeks 9–11): Real Memory Systems
   - Hierarchical memory; persistence; snapshots; usage analytics
   - Acceptance: durability tests; compaction/fragmentation tests; stress tests with bounded memory

5. Phase 5 (Weeks 12–15): Minimal Real AI Foundation
   - Decision/learning primitives (rule-based, probabilistic), episodic/semantic memory wiring
   - Acceptance: task suites with measurable success criteria; deterministic replay

6. Phase 6 (Weeks 16–19): Real NN + NLP Foundations
   - Forward/backward passes, batching; tokenization/NLP pipeline with validated metrics
   - Acceptance: training loop tests (loss decreases on a toy dataset); quality baselines

7. Phase 7 (Weeks 20–23): Quantum Computing (Optional/Experimental)
   - Only under non-strict builds with clear experimental flags
   - Acceptance: correctness validated by reference simulators; isolated from production paths

8. Phase 8 (Weeks 24–26): Full Integration
   - Unified event bus; data pipelines; persistence
   - Acceptance: integration tests; soak testing; failure-injection testing

9. Phase 9 (Weeks 27–29): Performance & Testing
   - Profiling, parallelism, caching; >90% coverage; property + fuzz testing
   - Acceptance: performance SLOs; coverage gates in CI

10. Phase 10 (Weeks 30–32): Deployment & Ops
    - Containers, orchestration, monitoring/alerting; docs complete
    - Acceptance: blue/green deploys; runbooks; on-call readiness

### Quality Gates (Global)
- Code coverage ≥ 90% (runtime/interpreter/compiler/VM)
- p95 response for basic ops < 100ms on reference hardware
- Memory < 1GB for standard workloads; no unbounded growth in soak
- Reliability ≥ 99.9% for the long-running runtime under test workloads

### Error System (Global Requirements)
- Every subsystem returns typed errors with spans and call-context
- Non-fatal recovery where applicable; fatal conditions must fail fast
- Errors recorded with structured fields (component, op, span, cause)
- CI denies any panics; all unexpected conditions must produce typed errors

### Deliverables Index
- Interpreter spec: `docs/RUST_INTERPRETER_SPEC.md`
- Compiler/VM spec: `docs/BYTECODE_VM_SPEC.md`
- Error handling: `docs/ERROR_SYSTEM.md`
- Strict mode: `docs/STRICT_MODE_AND_FEATURE_FLAGS.md`
- Observability: `docs/OBSERVABILITY.md`
- Testing strategy: `docs/TESTING_STRATEGY.md`
- CI/CD pipeline: `docs/CI_CD_PIPELINE.md`
- Readiness checklists: `docs/ENGINEERING_READINESS_CHECKLIST.md`
- Contributing: `docs/CONTRIBUTING.md`


