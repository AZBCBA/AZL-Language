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

**One shot (recommended):**

```bash
RUN_OPTIONAL_BENCHES=0 bash scripts/run_full_repo_verification.sh
```

Use `RUN_OPTIONAL_BENCHES=1` (default) to also run native + enterprise LLM benches when backends are available.

**Or** run in this exact order:

1. `bash scripts/enforce_canonical_stack.sh`
2. `bash scripts/check_azl_native_gates.sh`
3. `bash scripts/enforce_legacy_entrypoint_blocklist.sh`
4. `bash scripts/verify_native_runtime_live.sh` (minimal bundle — fast C-engine HTTP contract before the long suite)
5. `bash scripts/run_all_tests.sh` — includes `scripts/run_tests.sh`, which runs **`verify_enterprise_native_http_live.sh`** (fat combined + `::build.daemon.enterprise`) after the minimal live verify, then quantum LHA3 + grammar + VM/azlpack/LSP checks.

All commands must pass with exit code `0`.

## Contributor quick bar (subset of release)

For a fast, scripted check that still exercises **native gates** (F2/F3/G/H, engine build) and the **live** `GET /api/llm/capabilities` probe:

```bash
bash scripts/verify_azl_strength_bar.sh
```

Documented in `docs/AZL_DOCUMENTATION_CANON.md` §1.7. This **does not** replace the five-step block above (it omits `enforce_*` scripts and `run_all_tests.sh`).

## Optional — product / LLM benchmarks

After gates are green, you can measure latency on real backends (not required for release exit code):

```bash
bash scripts/run_product_benchmark_suite.sh
```

- Requires **`ollama serve`** and a pulled model for the C-engine leg.
- The enterprise **`POST /v1/chat`** leg runs only if **`AZL_API_TOKEN`** is set in the environment (daemon on **`AZL_ENTERPRISE_PORT`**, default `8080`). For local convenience you may put the token in **`.azl/local_api_token`** (first line only; **`chmod 600`**); that directory is gitignored.

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

## GitHub Release (sample assets on tag)

After gates are green on the commit you intend to ship:

1. Create an annotated or lightweight tag matching **`vMAJOR.MINOR.PATCH`** with optional SemVer suffixes, e.g. **`v1.2.3`**, **`v1.2.3-rc.1`**, **`v1.2.3+build.1`** (see **`scripts/gh_create_sample_release.sh`** for the exact pattern).
2. Push the tag: `git push origin v1.2.3` (example).
3. **`.github/workflows/release.yml`** runs: prepares **`dist/`** (sample `.azl` + **`README.md`** / **`OPERATIONS.md`**), then **`gh release create`** with **`--verify-tag`**.

**Errors (no silent fallback):** the script exits **2–8** with **`ERROR:`** on stderr for missing **`gh`**, bad/missing env, non-tag **`GITHUB_REF`** (when **`AZL_RELEASE_TAG`** is unset), invalid tag shape, missing **`dist/*`**, existing release for that tag, or **`gh`** failure.

**Manual release (Actions UI):** run **Release** → **Run workflow** and set **tag** to an existing remote tag (e.g. **`v1.2.3`**). The job checks out that ref, builds **`dist/`**, sets **`AZL_RELEASE_TAG`**, and creates the GitHub Release. **Do not** run the workflow without the **tag** input (it is **required**). Tag-push runs leave **`AZL_RELEASE_TAG`** empty and use **`GITHUB_REF`** as before.

**Permissions:** the workflow sets **`contents: write`** for **`GITHUB_TOKEN`** so the release can be created.
