# AZL Language — Documentation index

Single entry point for **accurate** project docs. Older “status report”, “supervisor”, and duplicate ecosystem summaries were removed as misleading; use **git history** if you need a retired filename.

## Start here (operations)

| Document | Use |
|----------|-----|
| [../README.md](../README.md) | Clone, quick start, native mode |
| [../OPERATIONS.md](../OPERATIONS.md) | Runbook: daemons, sysproxy, tests |
| [../RELEASE_READY.md](../RELEASE_READY.md) | **Release gate order** before shipping native profile |
| [AZL_NATIVE_RUNTIME_CONTRACT.md](AZL_NATIVE_RUNTIME_CONTRACT.md) | Native HTTP/runtime behavior contract |
| [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md) | **Spine source of truth:** C engine vs AZL interpreter (current vs target, P0–P5) |

## Roadmap and audits (planning)

| Document | Use |
|----------|-----|
| [AZL_PERFECTION_PLAN.md](AZL_PERFECTION_PLAN.md) | Strategic gaps and phased goals |
| [PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md) | Phased completion vs contract (P0 executor gap, P1–P5) |
| [DEEP_AUDIT_QUANTUM_MEMORY_PHYSICS.md](DEEP_AUDIT_QUANTUM_MEMORY_PHYSICS.md) | Quantum / LHA3 / memory: real vs symbolic |
| [LLM_INFRASTRUCTURE_AUDIT.md](LLM_INFRASTRUCTURE_AUDIT.md) | LLM / HTTP / proxy stack; includes **`GET /api/llm/capabilities`** on native engine |
| [INTEGRATIONS_HOST_VS_NATIVE.md](INTEGRATIONS_HOST_VS_NATIVE.md) | AnythingLLM / `azl/integrations`: pure AZL vs host-shaped reference |
| [AUDIT_STRENGTH_ITEMS.md](AUDIT_STRENGTH_ITEMS.md) | Focused strength / risk audit |
| [STATUS.md](STATUS.md) | Short **verified** runtime snapshot |

## Language (syntax and rules)

| Document | Use |
|----------|-----|
| [language/AZL_CURRENT_SPECIFICATION.md](language/AZL_CURRENT_SPECIFICATION.md) | **Implemented** behavior |
| [language/AZL_LANGUAGE_RULES.md](language/AZL_LANGUAGE_RULES.md) | AZL identity (not Java/TS) |
| [language/GRAMMAR.md](language/GRAMMAR.md) | Grammar; parser lives in `azl/core/parser/` |

Broader / historical spec draft: [../azl/docs/AZL_LANGUAGE_SPECIFICATION.md](../azl/docs/AZL_LANGUAGE_SPECIFICATION.md) (vision; prefer `AZL_CURRENT_SPECIFICATION` for truth).

## Architecture and APIs

| Document | Use |
|----------|-----|
| [ARCHITECTURE_OVERVIEW.md](ARCHITECTURE_OVERVIEW.md) | System shape |
| [ERROR_SYSTEM.md](ERROR_SYSTEM.md) | Error handling |
| [stdlib.md](stdlib.md) | Standard library |
| [VIRTUAL_OS_API.md](VIRTUAL_OS_API.md) | Virtual OS / syscalls |
| [STRICT_MODE_AND_FEATURE_FLAGS.md](STRICT_MODE_AND_FEATURE_FLAGS.md) | Flags and strict mode |
| [LHA3_STDLIB_API.md](LHA3_STDLIB_API.md) | LHA3 memory API surface |
| [API_REFERENCE.md](API_REFERENCE.md) | API-style reference (where maintained) |

## CI/CD and contributing

| Document | Use |
|----------|-----|
| [CI_CD_PIPELINE.md](CI_CD_PIPELINE.md) | GitHub Actions overview |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute |
| [OBSERVABILITY.md](OBSERVABILITY.md) | Logs / metrics hooks |

Workflows live under `.github/workflows/` — including **`test-and-deploy.yml`** (tests, native matrix, benchmarks, coverage artifact, Docker → GHCR, optional staging webhook).

**`scripts/test_azl_use_vm_path.sh`** (from `run_all_tests.sh`) checks `AZL_USE_VM` docs + wiring, **source-level parity** between `vm_run_bytecode_program` and tree-walker say/emit (`check_azl_vm_tree_parity.py`), and the eligible fixture `azl/tests/fixtures/vm_parity_minimal.azl`.

**LSP:** `tools/azl_lsp.py` provides diagnostics and **`textDocument/definition`** (jump to `component ::…`, matching `emit`/`listen` sites, `fn` / `function`). Integration tests: `scripts/verify_lsp_smoke.sh`, `scripts/test_lsp_jump_to_def.sh` (fixture `azl/tests/lsp_definition_resolution.azl`).

## Packages, training, runbooks

| Document | Use |
|----------|-----|
| [AZLPACK_SPEC.md](AZLPACK_SPEC.md) | Package format; first dogfood pack `packages/src/azl-hello/` |
| [TRAIN_IN_PURE_AZL.md](TRAIN_IN_PURE_AZL.md) | Training in AZL |
| [AZME_PRODUCTION_RUNBOOK.md](AZME_PRODUCTION_RUNBOOK.md) | AZME operations |
| [PRODUCTION_RUN.md](PRODUCTION_RUN.md) | Production run notes |
| [../README_PREPARE_AZME_TRAINING.md](../README_PREPARE_AZME_TRAINING.md) | Prepare AZME training env |
| [../AZL_AZME_TRAINING_GUIDE.md](../AZL_AZME_TRAINING_GUIDE.md) | AZL/AZME training guide |
| [../AZME_USAGE_GUIDE.md](../AZME_USAGE_GUIDE.md) | AZME ask/spawn usage examples |

## Experimental / future-only

| Document | Use |
|----------|-----|
| [advanced_features.md](advanced_features.md) | **Not implemented** — theoretical features only |

## Other

| Document | Use |
|----------|-----|
| [CODEGEN.md](CODEGEN.md) | Code generation notes |
| [AZL_LSP_SETUP.md](AZL_LSP_SETUP.md) | LSP: diagnostics + go to definition |
| [STRICT_AZL_GRAMMAR_CONFORMANCE_CHECKLIST.md](STRICT_AZL_GRAMMAR_CONFORMANCE_CHECKLIST.md) | Grammar conformance |
| [reflection_flow.md](reflection_flow.md) | Reflection flow |
| [ENTERPRISE_BUILD_SYSTEM.md](ENTERPRISE_BUILD_SYSTEM.md) | Enterprise build |
| [AZL_ENTERPRISE_SETUP.md](AZL_ENTERPRISE_SETUP.md) | Enterprise setup |

`azl/docs/README.md` describes layout under `azl/` and links back here.
