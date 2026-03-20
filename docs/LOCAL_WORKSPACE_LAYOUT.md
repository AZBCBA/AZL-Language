# Local workspace layout (`.azl/`)

All paths are **gitignored** as a unit (see `.gitignore`). This document is the **operator map** for organizing files on disk without touching versioned `azl/` or `azme/` trees.

## Subdirectories (created by `scripts/azl_local_layout.sh`)

| Directory | Purpose |
|-----------|---------|
| `.azl/benchmarks/` | Benchmark reports (`.txt`), latency traces (`.lat`), policy bench JSON, LLM bench logs |
| `.azl/state/` | `native_engine_runs.jsonl`, `policy_infer_audit.jsonl`, `native_runtime_state.json` (native engine + runtime loop) |
| `.azl/logs/` | Reserved for ad-hoc log copies (optional); many scripts still write specific logs next to FIFOs under `.azl/` |
| `.azl/run/` | Reserved for PID snapshots if you relocate them later |
| `.azl/bundles/` | Large rebuilt combined `.azl` you keep for inspection (e.g. `enterprise_combined_rebuilt.azl`) |
| `.azl/quarantine/` | Local checkpoints or exports you do not want at repo root (moved from `./quarantine/` by migrate script) |
| `.azl/archive/` | Raw tail backups from `scripts/azl_truncate_daemon_err.sh` |
| `.azl/tmp/` | Ephemeral combined/bundle builds |
| `.azl/bin/` | Built `azl-native-engine`, `sysproxy`, etc. |
| `.azl/cache/` | Daemon cache |

## Stable paths (do not move without code changes)

- **FIFOs:** `.azl/engine.in`, `.azl/engine.out`
- **Daemon stderr (often huge):** `.azl/daemon.err` (systemd unit may reference this path)
- **Secrets / chat:** `.azl/live_chat.env`, `.azl/local_api_token` (first line = token for some benches)
- **Chat sessions:** `.azl/chat_sessions/`

## Environment overrides

| Variable | Default | Effect |
|----------|---------|--------|
| `AZL_VAR` | `<repo>/.azl` | Root of all local dirs below |
| `AZL_BENCHMARKS_DIR` | `$AZL_VAR/benchmarks` | Benchmark scripts write here |
| `AZL_STATE_DIR` | `$AZL_VAR/state` | Native engine audit/run JSONL |
| `AZL_STATE_DIR` | (same) | `scripts/azl_native_runtime_loop.sh` heartbeat JSON |

## Migration

From repo root:

```bash
bash scripts/azl_migrate_local_workspace.sh
```

**Rebuild** the native engine after pulling changes that move audit paths:

```bash
bash scripts/build_azl_native_engine.sh
```

## Source of truth in repo

- `scripts/azl_local_layout.sh` — exports paths + `mkdir -p`
- `scripts/run_enterprise_daemon.sh` — `cd` to repo root, sources layout, exports `AZL_STATE_DIR` for children
