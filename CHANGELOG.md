# Changelog

All notable changes to the AZL Language project are documented here. AZL is a component-based, event-driven language (see [docs/language/AZL_LANGUAGE_RULES.md](docs/language/AZL_LANGUAGE_RULES.md)).

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

- Documentation and GitHub readiness: LICENSE, CONTRIBUTING (Python + AZL), AZL_LANGUAGE_RULES, GRAMMAR reference, updated README and project structure, clarified advanced_features as future-only.
- Documentation cleanup: removed obsolete root/`reports`/`azl/docs` status and “supervisor” markdown that contradicted the native AZL stack (stale Rust-runtime claims, duplicate completion reports). Canonical index: `docs/README.md`; CI truth: `docs/CI_CD_PIPELINE.md`; short status: `docs/STATUS.md`.
- **`AZL_USE_VM=1`**: `::azl.interpreter` `execute` path can compile a restricted AST (say/emit + init-only components) to linear ops and run `vm_run_bytecode_program` with shared `emit_event_resolved` dispatch; documented in `docs/AZL_NATIVE_RUNTIME_CONTRACT.md`; verified by `scripts/verify_azl_use_vm_path.sh`.
- **Native LLM capabilities:** `GET /api/llm/capabilities` on `azl-native-engine` reports Ollama proxy vs GGUF status with `ERR_NATIVE_GGUF_NOT_IMPLEMENTED`; `verify_native_runtime_live.sh` + `check_azl_native_gates.sh` enforce it; `docs/LLM_INFRASTRUCTURE_AUDIT.md` synced to sysproxy/C engine HTTP reality.
