# GitHub branch protection (`main`)

**`main`** uses the REST **branch protection** API with **required status checks** from **GitHub Actions** (**`app_id` 15368**).

## Single source of truth

**`release/ci/required_github_status_checks.json`** defines:

- Which **job ids** and **`name:`** lines in **`.github/workflows/test-and-deploy.yml`** correspond to required checks (including matrix expansion).
- What must **not** be required (**`deploy-staging`**).

**`scripts/gh_apply_main_branch_protection.sh`** reads that JSON to build the API payload and to compare on **`--verify`**.

## CI contract (no admin token)

**`scripts/verify_required_github_status_checks_contract.sh`** runs in **Test and Deploy** and **AZL CI (all branches)** after **`jq`** is installed. It proves the workflow file still matches the JSON (rename a job without updating the JSON → **PR fails**).

**We do not** run live **`GET …/branches/main/protection`** from Actions on every PR: the default **`GITHUB_TOKEN`** usually **cannot** read branch-protection settings, and storing a highly privileged PAT in secrets only to duplicate what maintainers already verify is a **larger blast radius** than the value gained. Maintainers use **`make branch-protection-verify`** after policy changes.

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

**Not required:** **Deploy staging** — skipped on **`pull_request`**; requiring it would block PR merges.

**Strict updates:** **`strict: true`** on the API.

No required approving reviews in the default payload. Add reviewers under **Settings → Branches** if your org wants them.

## Apply / verify (maintainers)

```bash
make branch-protection-contract   # workflow vs JSON only (same as CI)
make branch-protection-apply      # PUT (needs gh + repo admin)
make branch-protection-verify     # GET + compare to JSON (needs gh + can read protection)
bash scripts/gh_apply_main_branch_protection.sh --dry-run   # jq only; print API body
```

Optional argument: branch name (default from JSON **`branch_default`**, usually **`main`**).

Exit codes: **`docs/ERROR_SYSTEM.md`** — **Branch protection** and **Required GitHub status checks contract**.

## Inspect via `gh`

```bash
gh api repos/AZBCBA/AZL-Language/branches/main/protection --jq '.required_status_checks'
```

## Export JSON for a manual PUT (forks)

```bash
bash scripts/gh_apply_main_branch_protection.sh --dry-run > /tmp/protection-body.json
gh api --method PUT repos/OWNER/REPO/branches/main/protection --input /tmp/protection-body.json
```

**Discover check contexts** after a green run:

```bash
gh api repos/AZBCBA/AZL-Language/commits/main/check-runs \
  --jq '.check_runs[] | select(.app.slug=="github-actions") | {name, app_id: .app.id}'
```

## Related

- [CI_CD_PIPELINE.md](CI_CD_PIPELINE.md) — workflow roles and canonical **`test-and-deploy.yml`**.
