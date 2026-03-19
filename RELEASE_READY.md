# AZL Native Release Ready

This document defines the release path for the AZL-native profile.

## Canonical Release Profile

- Manifest: `release/native/manifest.json`
- Startup command: `bash scripts/start_azl_native_mode.sh`
- Runtime contract: `docs/AZL_NATIVE_RUNTIME_CONTRACT.md`

## Required Environment

- `AZL_NATIVE_ONLY=1`
- `AZL_ENABLE_LEGACY_HOST=0`
- `AZL_API_TOKEN=<secure token>`

## Required Pre-Release Gates

Run in this exact order:

1. `bash scripts/enforce_canonical_stack.sh`
2. `bash scripts/check_azl_native_gates.sh`
3. `bash scripts/enforce_legacy_entrypoint_blocklist.sh`
4. `bash scripts/verify_native_runtime_live.sh`
5. `bash scripts/run_all_tests.sh`

All commands must pass with exit code `0`.

## Expected Runtime Signals

After startup, validate:

- `GET /healthz` returns:
  - `{"ok":true,"service":"azl-native-engine","entry":"::boot.entry"}`
- `GET /readyz` returns:
  - `{"status":"ready","engine":"native","runtime":"running"}`
- `GET /status` includes:
  - `"engine":"native"`
  - `"runtime":{"running":true,...}`
- `GET /api/exec_state` with bearer token includes:
  - `"ok":true`
  - `"running":true`

## Rollback Procedure

If any gate fails:

1. Stop release promotion immediately.
2. Keep `AZL_NATIVE_ONLY=1` unchanged.
3. Fix failing gate root cause.
4. Re-run full gate sequence.
5. Only continue after complete green pass.

## CI Requirement

The `native-release-gates` workflow must pass on the release branch before deploy. The consolidated **`test-and-deploy.yml`** workflow also runs the full test suite plus Docker/GHCR and optional staging; see `docs/CI_CD_PIPELINE.md`.
