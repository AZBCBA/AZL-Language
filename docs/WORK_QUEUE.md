# Work queue (run in order)

Single checklist for the **next actions** from [PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md). Update row **Status** as you go.

| # | Task | Owner | Status |
|---|------|--------|--------|
| 1 | **Product benchmark suite** — `ollama serve` + model; `bash scripts/run_enterprise_daemon.sh`; align `AZL_ENTERPRISE_PORT` with daemon; token in env or `.azl/local_api_token`; `bash scripts/run_product_benchmark_suite.sh` | ops | ☐ |
| 2 | **P0 spine — automated gates** — `bash scripts/check_azl_native_gates.sh` includes **H** (tokenizer + brace tokens on `azl_interpreter.azl`). Next engineering slice: execute interpreter under `AZL_RUNTIME_SPINE=azl_interpreter` beyond minimal fixture | eng | ☐ (gate H partial) |
| 3 | **Canonical HTTP profile** — Read [CANONICAL_HTTP_PROFILE.md](CANONICAL_HTTP_PROFILE.md); pick **C-only** vs **enterprise `http_server`** per deployment; align startup docs | arch | ☐ |
| 4 | **GGUF / GPU** — Only if product requires; [LLM_INFRASTRUCTURE_AUDIT.md](LLM_INFRASTRUCTURE_AUDIT.md); keep `GET /api/llm/capabilities` honest | product | ☐ deferred |

## Quick commands

```bash
# Stability (release order)
bash scripts/enforce_canonical_stack.sh
bash scripts/check_azl_native_gates.sh
bash scripts/enforce_legacy_entrypoint_blocklist.sh
bash scripts/verify_native_runtime_live.sh
bash scripts/run_all_tests.sh

# Product suite (after daemon + Ollama)
bash scripts/run_product_benchmark_suite.sh
```
