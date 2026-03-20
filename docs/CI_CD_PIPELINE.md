# CI/CD pipeline

This repository’s automation is **bash + native AZL gates** (no Rust toolchain at repo root). Descriptions below match the workflows in `.github/workflows/`.

## Workflows (by role)

| Workflow | When | What it does |
|----------|------|----------------|
| **`test-and-deploy.yml`** | PR + push `main`/`master` + manual | **Canonical main CI/CD:** placeholders, stale-v2 **`rg`** gate, **`run_full.sh`**, **`audit_live_path.sh`**, **`run_all_tests.sh`** (includes **`run_tests.sh`**: canonical stack, native gates, live verify, grammar/quantum), **`perf_smoke.sh`**, native engine **matrix**, **benchmark** gate + artifacts, **GCC/lcov** for `tools/azl_native_engine.c`, **Docker** → **GHCR** on **main**; optional **staging** webhook. **`azme-e2e`** job after **`gate-and-test`**. |
| **`ci.yml`** (*AZL CI (manual)*) | **`workflow_dispatch` only** | Legacy layout for ad-hoc runs (unchanged steps). |
| **`native-release-gates.yml`** (*manual*) | **`workflow_dispatch` only** | Focused **`enforce_canonical_stack`** + **`check_azl_native_gates`** + blocklist + live verify + **`run_all_tests.sh`** (no Docker/benchmark matrix). |
| **`azl-ci.yml`** (*AZL CI (all branches)*) | PR + push (all branches) | Placeholders, stale-v2 gate, **`run_full.sh`**, **`audit_live_path.sh`**, **`run_all_tests.sh`**, **`run_examples.sh`**. |
| **`nightly.yml`** | Schedule (02:00 UTC) + manual | **`check_azl_native_gates.sh`** (**`jq`**, **`python3`**, **`rg`**, **`gcc`**) then sysproxy build + **`test_sysproxy_setup.sh`** + health probes + log artifacts. |
| `release.yml` | Tags `v*.*.*` + **`workflow_dispatch`** | **Dispatch:** **`gh_verify_remote_tag.sh`** before checkout. **After checkout:** **`gh_assert_checkout_matches_tag.sh`** (**`HEAD`** == **`refs/tags/<tag>^{commit}`**). Then **`dist/`** + **`gh_create_sample_release.sh`** / **`gh release create`**. Tag shape: **`vMAJOR.MINOR.PATCH`** plus optional **`-prerelease`** / **`+build`**. **`permissions: contents: write`**. **`fetch-depth: 0`** on checkout. **`AZL_RELEASE_TAG`** on dispatch only. |

**Canonical badge for `main`:** **`test-and-deploy.yml`**. **`ci.yml`** / **`native-release-gates.yml`** remain for manual debugging or release-focused reruns without the full deploy graph.

**Branch protection:** **`main`** requires **eight** **Test and Deploy** jobs — defined in **`release/ci/required_github_status_checks.json`**; CI enforces sync with the workflow via **`scripts/verify_required_github_status_checks_contract.sh`**. See [GITHUB_BRANCH_PROTECTION.md](GITHUB_BRANCH_PROTECTION.md). **Deploy staging** is not required (skipped on PRs). Maintainers: **`make branch-protection-apply`** / **`make branch-protection-verify`**.

## Release helper self-check

- **`scripts/self_check_release_helpers.sh`** — **`bash -n`** on **`azl_release_tag_policy.sh`**, **`gh_verify_remote_tag.sh`**, **`gh_assert_checkout_matches_tag.sh`**, **`gh_create_sample_release.sh`**, plus **`azl_release_tag_policy.sh`** direct-run guard, sourced assert tests, **`gh_verify_remote_tag.sh`** usage, and **`jq`** validation of **`release/native/manifest.json`** (JSON parse, **`gates[]`** / **`github_release.workflow`** / **`github_release.scripts`** paths on disk). **`gh_verify_remote_tag.sh`** encodes **`refs/tags/<tag>`** with **`jq @uri`** for **`gh api`**. Invoked at the start of **`scripts/check_azl_native_gates.sh`** (**gate 0**). Workflows that run gates install **`jq`** (**`test-and-deploy.yml`**, **`azl-ci.yml`**, **`nightly.yml`**, manual **`ci.yml`** / **`native-release-gates.yml`**; **`release.yml`** installs **`jq`** on **`workflow_dispatch`** before verify).

## Local parity

- Tests: `./scripts/run_all_tests.sh` (see root `Makefile` `make test`).
- Includes `scripts/test_azl_use_vm_path.sh` (`AZL_USE_VM` wiring, VM vs tree-walker **source parity**, eligible fixture lint; see `docs/AZL_NATIVE_RUNTIME_CONTRACT.md`).
- Includes `scripts/verify_azlpack_local.sh` (build + install `azl-hello` .azlpack), `scripts/verify_lsp_smoke.sh` (`initialize` + `definitionProvider` + `didOpen` → `publishDiagnostics`), and `scripts/test_lsp_jump_to_def.sh` (`textDocument/definition` on `azl/tests/lsp_definition_resolution.azl`).
- Includes `scripts/verify_native_bundle_excludes_host_integrations.sh` (no host-shaped AnythingLLM paths in `run_enterprise_daemon.sh`).
- Release order: `RELEASE_READY.md` (canonical gate sequence).

## Coverage

- **Native engine (C):** produced in CI by `scripts/ci_native_engine_coverage.sh` (HTML + `coverage.info` artifacts). That script sets **`AZL_NATIVE_ENGINE_BIN`** to the **`gcc --coverage`** binary before **`verify_native_runtime_live.sh`**, so verify does not overwrite it with **`build_azl_native_engine.sh`** (see script headers). **`lcov` / `genhtml`** failures log under **`.azl/lcov_capture.log`** / **`.azl/genhtml.log`**.
- **Full AZL source coverage:** not yet a single unified report; extend harness / tooling over time.
