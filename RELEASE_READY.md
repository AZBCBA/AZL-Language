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

**Declare native release profile complete (Tier A — includes contract + strength bar):**

```bash
bash scripts/verify_native_release_profile_complete.sh
# or: make native-release-profile-complete
```

See **`docs/PROJECT_COMPLETION_STATEMENT.md`** (Tier A vs Tier B roadmap).

**Or** run in this exact order:

0. `bash scripts/verify_documentation_pieces.sh --promoted-only` — **`release/doc_verification_pieces.json`**; see **`docs/INTEGRATION_VERIFY.md`**
1. `bash scripts/enforce_canonical_stack.sh`
2. `bash scripts/check_azl_native_gates.sh` — **gate 0** runs **`scripts/self_check_release_helpers.sh`** (release helper **`bash -n`**, **`azl_release_tag_policy`** invariants, **`release/native/manifest.json`** via **`jq`** + **`gates[]` / `github_release`** paths on disk; needs **`rg`** + **`jq`**).
3. `bash scripts/verify_azl_interpreter_semantic_spine_smoke.sh` — Tier B **P0.1b**: real **`azl_interpreter.azl`** **`init`** on Python spine (stub **`::azl.security`**; **`docs/ERROR_SYSTEM.md`** **286–290**).

4. `bash scripts/verify_azl_interpreter_semantic_spine_behavior_smoke.sh` — Tier B **P0.1c**: stub + **`azl/tests/harness/azl_interpreter_semantic_spine_behavior_entry.azl`** + interpreter; **six** **`emit interpret`** + in-file cache hits + multi-line depth **`say`** + **`AZL_S6_ONLY`** (**548–561**).

5. `bash scripts/enforce_legacy_entrypoint_blocklist.sh`
6. `bash scripts/verify_native_runtime_live.sh` (minimal bundle — fast C-engine HTTP contract before the long suite)
7. `bash scripts/run_all_tests.sh` — includes `scripts/run_tests.sh`, which runs **`verify_enterprise_native_http_live.sh`** (fat combined + `::build.daemon.enterprise`) after the minimal live verify, then quantum LHA3 + grammar + VM/azlpack/LSP checks.

All commands must pass with exit code `0`.

## Contributor quick bar (subset of release)

For a fast, scripted check that still exercises **native gates** (F2–F160, G, G2, H, engine build) and the **live** `GET /api/llm/capabilities` probe:

```bash
bash scripts/verify_azl_strength_bar.sh
```

Documented in `docs/AZL_DOCUMENTATION_CANON.md` §1.7. This **does not** replace the **eight-step** release block above (steps **0–7**; it omits **`enforce_*`** scripts, interpreter spine smokes, and **`run_all_tests.sh`**).

## Optional — product / LLM benchmarks

After gates are green, you can measure latency on real backends (not required for **`make verify`**, which sets **`RUN_OPTIONAL_BENCHES=0`**):

```bash
RUN_OPTIONAL_BENCHES=1 bash scripts/run_full_repo_verification.sh
# or:
bash scripts/run_product_benchmark_suite.sh
```

- **C-engine / Ollama leg:** requires **`ollama serve`** and a pulled model when **`127.0.0.1:11434`** is reachable; otherwise the optional step logs a skip.
- **Enterprise `POST /v1/chat` leg:** requires **Profile B** (see [docs/CANONICAL_HTTP_PROFILE.md](docs/CANONICAL_HTTP_PROFILE.md)): daemon such as **`bash scripts/run_enterprise_daemon.sh`**, **`AZL_API_TOKEN`** matching the process (or **`.azl/local_api_token`** first line, **`chmod 600`**), and **`AZL_BUILD_API_PORT`** aligned with **`AZL_ENTERPRISE_PORT`** (default **8080**). Typed failures: **`ERROR[AZL_ENTERPRISE_V1_CHAT_BENCH]`**, exits **2** / **91** / **93** / **94** / **95** in **[docs/ERROR_SYSTEM.md](docs/ERROR_SYSTEM.md)** (**91**–**95** overlap **gate G** numbers — use stderr prefix).

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

The **`test-and-deploy.yml`** workflow (PR/push to **`main`**/**`master`**) must pass before you treat the branch as release-ready: it runs the same strict path as historical **`native-release-gates`** + **`ci.yml`** (guards, **`run_all_tests.sh`**, **`perf_smoke`**, AZME E2E) plus Docker/GHCR and optional staging. For a gates-only manual rerun, use **Actions → `native-release-gates (manual)`**. See `docs/CI_CD_PIPELINE.md`.

## GitHub Release (sample assets on tag)

After gates are green on the commit you intend to ship:

1. Create an annotated or lightweight tag matching **`vMAJOR.MINOR.PATCH`** with optional SemVer suffixes, e.g. **`v1.2.3`**, **`v1.2.3-rc.1`**, **`v1.2.3+build.1`** (see **`scripts/gh_create_sample_release.sh`** for the exact pattern).
2. Push the tag: `git push origin v1.2.3` (example).
3. **`.github/workflows/release.yml`** runs: prepares **`dist/`** (sample `.azl` + **`README.md`** / **`OPERATIONS.md`**), asserts **`git HEAD`** matches the peeled commit for **`refs/tags/<tag>`** (**`scripts/gh_assert_checkout_matches_tag.sh`**), then **`gh release create`** with **`--verify-tag`**.

**Errors (no silent fallback):** the script exits **2–8** with **`ERROR:`** on stderr for missing **`gh`**, bad/missing env, non-tag **`GITHUB_REF`** (when **`AZL_RELEASE_TAG`** is unset), invalid tag shape, missing **`dist/*`**, existing release for that tag, or **`gh`** failure.

**Manual release (Actions UI):** run **Release** → **Run workflow** and set **tag** to an existing remote tag (e.g. **`v1.2.3`**). The first step runs **`scripts/gh_verify_remote_tag.sh`**: **`gh api`** resolves URL-encoded **`refs/tags/<tag>`** on the remote; if missing or malformed, the job fails with **`ERROR`** before checkout or **`dist/`** work. Then the job checks out that ref, builds **`dist/`**, sets **`AZL_RELEASE_TAG`**, and creates the GitHub Release. **Do not** run the workflow without the **tag** input (it is **required**). Tag-push runs skip the verify step and leave **`AZL_RELEASE_TAG`** empty (**`GITHUB_REF`** drives the script).

**Permissions:** the workflow sets **`contents: write`** for **`GITHUB_TOKEN`** so the release can be created.
