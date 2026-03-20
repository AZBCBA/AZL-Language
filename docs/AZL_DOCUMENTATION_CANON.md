# AZL documentation canon

**Start here** for (1) a **single record of shipped and verified** work, (2) the **full map** of remaining documentation, and (3) **short pointers** to open milestones. Detailed specs and audits stay in linked files; this file replaces redundant status/strength/checklist docs that only duplicated completed items.

---

## 1. Shipped and verified (cross-checked)

### 1.1 Native runtime and quality gates

| Item | Proof |
|------|--------|
| C HTTP engine | `tools/azl_native_engine.c` — health, readiness, status, exec_state, capabilities, Ollama proxy, GGUF CLI infer, llama-server completion proxy |
| Native gates | `scripts/check_azl_native_gates.sh` — guards A–E, VM opcode contract D, C minimal F, Python parity F2, P0 slice F3, spine G, tokenizer/brace H |
| Live HTTP + LLM honesty | `scripts/verify_native_runtime_live.sh` — `azl-native-engine` + minimal bootstrap (`c_minimal_link_ping`), `/api/llm/capabilities`, native-only `scripts/azl` block |
| Strength bar (one command) | `scripts/verify_azl_strength_bar.sh` — gates + `verify_native_runtime_live.sh`; failures: `ERROR[AZL_STRENGTH_BAR]: …` |
| Full release sequence | `scripts/run_full_repo_verification.sh` — see [RELEASE_READY.md](../RELEASE_READY.md) |
| Changelog | [CHANGELOG.md](../CHANGELOG.md) |

### 1.2 Interpreter spine (done phases; not full self-host)

| Item | Proof |
|------|--------|
| Default spine | `AZL_RUNTIME_SPINE=c_minimal` → `scripts/azl_c_interpreter_runtime.sh` → `azl-interpreter-minimal` |
| Semantic spine (Python, parity subset) | `AZL_RUNTIME_SPINE=azl_interpreter` → `tools/azl_runtime_spine_host.py` / `tools/azl_semantic_engine/` |
| Byte parity C vs Python | Gate **F2** on `azl/tests/c_minimal_link_ping.azl` |
| P0 interpreter-shaped slice | Gate **F3** on `azl/tests/p0_semantic_interpreter_slice.azl` (includes **`.toInt()`**, dotted **`::perf.*`**, aligned with `azl_interpreter.azl` init prefix) |
| Tokenizer + `{`/`}` balance on real interpreter file | Gate **H** — `scripts/verify_p0_interpreter_tokenizer_boundary.sh` |
| Spine resolver + error surface | Gate **G** — `scripts/verify_runtime_spine_contract.sh` |

Source of truth for current vs target: [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md).

### 1.3 LLM and HTTP (honest surfaces)

| Item | Proof |
|------|--------|
| Capabilities / `ERR_NATIVE_GGUF_NOT_IN_PROCESS` | `GET /api/llm/capabilities` (see live verify above) |
| Ollama proxy | `POST /api/ollama/generate` — `scripts/benchmark_llm_ollama.sh`, `scripts/run_native_engine_llm_bench.sh` |
| Subprocess GGUF (no Ollama) | `POST /api/llm/gguf_infer` — `scripts/run_benchmark_gguf_direct.sh` |
| Loaded model (`llama-server`) | `POST /api/llm/llama_server/completion` — `scripts/run_benchmark_llama_server.sh` |
| Enterprise chat (not C proxy) | `POST /v1/chat` — `scripts/benchmark_enterprise_v1_chat.sh` |
| **Partner LLM proof (minimal bundle)** | `scripts/run_proof_llm_python_vs_azl.sh` + `scripts/proof_llm_python_vs_azl.py` — default **1000×** per path (Python → Ollama vs `POST /api/ollama/generate`); `.azl/proof_llm_python_vs_azl_*.md` (mean/p95 **AZL/Python** ratios). |
| **Partner LLM proof (enterprise `.azl` loaded)** | `scripts/run_proof_llm_enterprise_bundle.sh` — same comparison after loading the **fat** combined file from `scripts/build_enterprise_combined.sh` (same component list as `run_enterprise_daemon.sh`); report **`PROOF_REPORT_DISCLAIMER`** states C proxy vs `/v1/chat` scope. |
| **Host `getenv` via sysproxy** | `tools/sysproxy.c` op **`getenv`**; `export fn host_getenv` + syscall **`proc.getenv`** in `azl/system/azl_system_interface.azl`; `azl/host/exec_bridge.azl` seeds **`::internal`** after `link ::azl.system_interface`. Ops: [OPERATIONS.md](../OPERATIONS.md). |
| Inventory | [LLM_INFRASTRUCTURE_AUDIT.md](LLM_INFRASTRUCTURE_AUDIT.md) |

