# Contributing to AZL Language

Thank you for contributing to **AZL** — the component-based, event-driven programming language. This project is **AZL language**, not Java, TypeScript, or any other language. Please follow AZL's rules and architecture.

## Repository layout (native-first AZL)

- **`azl/`** — Pure AZL runtime: interpreter, parser, compiler, stdlib, error system, security. Grammar and parsing live in AZL (e.g. `azl/core/parser/azl_parser.azl`).
- **`scripts/start_azl_native_mode.sh`** — Canonical native startup path.
- **`scripts/run_enterprise_daemon.sh`** — Canonical combined runtime launcher.
- **`docs/`** — All project documentation. Language spec: `docs/language/AZL_CURRENT_SPECIFICATION.md` and `docs/language/AZL_LANGUAGE_RULES.md`.

There is **no** `src/lib.rs` or `Cargo.toml` at repo root. The release runtime path is native-first AZL.

## Research and capability libraries

Subtrees such as `azl/quantum/`, `azl/memory/`, `azl/neural/`, and `azl/ffi/` contain **event-driven modules** that may not be executed by the **default native runtime child** (minimal C / Python subset on the enterprise combined file). Before treating a file as “what AZL does in production,” read:

- [AZL_GPU_NEURAL_QUANTUM_INVENTORY.md](AZL_GPU_NEURAL_QUANTUM_INVENTORY.md) — GPU/device/neural/quantum **file map** and mathematics stack audit (§8)
- [DEEP_AUDIT_QUANTUM_MEMORY_PHYSICS.md](DEEP_AUDIT_QUANTUM_MEMORY_PHYSICS.md) — symbolic vs implemented quantum/memory claims
- [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md) — which stack owns semantics on the canonical command

Refresh local counts: `bash scripts/audit_gpu_neural_quantum_surfaces.sh`

## LLM and HTTP benchmarks (optional)

Three **different** surfaces — do not mix them up:

| Script | What it measures |
|--------|------------------|
| `scripts/run_product_benchmark_suite.sh` | Runs **native LLM bench** first; runs **enterprise /v1/chat** only if `AZL_API_TOKEN` is set (one command for ops sweeps). |
| `scripts/run_native_engine_llm_bench.sh` | Builds and starts **C `azl-native-engine`**, then runs the Ollama comparison (needs `ollama serve` + a model). |
| `scripts/benchmark_llm_ollama.sh` | Python vs curl vs **C engine** `POST /api/ollama/generate` (only if `GET /api/llm/capabilities` reports the proxy). |
| `scripts/benchmark_enterprise_v1_chat.sh` | **Enterprise daemon** `POST /v1/chat` with `AZL_API_TOKEN` (not the C Ollama proxy). |

For local runs only, you may store the daemon token in **`.azl/local_api_token`** (first line; `chmod 600`); **`run_product_benchmark_suite.sh`** and **`benchmark_enterprise_v1_chat.sh`** read it if **`AZL_API_TOKEN`** is unset.

Details and honesty contract: [LLM_INFRASTRUCTURE_AUDIT.md](LLM_INFRASTRUCTURE_AUDIT.md). **Ordered checklist:** [WORK_QUEUE.md](WORK_QUEUE.md) · **C vs enterprise HTTP:** [CANONICAL_HTTP_PROFILE.md](CANONICAL_HTTP_PROFILE.md).

## Active work areas (coordinate before changing)

- **`azl/core/parser/azl_parser.azl`** — Token types, keywords, operators, punctuation, `tokenize`, `parse_azl_code`, AST.
- **`azl/core/compiler/`** — Compiler pipeline (parser, bytecode, optimizers).
- **`azl/runtime/interpreter/`** — AZL interpreter.
- **`azl/core/error_system.azl`** — Error handling.
- **`docs/language/AZL_CURRENT_SPECIFICATION.md`** — Single source of truth for **current** AZL syntax and behavior.

Please avoid large, conflicting edits in these areas without coordination. Add tests and docs freely; for runtime/parser/compiler changes, discuss in issues or PRs.

## Standards

- **No placeholders or mocks** in production code.
- **Strict mode** must pass before merging (see `OPERATIONS.md` and `docs/STRICT_MODE_AND_FEATURE_FLAGS.md`).
- **Error system**: Use the project's error handling; no silent fallbacks in production paths.
- **AZL syntax and rules**: Follow `docs/language/AZL_CURRENT_SPECIFICATION.md` and `docs/language/AZL_LANGUAGE_RULES.md`. Do not assume Java/TypeScript semantics.

## Code style

- Descriptive names; clear control flow; guard clauses.
- **Indentation**: 4 spaces (Python and AZL).
- Tests and documentation required for new features and behavior changes.

## Process

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/your-feature`).
3. Make changes; update specs/docs under `docs/` when changing behavior.
4. Add or adjust tests under `azl/testing/` and runtime gate scripts.
5. Ensure the project runs — **`bash scripts/run_full_repo_verification.sh`** (or `RUN_OPTIONAL_BENCHES=0` for CI-style without LLM benches), or individually: `scripts/run_tests.sh`, `scripts/run_all_tests.sh`, `scripts/verify_native_runtime_live.sh`.
6. Push and open a Pull Request. Keep PRs small and reviewable.

## Documentation

- **Current language spec**: `docs/language/AZL_CURRENT_SPECIFICATION.md`
- **AZL rules and identity**: `docs/language/AZL_LANGUAGE_RULES.md`
- **Grammar reference**: `docs/language/GRAMMAR.md`
- **Architecture**: `docs/ARCHITECTURE_OVERVIEW.md`, `azl/docs/AZL_LANGUAGE_ARCHITECTURE.md`

When you change AZL syntax or runtime behavior, update the spec and grammar docs so the repo stays accurate for contributors and users.
