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
| `scripts/run_benchmark_llama_server.sh` | **`llama-server`** with model loaded once: direct `/completion` vs **`POST /api/llm/llama_server/completion`** on the native engine (see `LLM_INFRASTRUCTURE_AUDIT.md`). |

For local runs only, you may store the daemon token in **`.azl/local_api_token`** (first line; `chmod 600`); **`run_product_benchmark_suite.sh`** and **`benchmark_enterprise_v1_chat.sh`** read it if **`AZL_API_TOKEN`** is unset.

Details and honesty contract: [LLM_INFRASTRUCTURE_AUDIT.md](LLM_INFRASTRUCTURE_AUDIT.md). **Shipped items + commands:** [AZL_DOCUMENTATION_CANON.md](AZL_DOCUMENTATION_CANON.md) · **C vs enterprise HTTP:** [CANONICAL_HTTP_PROFILE.md](CANONICAL_HTTP_PROFILE.md).

## Active work areas (coordinate before changing)

- **`azl/core/parser/azl_parser.azl`** — Token types, keywords, operators, punctuation, `tokenize`, `parse_azl_code`, AST.
- **`azl/core/compiler/`** — Compiler pipeline (parser, bytecode, optimizers).
- **`azl/runtime/interpreter/`** — AZL interpreter.
- **`azl/core/error_system.azl`** — Error handling.
- **`docs/language/AZL_CURRENT_SPECIFICATION.md`** — Single source of truth for **current** AZL syntax and behavior.

Please avoid large, conflicting edits in these areas without coordination. Add tests and docs freely; for runtime/parser/compiler changes, discuss in issues or PRs.

## Strength bar (provable claims)

AZL’s “strength” is what you can **verify**, not adjectives in prose. The four pillars are recorded under **[AZL_DOCUMENTATION_CANON.md](AZL_DOCUMENTATION_CANON.md) §1.7**.

Quick check before a PR (same tooling as native gates: **`rg`**, **`jq`**, **`python3`**, **`gcc`**):

```bash
bash scripts/verify_azl_strength_bar.sh
```

That runs **`check_azl_native_gates.sh`**, **`verify_native_runtime_live.sh`**, and **`verify_enterprise_native_http_live.sh`**. It does **not** replace the full release sequence — use **`scripts/run_full_repo_verification.sh`** (see `RELEASE_READY.md`).

## Native gates (local tooling + exit codes)

**`bash scripts/check_azl_native_gates.sh`** is the main native gate runner. Install on the host (examples for Debian/Ubuntu):

- **`ripgrep`** (`rg`), **`jq`**, **`python3`**, **`gcc`**, **`curl`** — required for gate 0 ( **`self_check_release_helpers.sh`** ), F2/F3 parity, engine build, and live verify scripts you may run afterward.

**Numeric exits (no silent failures):** full tables live in **[ERROR_SYSTEM.md](ERROR_SYSTEM.md)** under **§ Shell helpers** (release/`verify_*` scripts), **§ Native gates (`check_azl_native_gates.sh`)** ( **10–31** + gate 0 / G / H notes), **§ Runtime spine contract** ( **90–96** ), **§ Strength bar**, and **§ Release checkout assertion** (`gh_assert_checkout_matches_tag.sh`). Use the printed **`ERROR:`** / **`ERROR[...]`** lines first; the doc maps codes to meaning.

## GitHub Releases (maintainers)

Publishing sample assets to a **GitHub Release** is **not** part of `run_full_repo_verification.sh`. Flow, **`workflow_dispatch`**, and **`gh`/`ERROR` exits** are documented in **`RELEASE_READY.md`** § GitHub Release and **`docs/CI_CD_PIPELINE.md`**. Tag naming is defined once in **`scripts/azl_release_tag_policy.sh`** (sourced by **`scripts/gh_verify_remote_tag.sh`** and **`scripts/gh_create_sample_release.sh`**). Shell exit tables: **`docs/ERROR_SYSTEM.md`** (§ Shell helpers, Native gates, spine contract, strength bar, release checkout assertion). **`scripts/self_check_release_helpers.sh`** runs as **gate 0** inside **`check_azl_native_gates.sh`** (**`rg`**, **`jq`**); it verifies **`release/native/manifest.json`** (**`gates[]`** and **`github_release`** paths). When you add a GitHub release script, list it under **`github_release.scripts`** in the manifest. **`gh_verify_remote_tag.sh`** uses **`jq @uri`** for the GitHub REST ref path (no Python in that path).

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
5. Ensure the project runs — **`bash scripts/run_full_repo_verification.sh`** (or `RUN_OPTIONAL_BENCHES=0` for CI-style without LLM benches), or individually: `scripts/run_tests.sh`, `scripts/run_all_tests.sh`, `scripts/verify_native_runtime_live.sh`, `scripts/verify_enterprise_native_http_live.sh`.
6. Push and open a Pull Request. **`main`**/**`master`** PRs run **`.github/workflows/test-and-deploy.yml`** (see **`docs/CI_CD_PIPELINE.md`**); feature branches also run **`azl-ci.yml`**. Keep PRs small and reviewable.

## Documentation

- **Current language spec**: `docs/language/AZL_CURRENT_SPECIFICATION.md`
- **AZL rules and identity**: `docs/language/AZL_LANGUAGE_RULES.md`
- **Grammar reference**: `docs/language/GRAMMAR.md`
- **Architecture**: `docs/ARCHITECTURE_OVERVIEW.md`, `azl/docs/AZL_LANGUAGE_ARCHITECTURE.md`

When you change AZL syntax or runtime behavior, update the spec and grammar docs so the repo stays accurate for contributors and users.
