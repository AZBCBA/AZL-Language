# Repository layout — where things belong

This project mixes **versioned source**, **local runtime state**, and **historical root-level artifacts**. Use this map so “uncategorized” files have a defined bucket (without deleting components you may still wire up later).

## 1. Canonical trees (prefer these for new work)

| Area | Path | Role |
|------|------|------|
| AZL language & systems | `azl/` | Components, stdlib slices, HTTP, build daemon, integrations |
| AZME / agent surfaces | `azme/` | AZME plugins, interfaces, training-related AZL |
| Native / host tools | `tools/` | C engine, LSP, semantic spine host, sysproxy sources |
| Shell entrypoints | `scripts/` | Daemon, native mode, chat, benchmarks, installers |
| Human docs | `docs/` | Specs, operations, diagnostics (`docs/diagnostics/`) |
| Examples | `examples/` | Small, copy-paste-friendly AZL |
| Benchmarks | `benchmarks/` | Benchmark definitions / harnesses (as present) |
| Deployment | `deployment/` | Deploy assets |
| Config | `config/` | e.g. `prod.azl.json` |
| Packages | `packages/` | `.azlpack`-related first-party packs |

## 2. `.azl/` — **local only** (gitignored)

Everything under **`.azl/`** is **intentionally not categorized into git**: engine binaries, FIFOs, PIDs, `daemon.err`, audit JSONL, benchmark outputs you dropped there, rebuilt combined `.azl`, chat env, CMake build trees, etc.

- **Rule:** Treat `.azl/` as a **runtime workspace**, not product source.
- **Hygiene:** Use `scripts/azl_truncate_daemon_err.sh`, rotate tmp combined files under `/tmp`, and keep secrets out of anything you `git add -f`.

## 3. Repository root — mixed legacy + ops

Many files at the **repo root** are **older demos, one-off AZL entrypoints, training experiments, or captured logs/JSON**. They are **categorized as “root legacy / artifacts”** until someone moves them with a full reference update (grep for paths before moving).

Rough groups:

| Group | Examples (non-exhaustive) | Note |
|-------|---------------------------|------|
| **Build / product metadata** | `azl.build.json`, `Makefile`, `Dockerfile`, `requirements.txt`, `README.md`, `CHANGELOG.md`, `LICENSE` | Keep at root or move only with tooling updates |
| **Ops / launch** | `run_pure_azl.sh`, `start_unified_llm.sh`, `launch_azme_complete.sh`, `OPERATIONS.md` | Prefer new flows under `scripts/` when adding |
| **AZME / demo AZL at root** | `azme_*.azl`, `chat_with_azl.azl`, `continuous_*training*.azl` | Legacy convenience paths; moving → update docs and any scripts that reference them |
| **Captured logs & proofs** | `*.log`, `full_*debug*.txt`, `*_proof.json`, `master_*report*.txt` | Historical snapshots; avoid committing new noise—prefer `.azl/` or `reports/` |
| **Training / tokenizer dumps** | `tokenizer*.json`, `training_config.json`, `master_training_config*.json` | Data/config snapshots; not “stdlib” |

**Nothing here is “wrong” by existing** — it is **under-documented until this file**. Prefer **new** files in the canonical trees above.

## 4. `reports/`, `training_reports/`, `migration/`

Use these (or add subfolders) for **human-readable reports** and **migration notes** instead of sprouting more one-off `*.txt` at root.

## 5. If you need a decision rule

1. **Shipping code / reusable AZL** → `azl/` or `azme/` (or `examples/` if tiny).  
2. **Host automation** → `scripts/` or `tools/`.  
3. **Explainability** → `docs/` (link from `README.md` if operators need it).  
4. **Machine-local noise** → `.azl/` (or don’t commit).  
5. **Unsure but must keep in git** → root is acceptable **temporarily**; add one line to this doc under root legacy until relocated.

## 6. Related

- Diagnostics snapshots (sanitized): `docs/diagnostics/digest.md`  
- Git policy for `.azl/`: `.gitignore` (comment block)
