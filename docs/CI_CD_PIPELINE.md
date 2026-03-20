# CI/CD pipeline

This repository’s automation is **bash + native AZL gates** (no Rust toolchain at repo root). Descriptions below match the workflows in `.github/workflows/`.

## Workflows (by role)

| Workflow | When | What it does |
|----------|------|----------------|
| **`test-and-deploy.yml`** | PR + push `main`/`master` | Full `run_all_tests.sh`, native engine **matrix** (O2 / O0 / Os), **benchmark** gate + artifacts, **GCC/lcov** coverage artifact for `tools/azl_native_engine.c`, **Docker** build (**buildx@v4**, **login@v4**, **build-push@v7**, Node 24); on **main** push also **GHCR** publish and optional **staging** webhook (`STAGING_DEPLOY_WEBHOOK`). |
| `ci.yml` | PR + push `main`/`master` | Placeholder / stale-v2 guards, `run_full.sh`, `audit_live_path.sh`, native smoke, perf smoke, benchmark gate, full tests, AZME E2E job. |
| `native-release-gates.yml` | PR + push `main`/`master` | Canonical stack, native gates, legacy blocklist, live verify, `run_all_tests.sh`. |
| **`azl-ci.yml`** (*AZL CI (all branches)*) | PR + push (all branches) | Installs `ripgrep`/build deps; placeholders + `run_all_tests.sh` + `run_examples.sh`. |
| `nightly.yml` | Schedule + manual | Sysproxy integration / health checks. |
| `release.yml` | Tags `v*.*.*` + **`workflow_dispatch`** | **Dispatch:** **`scripts/gh_verify_remote_tag.sh`** (remote **`refs/tags/<tag>`** via **`gh api`**, URL-encoded) runs **before** checkout. Then GitHub Release assets via **`scripts/gh_create_sample_release.sh`** / **`gh release create`** (no **`softprops/action-gh-release`** / Node 20 composite). Tag shape: **`vMAJOR.MINOR.PATCH`** plus optional **`-prerelease`** / **`+build`**. **`permissions: contents: write`**. **Dispatch:** required input **`tag`** → checkout at that ref, **`AZL_RELEASE_TAG`** set. **Tag push:** no verify step; **`AZL_RELEASE_TAG`** empty, script uses **`GITHUB_REF`**. |

To save GitHub Actions minutes, consider **disabling or slimming** overlapping workflows once you standardize on `test-and-deploy.yml` + one lightweight gate workflow.

## Release helper self-check

- **`scripts/self_check_release_helpers.sh`** — **`bash -n`** on GitHub release helpers, **`azl_release_tag_policy.sh`** direct-run guard, sourced assert tests, **`gh_verify_remote_tag.sh`** usage. Invoked at the start of **`scripts/check_azl_native_gates.sh`** (**gate 0**), so any workflow that runs native gates (including **`ci.yml`** runtime smoke and **`run_tests.sh`**) validates release scripts. Listed under **`github_release`** in **`release/native/manifest.json`**.

## Local parity

- Tests: `./scripts/run_all_tests.sh` (see root `Makefile` `make test`).
- Includes `scripts/test_azl_use_vm_path.sh` (`AZL_USE_VM` wiring, VM vs tree-walker **source parity**, eligible fixture lint; see `docs/AZL_NATIVE_RUNTIME_CONTRACT.md`).
- Includes `scripts/verify_azlpack_local.sh` (build + install `azl-hello` .azlpack), `scripts/verify_lsp_smoke.sh` (`initialize` + `definitionProvider` + `didOpen` → `publishDiagnostics`), and `scripts/test_lsp_jump_to_def.sh` (`textDocument/definition` on `azl/tests/lsp_definition_resolution.azl`).
- Includes `scripts/verify_native_bundle_excludes_host_integrations.sh` (no host-shaped AnythingLLM paths in `run_enterprise_daemon.sh`).
- Release order: `RELEASE_READY.md` (canonical gate sequence).

## Coverage

- **Native engine (C):** produced in CI by `scripts/ci_native_engine_coverage.sh` (HTML + `coverage.info` artifacts). That script sets **`AZL_NATIVE_ENGINE_BIN`** to the **`gcc --coverage`** binary before **`verify_native_runtime_live.sh`**, so verify does not overwrite it with **`build_azl_native_engine.sh`** (see script headers). **`lcov` / `genhtml`** failures log under **`.azl/lcov_capture.log`** / **`.azl/genhtml.log`**.
- **Full AZL source coverage:** not yet a single unified report; extend harness / tooling over time.