### 1.4 HTTP request handling (engine)

| Item | Proof |
|------|--------|
| Full POST body reads | `read_http_request_full` in `tools/azl_native_engine.c` (Content-Length–bounded) |

### 1.5 Ecosystem and tooling (shipped)

| Item | Proof |
|------|--------|
| `.azlpack` + dogfood | [AZLPACK_SPEC.md](AZLPACK_SPEC.md), `packages/src/azl-hello/`, `scripts/verify_azlpack_local.sh` |
| LSP | `tools/azl_lsp.py`, `scripts/verify_lsp_smoke.sh`, [AZL_LSP_SETUP.md](AZL_LSP_SETUP.md) |
| VM path (restricted slice) | `AZL_USE_VM=1` — `scripts/test_azl_use_vm_path.sh`, [AZL_NATIVE_RUNTIME_CONTRACT.md](AZL_NATIVE_RUNTIME_CONTRACT.md) |

### 1.6 Work-queue rows completed (formerly `WORK_QUEUE.md`)

| # | Was | Status |
|---|-----|--------|
| 1 | Product benchmarks | Automated in `run_full_repo_verification.sh` when backends exist; else skipped with log lines. Manual: `scripts/run_product_benchmark_suite.sh` |
| 2 | P0 gates F3 + H | **Done** (slice widened per CHANGELOG; full interpreter-as-default still open — see §3) |
| 3 | Canonical HTTP (C vs enterprise) | **Documented** — [CANONICAL_HTTP_PROFILE.md](CANONICAL_HTTP_PROFILE.md) |
| 4 | GGUF / GPU policy | **Deferred**; honesty enforced by live capabilities check |

### 1.7 Provable strength (four pillars; formerly `AZL_STRENGTH_BAR.md`)

1. **Predictable semantics** — [language/AZL_CURRENT_SPECIFICATION.md](language/AZL_CURRENT_SPECIFICATION.md); gates F2, F3, G.  
2. **Operational strength** — gates script; `verify_native_runtime_live.sh`; `run_full_repo_verification.sh`; [ERROR_SYSTEM.md](ERROR_SYSTEM.md).  
3. **Honest benchmarks** — scripts in §1.3 (including §1.3 proof harnesses); never mix C proxy port with enterprise stack.  
4. **Ecosystem** — §1.5; [CONTRIBUTING.md](CONTRIBUTING.md).

```bash
bash scripts/verify_azl_strength_bar.sh   # rg, python3, gcc required
```

### 1.8 Verified stack snapshot (formerly `STATUS.md`)

- **Interpreter (AZL source):** `azl/runtime/interpreter/azl_interpreter.azl` — large surface; default native **child** remains C minimal or Python parity subset unless spine env says otherwise.  
- **Virtual OS / stdlib:** `azl_system_interface.azl`, `azl_stdlib.azl` — as exercised by tests and semantic path.  
- **Deprecated:** Rust runtime at repo root as live core — ignore for current native profile.

---

## 2. Retired documents (merged into this file)

| File | Replaced by |
|------|-------------|
| `docs/WORK_QUEUE.md` | §1.6 + §1.1 commands |
| `docs/STATUS.md` | §1.8 + §3 |
| `docs/AZL_STRENGTH_BAR.md` | §1.7 |
| `docs/AZL_ENTERPRISE_SETUP.md` | [ENTERPRISE_BUILD_SYSTEM.md](ENTERPRISE_BUILD_SYSTEM.md) (quick start + ops) |
| `docs/PRODUCTION_RUN.md` | Removed — duplicated [ARCHITECTURE_OVERVIEW.md](ARCHITECTURE_OVERVIEW.md) / stale `cargo` path; use [OPERATIONS.md](../OPERATIONS.md), [RELEASE_READY.md](../RELEASE_READY.md) |
| `docs/ADVANCED_OPTIMIZATION_FEATURES.md` | Removed — contradicted [advanced_features.md](advanced_features.md) (honest “not implemented”); use **advanced_features.md** only for future-only optimizer/JIT fiction |

