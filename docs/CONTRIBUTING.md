# Contributing to AZL Language

**Read [AGENTS.md](../AGENTS.md) first.**

Thank you for contributing to **AZL** — the component-based, event-driven programming language. This project is **AZL language**, not Java, TypeScript, or any other language. Please follow AZL's rules and architecture.

## Before you edit (maintainers + AI)

1. **[AGENTS.md](../AGENTS.md)** — entry order for assistants and continuity.  
2. **[AI_MAINTAINER_CONTINUITY_HANDOFF.md](AI_MAINTAINER_CONTINUITY_HANDOFF.md)** — reality vs aspiration; do not claim shipped what the spine trace does not show.  
3. **[AZL_STRATEGIC_CONSENSUS_AND_EXECUTION_PLAN.md](AZL_STRATEGIC_CONSENSUS_AND_EXECUTION_PLAN.md)** — phased plan (native/AOT north star, literal vs serving artifacts).  
4. **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)** — what **actually** runs on the default native path today.

## Repository layout (native-first AZL)

- **`azl/`** — Pure AZL runtime: interpreter, parser, compiler, stdlib, error system, security. Grammar and parsing live in AZL (e.g. `azl/core/parser/azl_parser.azl`).
- **`scripts/start_azl_native_mode.sh`** — Canonical native startup path.
- **`scripts/run_enterprise_daemon.sh`** — Canonical combined runtime launcher.
- **`docs/`** — All project documentation. Language spec: `docs/language/AZL_CURRENT_SPECIFICATION.md` and `docs/language/AZL_LANGUAGE_RULES.md`.

There is **no** `src/lib.rs` or `Cargo.toml` at repo root. The release runtime path is native-first AZL.

External **Rust** or **dataset** trees on other disks are indexed in [RELATED_WORKSPACES.md](RELATED_WORKSPACES.md) and [migration/INVENTORY.csv](../migration/INVENTORY.csv). They are **out of scope** for default PR verification (**`make verify`**).

## Research and capability libraries

Subtrees such as `azl/quantum/`, `azl/memory/`, `azl/neural/`, and `azl/ffi/` contain **event-driven modules** that may not be executed by the **default native runtime child** (minimal C / Python subset on the enterprise combined file). Before treating a file as “what AZL does in production,” read:

- [AZL_GPU_NEURAL_SURFACE_MAP.md](AZL_GPU_NEURAL_SURFACE_MAP.md) — **Whole-field semantics** (what “quantum” means in-repo, §0) + GPU / neural / LHA3 / `azl/quantum/` **file map**
- [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md) — which stack owns semantics on the canonical command

Refresh local counts: `bash scripts/audit_gpu_neural_quantum_surfaces.sh`

## LLM and HTTP benchmarks (optional)

Three **different** surfaces — do not mix them up:

| Script | What it measures |
|--------|------------------|
| `scripts/run_product_benchmark_suite.sh` | Runs **native LLM bench** first; runs **enterprise /v1/chat** only if `AZL_API_TOKEN` is set (one command for ops sweeps). |
| `scripts/run_native_engine_llm_bench.sh` | Builds and starts **C `azl-native-engine`**, then runs the Ollama comparison (needs `ollama serve` + a model). |
| `scripts/benchmark_llm_ollama.sh` | Python vs curl vs **C engine** `POST /api/ollama/generate` (only if `GET /api/llm/capabilities` reports the proxy). |
| `scripts/benchmark_enterprise_v1_chat.sh` | **Enterprise daemon** `POST /v1/chat` with `AZL_API_TOKEN` (not the C Ollama proxy). Typed stderr **`ERROR[AZL_ENTERPRISE_V1_CHAT_BENCH]`**; exits **2** / **91** / **93** / **94** / **95** in **[ERROR_SYSTEM.md](ERROR_SYSTEM.md)**. |
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

- **`ripgrep`** (`rg`), **`jq`**, **`python3`**, **`gcc`**, **`curl`** — required for gate 0 ( **`self_check_release_helpers.sh`** ), F2–F165 parity, literal codec round-trip, engine build, and live verify scripts you may run afterward.

