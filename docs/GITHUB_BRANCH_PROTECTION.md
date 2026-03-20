# GitHub branch protection (`main`)

**`main`** uses the REST **branch protection** API with **required status checks** from **GitHub Actions** (**`app_id` 15368**). The list is defined in **`scripts/gh_apply_main_branch_protection.sh`** (single source of truth) and matches **`.github/workflows/test-and-deploy.yml`** job names.

## Required checks (current)

| Check name (job `name` in `test-and-deploy.yml`) | Role |
|--------------------------------------------------|------|
| **Gates and full test suite** | Repo guards, **`run_all_tests.sh`**, **`perf_smoke.sh`** |
| **AZME provider E2E** | Enterprise AZME after gates |
| **Native engine (release-O2)** | Matrix: **`gcc -O2`** engine build |
| **Native engine (debug-O0)** | Matrix: **`gcc -O0 -g`** engine build |
| **Native engine (size-Os)** | Matrix: **`gcc -Os`** engine build |
| **Benchmarks and regression gate** | **`benchmark_gate.sh`** |
| **Native engine coverage (GCC / lcov)** | **`ci_native_engine_coverage.sh`** |
| **Docker image (build; push to GHCR on main)** | **`docker/build-push-action`** |

**Not required:** **Deploy staging** — that job is **`if:`** push to **`main`** only; it is **skipped on `pull_request`**, so requiring it would block PR merges.

**Strict updates:** branches must be up to date with **`main`** before merge (API **`strict: true`**).

No required approving reviews are enforced by this payload (solo/small-team default). Adjust in **Settings → Branches** if you add review rules.

## Apply / verify (preferred)

From repo root, with **`gh auth login`** and **admin** on the repository:

```bash
bash scripts/gh_apply_main_branch_protection.sh          # PUT (idempotent)
bash scripts/gh_apply_main_branch_protection.sh --verify # GET + compare (no write)
bash scripts/gh_apply_main_branch_protection.sh --dry-run # print JSON only
```

Optional argument: branch name (default **`main`**).

**Make targets:** **`make branch-protection-apply`**, **`make branch-protection-verify`**.

Exit codes: **`docs/ERROR_SYSTEM.md`** § **Branch protection (`gh_apply_main_branch_protection.sh`)**.

## Inspect via `gh`

```bash
gh api repos/AZBCBA/AZL-Language/branches/main/protection --jq '.required_status_checks'
```

## Export JSON for a manual PUT (forks)

```bash
bash scripts/gh_apply_main_branch_protection.sh --dry-run > /tmp/protection-body.json
# edit repo/branch, then:
gh api --method PUT repos/OWNER/REPO/branches/main/protection --input /tmp/protection-body.json
```

**Discover check contexts** after a green run (exact strings vary by matrix expansion):

```bash
gh api repos/AZBCBA/AZL-Language/commits/main/check-runs \
  --jq '.check_runs[] | select(.app.slug=="github-actions") | {name, app_id: .app.id}'
```

## Related

- [CI_CD_PIPELINE.md](CI_CD_PIPELINE.md) — workflow roles and canonical **`test-and-deploy.yml`**.
