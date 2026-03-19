# Unified LLM Deployment Summary (Archived)

The former Python unified deployment system is retired from the canonical AZL runtime profile.

Current production direction is native-first AZL:

- `scripts/start_azl_native_mode.sh`
- `tools/azl_native_engine.c`
- `scripts/azl_native_runtime_loop.sh`
- `scripts/check_azl_native_gates.sh`
- `scripts/verify_native_runtime_live.sh`

This file is retained only as an archive marker to prevent accidental reuse of removed legacy entrypoints.
