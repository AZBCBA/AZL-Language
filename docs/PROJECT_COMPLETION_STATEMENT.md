# Project completion — what “done” means

AZL uses **two tiers**. Saying **“the project is complete”** without a qualifier is ambiguous; use the phrases below precisely.

---

## Tier A — Native release profile **complete** (shipping bar)

This tier means: **the repository meets every automated gate we use to ship the native-first profile**, and **docs/CI match the workflow contract**. It does **not** mean the entire language roadmap (full AZL-in-AZL self-host, P1+ layers) is finished.

### Criteria (all must pass)

1. **`scripts/verify_required_github_status_checks_contract.sh`** — `release/ci/required_github_status_checks.json` ↔ `.github/workflows/test-and-deploy.yml`.
2. **`RUN_OPTIONAL_BENCHES=0 bash scripts/run_full_repo_verification.sh`** — [RELEASE_READY.md](../RELEASE_READY.md) order (step **0:** promoted **doc pieces**; see **`docs/INTEGRATION_VERIFY.md`**), canonical stack, native gates, **`verify_azl_interpreter_semantic_spine_smoke.sh`** (P0.1b **`init`**), **`verify_azl_interpreter_semantic_spine_behavior_smoke.sh`** (P0.1c interpret bridge), legacy blocklist, minimal live HTTP, **`run_all_tests.sh`** (optional LLM/product benches **off** so completion does not depend on Ollama/daemon).
3. **`bash scripts/verify_azl_strength_bar.sh`** — four pillars stamp ([AZL_DOCUMENTATION_CANON.md](AZL_DOCUMENTATION_CANON.md) §1.7).

### One command

```bash
bash scripts/verify_native_release_profile_complete.sh
```

**Make:** `make native-release-profile-complete`

Exit codes: child scripts propagate; see [ERROR_SYSTEM.md](ERROR_SYSTEM.md) § *Native release profile completeness*.

### When Tier A is true, you may say

- **“The native release profile is complete.”**
- **“The repo passes the documented shipping bar.”**
- **“CI + release gates + strength bar are green (optional benches excluded).”**

---

## Tier B — Language / platform roadmap (**not** implied by Tier A)

Defined in [PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md) and [AZL_DOCUMENTATION_CANON.md](AZL_DOCUMENTATION_CANON.md) §3. Outstanding examples:

| Area | Status |
|------|--------|
| **P0 remainder** | Semantic spine wide enough to **execute** full `azl/runtime/interpreter/azl_interpreter.azl` as the runtime child (or verified equivalent) — **large effort**; default spine today remains C minimal / Python parity subset per env. |
| **P1** | Canonical HTTP profile per deployment fully converged (C-only vs enterprise `http_server.azl`) beyond current honest dual-stack docs. |
| **P2–P5** | Process policy, VM breadth, packages, in-process GGUF — phased / deferred per roadmap. |

### When Tier B is incomplete, do **not** say

- “AZL language implementation is finished.”
- “Full self-hosting interpreter is done.”
- “All roadmap layers are complete.”

---

## Summary

| Phrase | Tier |
|--------|------|
| Native release profile complete | **A** — run `verify_native_release_profile_complete.sh` |
| Whole project / full roadmap complete | **B** — track [PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md) |

**Finishing the tests** on `main` (GitHub **Test and Deploy** green) is necessary but not sufficient for **Tier A** until you also run the local verifier above (includes full repo verification + strength bar + contract). CI on `main` already covers most of the same surface; the script is the **explicit, documented** completion ceremony for maintainers and releases.
