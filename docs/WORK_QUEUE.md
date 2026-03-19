# Work queue (status)

Single checklist tied to [PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md).

## One command (automation)

```bash
# Release order from RELEASE_READY.md + run_all_tests.sh + optional benches
bash scripts/run_full_repo_verification.sh
```

- **Optional benches** (Ollama + enterprise `/v1/chat` when possible): **on** by default. Disable: `RUN_OPTIONAL_BENCHES=0 bash scripts/run_full_repo_verification.sh`

## Row status

| # | Task | Status |
|---|------|--------|
| 1 | **Product benchmarks** — Native LLM + enterprise chat | **Automated** in `run_full_repo_verification.sh` when Ollama + Profile B exist; else skipped with log lines. Manual override: `bash scripts/run_product_benchmark_suite.sh` |
| 2 | **P0 spine** — Gates **F3** (interpreter slice C↔Py), **H** (tokenizer + braces on real `azl_interpreter.azl`) | **☑** Slice includes `::internal.env`, `or`/`==`, `if { }`, keyed `{ }` aggregate for `::perf`; **still open:** default enterprise path = C minimal (full P0 = AZL interpreter owns semantics — see `RUNTIME_SPINE_DECISION.md`) |
| 3 | **Canonical HTTP** — C engine vs enterprise `http_server` | **☑ Documented** — [CANONICAL_HTTP_PROFILE.md](CANONICAL_HTTP_PROFILE.md); per-deploy choice is yours |
| 4 | **GGUF / GPU** | **☑ Policy** — deferred; `GET /api/llm/capabilities` verified honest in `verify_native_runtime_live.sh` |

## Manual commands (same as before)

```bash
bash scripts/enforce_canonical_stack.sh
bash scripts/check_azl_native_gates.sh
bash scripts/enforce_legacy_entrypoint_blocklist.sh
bash scripts/verify_native_runtime_live.sh
bash scripts/run_all_tests.sh
bash scripts/run_product_benchmark_suite.sh
bash scripts/run_semantic_interpreter_slice.sh
```