---

## 3. Open milestones (short)

Full phased map: [PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md). Strategy / competitive gaps: [AZL_PERFECTION_PLAN.md](AZL_PERFECTION_PLAN.md). HAVE vs NEED inventory: [AUDIT_STRENGTH_ITEMS.md](AUDIT_STRENGTH_ITEMS.md).

- **P0 remainder:** Semantic engine wide enough to run `azl_interpreter.azl` as the runtime child (or verified equivalent); default spine choice documented in [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md).  
- **Bootstrap footgun:** `scripts/azl_bootstrap.sh` → `scripts/azl_seed_runner.sh` requires **`AZL_NATIVE_EXEC_CMD`** (path to `azl-native-engine`). **`start_azl_native_mode.sh`** builds and exports it before **`start_enterprise_daemon.sh`**. Calling **`run_enterprise_daemon.sh`** directly without **`AZL_NATIVE_EXEC_CMD`** set causes seed exit **65** (distinct from **`AZL_NATIVE_RUNTIME_CMD`**, which the C engine passes to its **child**).  
- **P1+:** HTTP profile per deployment, proc policy, VM breadth, packages, in-process GGUF (deferred unless product requires).  
- **Quality:** `scripts/check_no_placeholders.sh`, grammar / LHA3 verifiers in `run_all_tests.sh`.

---

## 4. Documentation map (all remaining docs)

### Operations and release

| Document | Purpose |
|----------|---------|
| [../README.md](../README.md) | Clone, quick start |
| [../OPERATIONS.md](../OPERATIONS.md) | Daemons, sysproxy, tests |
| [../RELEASE_READY.md](../RELEASE_READY.md) | Pre-release gate order |
| [AZL_NATIVE_RUNTIME_CONTRACT.md](AZL_NATIVE_RUNTIME_CONTRACT.md) | Native HTTP / runtime contract |
| [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md) | Spine source of truth |

### Roadmap and audits

| Document | Purpose |
|----------|---------|
| [PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md) | Phased completion vs contract |
| [AZL_PERFECTION_PLAN.md](AZL_PERFECTION_PLAN.md) | Strategic gaps / AI positioning |
| [CANONICAL_HTTP_PROFILE.md](CANONICAL_HTTP_PROFILE.md) | C engine vs enterprise `http_server` |
| [DEEP_AUDIT_QUANTUM_MEMORY_PHYSICS.md](DEEP_AUDIT_QUANTUM_MEMORY_PHYSICS.md) | Quantum / memory: real vs symbolic |
| [AZL_GPU_NEURAL_QUANTUM_INVENTORY.md](AZL_GPU_NEURAL_QUANTUM_INVENTORY.md) | File map vs default runtime |
| [LLM_INFRASTRUCTURE_AUDIT.md](LLM_INFRASTRUCTURE_AUDIT.md) | LLM paths and benchmarks |
| [INTEGRATIONS_HOST_VS_NATIVE.md](INTEGRATIONS_HOST_VS_NATIVE.md) | Integrations scope |
| [AUDIT_STRENGTH_ITEMS.md](AUDIT_STRENGTH_ITEMS.md) | HAVE vs NEED matrix |

### Language

| Document | Purpose |
|----------|---------|
| [language/AZL_CURRENT_SPECIFICATION.md](language/AZL_CURRENT_SPECIFICATION.md) | Implemented behavior |
| [language/AZL_LANGUAGE_RULES.md](language/AZL_LANGUAGE_RULES.md) | Language identity |
| [language/GRAMMAR.md](language/GRAMMAR.md) | Grammar |
| [../azl/docs/AZL_LANGUAGE_SPECIFICATION.md](../azl/docs/AZL_LANGUAGE_SPECIFICATION.md) | Vision draft (non-canonical) |

