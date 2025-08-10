# AZL Operations Runbook

## Overview
This runbook documents how to run the enterprise daemon and validate host integrations via the sysproxy bridge using only the pure AZL engine.

## Quick Start (Local)
- Build sysproxy:
  - `gcc -O2 -Wall -o .azl/sysproxy tools/sysproxy.c`
- Run full integration test harness:
  - `bash scripts/test_sysproxy_setup.sh`
- Verify:
  - `curl http://127.0.0.1:8080/healthz`
  - `curl http://127.0.0.1:8080/readyz`
  - `curl http://127.0.0.1:8080/status`
  - `tail -f .azl/daemon.out | grep '@sysproxy'`

## JS/Python Smoke Tests
- JS runtime (dev harness):
  - `node scripts/azl_runtime.js test_core.azl ::test.core`
- Python runner (event engine harness):
  - `python3 azl_runner.py test_integration_final.azl`

## CI
- Main CI (`.github/workflows/ci.yml`):
  - Fails on any placeholders/TODO/FIXME in `.azl`
  - Fails on any stale v2 references
  - Runs JS + Python smoke
- Nightly sysproxy E2E (`.github/workflows/nightly.yml`):
  - Builds sysproxy, runs `scripts/test_sysproxy_setup.sh`, uploads logs

## Troubleshooting
- Permission denied on `.azl/daemon.out`:
  - Ensure file exists and writable: `: > .azl/daemon.out && chmod 664 .azl/daemon.out`
- Port conflict on 8080:
  - Set `AZL_BUILD_API_PORT` before running daemon: `AZL_BUILD_API_PORT=8090 bash scripts/run_enterprise_daemon.sh`
- No sysproxy responses:
  - Check wire logs: `tail -f .azl/wire.log`
  - Check sysproxy logs: `tail -f .azl/sysproxy.log`

## Notes
- Torch FFI is disabled by default; calls log `ffi_disabled` and proceed.
- The language is unified under a single interpreter and parser (`::parser.core`).
