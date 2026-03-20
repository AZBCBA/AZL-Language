# GitHub branch protection (`main`)

**`main`** uses the REST **branch protection** API with **required status checks** from **GitHub Actions** (**`app_id` 15368**).

## Required checks (current)

| Check name (job `name` in `test-and-deploy.yml`) | Role |
|--------------------------------------------------|------|
| **Gates and full test suite** | Repo guards, **`run_all_tests.sh`**, **`perf_smoke.sh`** |
| **AZME provider E2E** | Enterprise AZME path after gates |

**Strict updates:** branches must be up to date with **`main`** before merge (API **`strict: true`**).

No required approving reviews are enforced by this payload (solo/small-team default). Adjust in **Settings → Branches** if you add review rules.

## Verify

```bash
gh api repos/AZBCBA/AZL-Language/branches/main/protection --jq '.required_status_checks'
```

## Apply via script (preferred)

From repo root, with **`gh auth login`** and **admin** on the repository:

```bash
bash scripts/gh_apply_main_branch_protection.sh
```

- **`--dry-run`** — print JSON only, no API call.
- Optional second argument — branch name (default **`main`**).

Exit codes: **`docs/ERROR_SYSTEM.md`** § **Branch protection (`gh_apply_main_branch_protection.sh`)**.

## Re-apply manually (maintainers, repo admin)

Save body to a file (adjust org/repo if you fork):

```json
{
  "required_status_checks": {
    "strict": true,
    "checks": [
      { "context": "Gates and full test suite", "app_id": 15368 },
      { "context": "AZME provider E2E", "app_id": 15368 }
    ]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": false,
  "lock_branch": false,
  "allow_fork_syncing": false
}
```

```bash
gh api --method PUT repos/AZBCBA/AZL-Language/branches/main/protection --input body.json
```

**Discover check contexts** after a green run on **`main`**:

```bash
gh api repos/AZBCBA/AZL-Language/commits/main/check-runs \
  --jq '.check_runs[] | select(.app.slug=="github-actions") | {name, app_id: .app.id}'
```

## Optional extra required checks

To also block merge until benchmarks, Docker, or coverage finish, add entries to **`checks`** using the **exact** `name` from the API output (e.g. **Benchmarks and regression gate**, **Docker image (build; push to GHCR on main)**). Prefer not to require **`Deploy staging`** (runs only on **`main`** push after image build).

## Related

- [CI_CD_PIPELINE.md](CI_CD_PIPELINE.md) — workflow roles and canonical **`test-and-deploy.yml`**.