### Architecture and APIs

| Document | Purpose |
|----------|---------|
| [ARCHITECTURE_OVERVIEW.md](ARCHITECTURE_OVERVIEW.md) | System shape |
| [ERROR_SYSTEM.md](ERROR_SYSTEM.md) | Errors |
| [stdlib.md](stdlib.md) | Stdlib |
| [VIRTUAL_OS_API.md](VIRTUAL_OS_API.md) | Virtual OS / syscalls |
| [STRICT_MODE_AND_FEATURE_FLAGS.md](STRICT_MODE_AND_FEATURE_FLAGS.md) | Flags |
| [LHA3_STDLIB_API.md](LHA3_STDLIB_API.md) | LHA3 API surface |
| [API_REFERENCE.md](API_REFERENCE.md) | API reference |

### CI and contributing

| Document | Purpose |
|----------|---------|
| [CI_CD_PIPELINE.md](CI_CD_PIPELINE.md) | GitHub Actions |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute |
| [OBSERVABILITY.md](OBSERVABILITY.md) | Logs / metrics |

### Packages, training, runbooks

| Document | Purpose |
|----------|---------|
| [AZLPACK_SPEC.md](AZLPACK_SPEC.md) | Pack format |
| [TRAIN_IN_PURE_AZL.md](TRAIN_IN_PURE_AZL.md) | Training in AZL |
| [AZME_PRODUCTION_RUNBOOK.md](AZME_PRODUCTION_RUNBOOK.md) | AZME ops (theoretical — verify before use) |
| [../README_PREPARE_AZME_TRAINING.md](../README_PREPARE_AZME_TRAINING.md) | AZME training prep |
| [../AZL_AZME_TRAINING_GUIDE.md](../AZL_AZME_TRAINING_GUIDE.md) | AZL/AZME training |
| [../AZME_USAGE_GUIDE.md](../AZME_USAGE_GUIDE.md) | AZME usage |

### Other technical

| Document | Purpose |
|----------|---------|
| [advanced_features.md](advanced_features.md) | Theoretical / not implemented |
| [CODEGEN.md](CODEGEN.md) | Codegen notes |
| [AZL_LSP_SETUP.md](AZL_LSP_SETUP.md) | LSP setup |
| [STRICT_AZL_GRAMMAR_CONFORMANCE_CHECKLIST.md](STRICT_AZL_GRAMMAR_CONFORMANCE_CHECKLIST.md) | Grammar conformance |
| [reflection_flow.md](reflection_flow.md) | Reflection |
| [ENTERPRISE_BUILD_SYSTEM.md](ENTERPRISE_BUILD_SYSTEM.md) | Enterprise build daemon + quick start (merged `AZL_ENTERPRISE_SETUP.md`) |
| [AZL_VS_PYTHON_COMPARISON.md](AZL_VS_PYTHON_COMPARISON.md) | Comparison |

### Root / repo

| Document | Purpose |
|----------|---------|
| [../CHANGELOG.md](../CHANGELOG.md) | Version history |
| [../SECURITY.md](../SECURITY.md) | Security |
| [../CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md) | Conduct |
| [../GITHUB_PUBLISH.md](../GITHUB_PUBLISH.md) | Publishing |
| [../migration/MAPPING.md](../migration/MAPPING.md) | Migration mapping |
| `azl/docs/README.md` | Layout under `azl/` |
| `azl/docs/AZL_LANGUAGE_ARCHITECTURE.md` | Architecture (AZL tree) |
| `deployment/README.md`, `packages/registry/README.md`, integration READMEs | Scoped guides |

---

## 5. Manual verification commands

```bash
bash scripts/enforce_canonical_stack.sh
bash scripts/check_azl_native_gates.sh
bash scripts/enforce_legacy_entrypoint_blocklist.sh
bash scripts/verify_native_runtime_live.sh
bash scripts/run_all_tests.sh
bash scripts/run_product_benchmark_suite.sh
bash scripts/run_semantic_interpreter_slice.sh
```

Same order and full tree: [RELEASE_READY.md](../RELEASE_READY.md) and `scripts/run_full_repo_verification.sh`.
