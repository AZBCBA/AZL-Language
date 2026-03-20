# Local workspace layout (`.azl/`)

All paths are **gitignored** as a unit (see `.gitignore`). This document is the **operator map** for organizing files on disk without touching versioned `azl/` or `azme/` trees.

## Subdirectories (created by `scripts/azl_local_layout.sh`)

| Directory | Purpose |
|-----------|---------|
| `.azl/benchmarks/` | Benchmark reports (`.txt`), latency traces (`.lat`), policy bench JSON, **`proof_llm_*`** markdown + traces |
| `.azl/state/` | `native_engine_runs.jsonl`, `policy_infer_audit.jsonl`, `native_runtime_state.json` (native engine + runtime loop) |
| `.azl/logs/` | **Canonical** host logs: `daemon.out`, `sysproxy.log`, `wire.log`, `wire.requests.log`, `wire.responses.log`, `wire.lock`, verify/bench engine logs |
| `.azl/run/` | **PID files:** `daemon.pid`, `sysproxy.pid`, `syswire.pid`, ad-hoc bench PIDs (`sysproxy_proof.pid`, …) |
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
| `AZL_STATE_DIR` | `$AZL_VAR/state` | Native engine audit/run JSONL + `scripts/azl_native_runtime_loop.sh` heartbeat JSON |
| `AZL_LOGS_DIR` | `$AZL_VAR/logs` | Enterprise daemon, sysproxy, wire, verification, bench engine stderr |
| `AZL_RUN_DIR` | `$AZL_VAR/run` | PID snapshots for daemon / sysproxy / syswire |

## Organize repository-root clutter (tracked + local)

Moves **artifact-class** files from the repo root into:

- **`project/repo_root/{logs,txt,json,pid}/`** — **`git mv`** (history preserved; committed paths change).
- **`.azl/archive/repo_root/...`** — plain **`mv`** for untracked/ignored leftovers (gitignored).

Protected at repo root (organizer): README, licenses, `azl.build.json`, `sample_dataset.jsonl`, main entry `.sh` / core `.azl`. Tokenizer + training configs live under `tokenizers/` and `project/entries/config/`.

```bash
# Preview
bash scripts/azl_organize_repo_root_artifacts.sh

# Apply (example: also fix mistaken ./http: directory)
AZL_ORGANIZE_APPLY=1 AZL_ORGANIZE_GIT_MV_TRACKED=1 AZL_ORGANIZE_FIX_HTTP_COLON=1 \
  bash scripts/azl_organize_repo_root_artifacts.sh
```

Optional: **`AZL_ORGANIZE_LARGE_EXPORTS=1`** moves **`lha3_memory_export.json`** into **`project/repo_root/json/`** (large file).

## Scan reorganized + canonical trees for language ideas

After organizing, generate a **review report** (components, listeners, error/policy hints):

```bash
bash scripts/azl_scan_for_language_benefits.sh
```

Report: **`.azl/quarantine/language_benefit_scan_*.txt`** and **`language_benefit_scan_LATEST.txt`**.

## Exploration (before archive or bulk moves)

Generate a **local-only** inventory: project-root files, `.azl/` root entries, symlinks, temp pools (`azl*` under `/tmp` and `/mnt/ssd4t/tmp`), plus a **heuristic** “referenced in repo” count (ripgrep fixed-string matches, excluding `.git` and `.azl`). **Does not move or delete anything.**

```bash
bash scripts/azl_explore_local_artifacts.sh
```

Default report path: **`.azl/quarantine/local_artifact_inventory_<UTC>.txt`** and a symlink **`local_artifact_inventory_LATEST.txt`**. Override with **`AZL_INVENTORY_OUT=/path/to/report.txt`**.

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
