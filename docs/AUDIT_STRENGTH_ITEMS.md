# AZL Strength Items: Have vs Need

Audit of what exists vs what needs to be built to make AZL stronger.

---

## 1. Execution & Runtime

| Item | Status | Location | Action |
|------|--------|----------|--------|
| Bytecode VM | **HAVE** | `azl/runtime/vm/azl_vm.azl` | Wire into enterprise daemon |
| Bytecode compiler | **HAVE** | `azl/core/compiler/azl_bytecode.azl` | Wire into enterprise daemon |
| C interpreter | **HAVE** | `tools/azl_interpreter_minimal.c` | Default runtime ✓ |
| JIT | **NEED** | — | Design in advanced_features.md only |
| Self-hosting (real parser) | **PARTIAL** | azl_self_hosting_integration uses deterministic stubs | Wire to real parser |

---

## 2. Performance

| Item | Status | Location | Action |
|------|--------|----------|--------|
| Parse cache | **HAVE** | `azl_interpreter.azl` perf.tok_cache, ast_cache | Cap 512 ✓ |
| perf_smoke | **HAVE** | `scripts/perf_smoke.sh` | Thresholds (healthz≤1500ms, etc.) |
| Benchmark gate | **NEED** | — | Add CI step: block if AZL regresses >10% vs baseline |
| SIMD primitives | **NEED** | advanced_features.md describes, not implemented | Add simd_add, simd_mul to stdlib |
| Memory-mapped files | **NEED** | — | C interpreter uses malloc; add mmap for large files |

---

## 3. AI Primitives

| Item | Status | Location | Action |
|------|--------|----------|--------|
| Tensor helpers | **HAVE** | quantum_ai_pipeline, qwen_72b, create_tensor | Object-based, not first-class |
| First-class tensor type | **NEED** | — | `tensor shape [n,m]` syntax |
| LHA3 stdlib API | **HAVE** | `docs/LHA3_STDLIB_API.md` | Documented ✓ |
| Quantum gradients | **PARTIAL** | quantum_optimizer, quantum_behavior_modeling | Add language-level `quantum_gradient` |
| Training DSL | **PARTIAL** | comprehensive_training_controller | Add `train X on Y` syntax |

---

## 4. Ecosystem

| Item | Status | Location | Action |
|------|--------|----------|--------|
| .azlpack spec | **HAVE** | `docs/AZLPACK_SPEC.md` | Documented ✓ |
| Package registry | **NEED** | — | HTTP registry, `azl install` |
| pkg_manager | **PARTIAL** | lha3_memory_export (build.pkg_manager) | Extract to real component |
| IDE/LSP | **NEED** | — | Language server for .azl |
| Debugger | **NEED** | — | Breakpoints, step, inspect |
| Profiler | **PARTIAL** | runtime_inspector, performance_analytics | Add event latency profiler |

---

## 5. Grammar & Purity

| Item | Status | Location | Action |
|------|--------|----------|--------|
| Grammar CI | **HAVE** | `verify_azl_grammar_conformance.sh` | Blocks var/const/print/etc ✓ |
| fn vs function | **PARTIAL** | Parser uses fn; many files use function | Unify or support both |
| Host syntax fixes | **PARTIAL** | lha3_memory_system (TS), ReasoningEngine (JS), quantum_neural (print) | Fix remaining |

---

## 6. Documentation

| Item | Status | Location | Action |
|------|--------|----------|--------|
| README accuracy | **HAVE** | Fixed to valid AZL ✓ | — |
| AZL_LANGUAGE_RULES | **HAVE** | Forbidden syntax table ✓ | — |
| API reference | **NEED** | — | Auto-generate from exports |
| Runbooks | **PARTIAL** | OPERATIONS.md exists | Update for native-only |
| Tutorials | **NEED** | — | "Train a model in pure AZL" |

---

## 7. Testing

| Item | Status | Location | Action |
|------|--------|----------|--------|
| Native gates | **HAVE** | check_azl_native_gates.sh, verify_native_runtime_live | ✓ |
| Grammar verify | **HAVE** | verify_azl_grammar_conformance.sh | ✓ |
| Unit test framework | **NEED** | — | `azl test` with assert_eq, etc. |
| Integration tests | **PARTIAL** | azme_e2e, various test_*.azl | Expand coverage |
| Fuzz testing | **NEED** | — | Parser/interpreter fuzz |

---

## 8. Production Readiness

| Item | Status | Location | Action |
|------|--------|----------|--------|
| Error system | **HAVE** | `azl/core/error_system.azl` | log_error, halt_execution ✓ |
| Logging | **PARTIAL** | say, log_error | Add structured levels, correlation IDs |
| Metrics | **PARTIAL** | runtime_inspector, persistence_stats | Prometheus export |
| Health checks | **HAVE** | /healthz, /readyz, /status | ✓ |

---

## Priority Build Order

1. **Benchmark gate** — CI blocks regression ✅ **DONE** (`scripts/benchmark_gate.sh`, CI step)
2. **Wire VM/bytecode** — Optional backend for enterprise
3. **azl install** — Script that fetches .azlpack ✅ **DONE** (`scripts/azl_install.sh`, `scripts/azl install`)
4. **SIMD stdlib** — simd_add, simd_mul (pure AZL first) ✅ **DONE** (`azl/stdlib/core/simd.azl`)
5. **Unit test framework** — azl test with assert ✅ **DONE** (`azl/testing/azl_test_framework.azl`)
6. **LSP skeleton** — Basic syntax server ✅ **DONE** (`tools/azl_lsp.py`, `docs/AZL_LSP_SETUP.md`)
7. **Tensor type** — create_tensor, tensor_add, tensor_mul ✅ **DONE** (`azl/core/types/tensor.azl`)
8. **Package registry server** — HTTP server for .azlpack ✅ **DONE** (`tools/registry_server.py`)
