# Unified LLM Deployment (Archived)

This document is archived. The Python-based unified deployment path was removed from the canonical AZL stack.

## Canonical Runtime Path

- Start runtime: `bash scripts/start_azl_native_mode.sh`
- Run gates: `bash scripts/check_azl_native_gates.sh`
- Verify live native state: `bash scripts/verify_native_runtime_live.sh`

## Notes

- Legacy host execution paths are intentionally blocked in native-only mode.
- See `RELEASE_READY.md` and `docs/AZL_NATIVE_RUNTIME_CONTRACT.md` for current release/runtime rules.
