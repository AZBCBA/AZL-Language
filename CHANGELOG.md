# Changelog

All notable changes to the AZL Language project are documented here. AZL is a component-based, event-driven language (see [docs/language/AZL_LANGUAGE_RULES.md](docs/language/AZL_LANGUAGE_RULES.md)).

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

- **Runtime spine (source of truth):** [docs/RUNTIME_SPINE_DECISION.md](docs/RUNTIME_SPINE_DECISION.md) — C engine orchestrates; AZL interpreter is the decided semantic core; documents **current vs target**, **P0 not done** on default `start_azl_native_mode.sh` path, ordered **P0–P5** obligations with file pointers; quantum core-language one-liner; GGUF deferred unless product requires it.
- Documentation and GitHub readiness: LICENSE, CONTRIBUTING (Python + AZL), AZL_LANGUAGE_RULES, GRAMMAR reference, updated README and project structure, clarified advanced_features as future-only.
- Documentation cleanup: removed obsolete root/`reports`/`azl/docs` status and “supervisor” markdown that contradicted the native AZL stack (stale Rust-runtime claims, duplicate completion reports). Canonical index: `docs/README.md`; CI truth: `docs/CI_CD_PIPELINE.md`; short status: `docs/STATUS.md`.
- **`AZL_USE_VM=1`**: `::azl.interpreter` `execute` path can compile a restricted AST (say/emit + init-only components) to linear ops and run `vm_run_bytecode_program` with shared `emit_event_resolved` dispatch; documented in `docs/AZL_NATIVE_RUNTIME_CONTRACT.md`; verified by `scripts/test_azl_use_vm_path.sh` (includes `verify_azl_use_vm_path.sh`, `check_azl_vm_tree_parity.py`, fixture `azl/tests/fixtures/vm_parity_minimal.azl`). Contract clarifies default enterprise **C minimal** runtime does not execute the AZL interpreter.
- **Native LLM capabilities:** `GET /api/llm/capabilities` on `azl-native-engine` reports Ollama proxy vs GGUF status with `ERR_NATIVE_GGUF_NOT_IMPLEMENTED`; `verify_native_runtime_live.sh` + `check_azl_native_gates.sh` enforce it; `docs/LLM_INFRASTRUCTURE_AUDIT.md` synced to sysproxy/C engine HTTP reality.
- **`.azlpack` dogfood:** `packages/src/azl-hello/` first-party pack, `scripts/build_azlpack.sh`, local install via `AZL_REGISTRY_DIR` in `scripts/azl_install.sh`, `scripts/verify_azlpack_local.sh` in full test run. **LSP:** `tools/azl_lsp.py` — `textDocument/definition` (`::` components, `emit`↔`listen`, `fn`/`function`); `scripts/verify_lsp_smoke.sh` + `scripts/test_lsp_jump_to_def.sh`; fixture `azl/tests/lsp_definition_resolution.azl`.
- **Integrations clarity:** `docs/INTEGRATIONS_HOST_VS_NATIVE.md`, `azl/integrations/anythingllm/README.md`, pure-AZL `azme_ollama_native.azl` (Ollama via `syscall` `http`), `scripts/verify_native_bundle_excludes_host_integrations.sh` in full test run.