**Numeric exits (no silent failures):** full tables live in **[ERROR_SYSTEM.md](ERROR_SYSTEM.md)** under **§ Shell helpers** (release/`verify_*` scripts), **§ Native gates (`check_azl_native_gates.sh`)** (parity **F2–F165** and engine rows **10–285** — e.g. **59** = F9 C↔Python stdout mismatch, **not** **`verify_native_runtime_live.sh`** **69**; **111–125** = F10–F14; **126–137** = F15–F18; **138–143** = F19–F20; **144–146** = F21; **147–149** = F22; **150–158** = F23–F25; **159–167** = F26–F28; **168–176** = F29–F31; **177–188** = F32–F35; **189–200** = F36–F39; **201–212** = F40–F43; **213–224** = F44–F47; **225–236** = F48–F51; **237–248** = F52–F55; **249–257** = F56–F58; **258–266** = F59–F61; **267–269** = F62; **270** / **272** / **273** = F63 ( **271** skipped — literal codec ); **274–276** = F64; **277–285** = F65–F67; **291–293** = F68; **294–296** = F69; **297–299** = F70; **311–313** = F71; **314–316** = F72; **317–319** = F73; **323–325** = F74; **326–328** = F75; **329–331** = F76; **332–334** = F77; **335–337** = F78; **338–340** = F79; **341–343** = F80; **344–346** = F81; **347–349** = F82; **350–352** = F83; **353–355** = F84; **356–358** = F85; **359–361** = F86; **362–364** = F87; **365–367** = F88; **368–370** = F89; **371–373** = F90; **374–376** = F91; **377–379** = F92; **380–382** = F93; **383–385** = F94; **386–388** = F95; **389–391** = F96; **392–394** = F97; **395–397** = F98; **398–400** = F99; **401–403** = F100; **404–406** = F101; **407–409** = F102; **410–412** = F103; **413–415** = F104; **416–418** = F105; **419–421** = F106; **422–424** = F107; **425–427** = F108; **428–430** = F109; **431–433** = F110; **434–436** = F111; **437–439** = F112; **440–442** = F113; **443–445** = F114; **446–448** = F115; **449–451** = F116; **452–454** = F117; **455–457** = F118; **458–460** = F119; **461–463** = F120; **464–466** = F121; **467–469** = F122; **470–472** = F123; **473–475** = F124; **476–478** = F125; **479–481** = F126; **482–484** = F127; **485–487** = F128; **488–490** = F129; **491–493** = F130; **494–496** = F131; **497–499** = F132; **500–502** = F133; **503–505** = F134; **506–508** = F135; **509–511** = F136; **512–514** = F137; **515–517** = F138; **518–520** = F139; **521–523** = F140; **524–526** = F141; **527–529** = F142; **530–532** = F143; **533–535** = F144; **536–538** = F145; **539–541** = F146; **542–544** = F147; **545–547** = F148; **560–562** = F149; **563–565** = F150; **566–568** = F151; **569–571** = F152; **572–574** = F153; **575–577** = F154; **578–580** = F155; **581–583** = F156; **584–586** = F157; **587–589** = F158; **590–592** = F159; **593–595** = F160; **596–598** = F161; **599–601** = F162; **602–604** = F163; **605–607** = F164; **608–610** = F165; **97–100** = G2; gate **0** propagates **40–58**; **G** / **H** as in that section), **§ Runtime spine contract** ( **90–96** ), **§ Semantic spine owner** ( **92**, **97–100** ), **§ Strength bar**, and **§ Release checkout assertion** (`gh_assert_checkout_matches_tag.sh`). Use the printed **`ERROR:`** / **`ERROR[...]`** lines first; the doc maps codes to meaning.

## GitHub Releases (maintainers)

Publishing sample assets to a **GitHub Release** is **not** part of `run_full_repo_verification.sh`. Flow, **`workflow_dispatch`**, and **`gh`/`ERROR` exits** are documented in **`RELEASE_READY.md`** § GitHub Release and **`docs/CI_CD_PIPELINE.md`**. Tag naming is defined once in **`scripts/azl_release_tag_policy.sh`** (sourced by **`scripts/gh_verify_remote_tag.sh`** and **`scripts/gh_create_sample_release.sh`**). Shell exit tables: **`docs/ERROR_SYSTEM.md`** (§ Shell helpers, Native gates, spine contract, strength bar, release checkout assertion, required status checks contract, branch protection). **`scripts/self_check_release_helpers.sh`** runs as **gate 0** inside **`check_azl_native_gates.sh`** (**`rg`**, **`jq`**); it verifies **`release/native/manifest.json`** (**`gates[]`** and **`github_release`** paths). When you add a GitHub release script, list it under **`github_release.scripts`** in the manifest. **`gh_verify_remote_tag.sh`** uses **`jq @uri`** for the GitHub REST ref path (no Python in that path). **Branch protection:** **`release/ci/required_github_status_checks.json`** is the single source of truth; **`scripts/verify_required_github_status_checks_contract.sh`** runs in CI. Maintainers: **`docs/GITHUB_BRANCH_PROTECTION.md`**, **`make branch-protection-contract`**, **`make branch-protection-apply`**, **`make branch-protection-verify`**.

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
5. Ensure the project runs — **one command:** **`make verify`** (same as `RUN_OPTIONAL_BENCHES=0 bash scripts/run_full_repo_verification.sh` — see **`docs/INTEGRATION_VERIFY.md`**; step **0** runs promoted **doc pieces** from **`release/doc_verification_pieces.json`**, then native gates, then **`verify_azl_interpreter_semantic_spine_smoke.sh`** (P0.1b) and **`verify_azl_interpreter_semantic_spine_behavior_smoke.sh`** (P0.1c), then blocklist, minimal live, **`run_all_tests.sh`**). **`make verify-doc-pieces`** — every manifest entry. Or full script with optional benches: **`bash scripts/run_full_repo_verification.sh`**, or individually: `scripts/run_tests.sh`, `scripts/run_all_tests.sh`, `scripts/verify_native_runtime_live.sh`, `scripts/verify_enterprise_native_http_live.sh`. **Declaring native release profile complete (maintainers):** **`docs/PROJECT_COMPLETION_STATEMENT.md`**, **`make native-release-profile-complete`**. **Tier B / roadmap work queue:** **`docs/TIER_B_BACKLOG.md`**.
6. Push and open a Pull Request. **`main`**/**`master`** PRs run **`.github/workflows/test-and-deploy.yml`** (see **`docs/CI_CD_PIPELINE.md`**); feature branches also run **`azl-ci.yml`**. Keep PRs small and reviewable.

## Documentation

- **Current language spec**: `docs/language/AZL_CURRENT_SPECIFICATION.md`
- **AZL rules and identity**: `docs/language/AZL_LANGUAGE_RULES.md`
- **Grammar reference**: `docs/language/GRAMMAR.md`
- **Architecture**: `docs/ARCHITECTURE_OVERVIEW.md`, `azl/docs/AZL_LANGUAGE_ARCHITECTURE.md`

When you change AZL syntax or runtime behavior, update the spec and grammar docs so the repo stays accurate for contributors and users.
