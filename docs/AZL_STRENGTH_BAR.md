# AZL strength bar (provable claims)

AZL does not claim strength by slogan. This page ties **four engineering pillars** to **commands and files you can run today**. For gap-style audits (HAVE vs NEED), see [AUDIT_STRENGTH_ITEMS.md](AUDIT_STRENGTH_ITEMS.md).

---

## 1. Predictable semantics

**Claim:** On the supported subset, behavior is defined by spec and checked by automated parity.

| Proof | Location |
|--------|----------|
| Current behavior (not wishful spec) | [language/AZL_CURRENT_SPECIFICATION.md](language/AZL_CURRENT_SPECIFICATION.md) |
| C minimal vs Python semantic host — same fixture, byte-identical stdout | Native gate **F2** in `scripts/check_azl_native_gates.sh` |
| P0 interpreter slice — C vs Python | Gate **F3** (same script) |
| Spine resolver contract | Gate **G** → `scripts/verify_runtime_spine_contract.sh` |

---

## 2. Operational strength

**Claim:** Native mode, LLM surfaces, and release order are enforced by scripts with explicit failures (no silent “green”).

| Proof | Location |
|--------|----------|
| Native-only guards, VM opcode contract, engine build, legacy blocklist patterns | `scripts/check_azl_native_gates.sh` |
| Live HTTP: capabilities + honesty fields | `scripts/verify_native_runtime_live.sh` (minimal engine bundle, same family as `run_native_engine_llm_bench.sh`) |
| Full ship bar (canonical stack + gates + legacy blocklist + live + **all tests**) | `scripts/run_full_repo_verification.sh` — see [RELEASE_READY.md](../RELEASE_READY.md) |
| Error handling philosophy | [ERROR_SYSTEM.md](ERROR_SYSTEM.md) |

---

## 3. Performance and benchmarking (honest comparisons)

**Claim:** Benchmarks name the HTTP surface and whether the model is loaded per request vs kept in a server.

| Proof | Location |
|--------|----------|
| Ollama proxy vs Python vs curl | `scripts/benchmark_llm_ollama.sh`, `scripts/run_native_engine_llm_bench.sh` |
| Subprocess GGUF vs engine | `scripts/run_benchmark_gguf_direct.sh` |
| Loaded model: `llama-server` direct vs engine proxy | `scripts/run_benchmark_llama_server.sh` |
| Enterprise stack (not C proxy) | `scripts/benchmark_enterprise_v1_chat.sh` |
| Surface inventory | [LLM_INFRASTRUCTURE_AUDIT.md](LLM_INFRASTRUCTURE_AUDIT.md) |

---

## 4. Ecosystem and contributor velocity

**Claim:** Packages, LSP, and contribution paths exist and are verifiable.

| Proof | Location |
|--------|----------|
| Pack format + dogfood | [AZLPACK_SPEC.md](AZLPACK_SPEC.md), `packages/src/azl-hello/`, `scripts/verify_azlpack_local.sh` |
| LSP (diagnostics + go-to-definition) | `tools/azl_lsp.py`, `scripts/verify_lsp_smoke.sh` |
| Contributing + strict/error rules | [CONTRIBUTING.md](CONTRIBUTING.md) |

---

## One command: strength bar (not a full release)

Runs native gates (includes F2/F3/G/H and engine build) and the live capabilities probe:

```bash
bash scripts/verify_azl_strength_bar.sh
```

Requires the same tooling as gates (**`rg`**, **`python3`**, **`gcc`** for the native engine build). Exit non-zero prints `ERROR[AZL_STRENGTH_BAR]: …` with a distinct step code.

**Before a release**, still run `bash scripts/run_full_repo_verification.sh` (or the ordered steps in `RELEASE_READY.md`).
