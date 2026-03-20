## Description
Brief description of the change.

## Type of change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation
- [ ] Refactor / cleanup

## Checklist
- [ ] Changes follow [CONTRIBUTING.md](https://github.com/AZBCBA/AZL-Language/blob/main/docs/CONTRIBUTING.md) and [AZL Language Rules](https://github.com/AZBCBA/AZL-Language/blob/main/docs/language/AZL_LANGUAGE_RULES.md).
- [ ] Documentation updated under `docs/` if behavior or syntax changed.
- [ ] No placeholders or mocks in production paths; error handling used where appropriate.
- [ ] Merging to **`main`**: **Test and Deploy** must satisfy **eight** required checks (see [docs/GITHUB_BRANCH_PROTECTION.md](docs/GITHUB_BRANCH_PROTECTION.md)); if you change **`test-and-deploy.yml`** job **`name:`** or ids, update **`release/ci/required_github_status_checks.json`** (CI runs **`scripts/verify_required_github_status_checks_contract.sh`**) and have a maintainer run **`make branch-protection-apply`**.

## How was this tested?
How did you verify the change (e.g. `bash scripts/check_azl_native_gates.sh` — **gate 0** runs `self_check_release_helpers.sh` + manifest checks — `bash scripts/verify_native_runtime_live.sh`, `bash scripts/run_all_tests.sh`)? Exit code map: [docs/ERROR_SYSTEM.md](docs/ERROR_SYSTEM.md) — **Shell helpers**, **Native gates** (`check_azl_native_gates.sh`), **Strength bar**, **Runtime spine contract**, **Release checkout assertion** (see also [CONTRIBUTING.md](docs/CONTRIBUTING.md) § Native gates).
