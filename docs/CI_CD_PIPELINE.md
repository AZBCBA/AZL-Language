# CI/CD pipeline

This repository’s automation is **bash + native AZL gates** (no Rust toolchain at repo root). Descriptions below match the workflows in `.github/workflows/`.

## Workflows (by role)

| Workflow | When | What it does |
|----------|------|----------------|
| **`test-and-deploy.yml`** | PR + push `main`/`master` | Full `run_all_tests.sh`, native engine **matrix** (O2 / O0 / Os), **benchmark** gate + artifacts, **GCC/lcov** coverage artifact for `tools/azl_native_engine.c`, **Docker** build; on **main** push also **GHCR** publish and optional **staging** webhook (`STAGING_DEPLOY_WEBHOOK`). |
| `ci.yml` | PR + push `main`/`master` | Placeholder / stale-v2 guards, `run_full.sh`, `audit_live_path.sh`, native smoke, perf smoke, benchmark gate, full tests, AZME E2E job. |
| `native-release-gates.yml` | PR + push `main`/`master` | Canonical stack, native gates, legacy blocklist, live verify, `run_all_tests.sh`. |
| `azl-ci.yml` | PR + push (all branches) | Placeholders + `run_all_tests.sh` + `run_examples.sh`. |
| `nightly.yml` | Schedule + manual | Sysproxy integration / health checks. |
| `release.yml` | Tags `v*.*.*` | GitHub Release assets (sample bundles + runbooks). |

To save GitHub Actions minutes, consider **disabling or slimming** overlapping workflows once you standardize on `test-and-deploy.yml` + one lightweight gate workflow.

## Local parity

- Tests: `./scripts/run_all_tests.sh` (see root `Makefile` `make test`).
- Includes `scripts/verify_azl_use_vm_path.sh` (static check for `AZL_USE_VM` docs + interpreter wiring).
- Release order: `RELEASE_READY.md` (canonical gate sequence).

## Coverage

- **Native engine (C):** produced in CI by `scripts/ci_native_engine_coverage.sh` (HTML + `coverage.info` artifacts).
- **Full AZL source coverage:** not yet a single unified report; extend harness / tooling over time.
