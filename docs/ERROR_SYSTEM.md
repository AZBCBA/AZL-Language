## Error System (Production, Mandatory)

### Goals
- Zero panics in strict mode; all failure modes represented as typed errors
- Rich diagnostics: spans, categories, causes, and call stacks
- Clear recovery policies; fail-fast only for unrecoverable conditions

### Taxonomy
- Parse: invalid tokens, unexpected constructs, unterminated strings
- Type: invalid coercions, arity mismatches, unsupported operations
- Runtime: out-of-bounds, undefined vars, division by zero, timeouts
- Compilation: IR/bytecode generation failures, symbol resolution
- IO/Network: filesystem, network errors, external process failures
- Other: explicitly categorized if none of the above apply
 - Timeout: listener/component timeouts
 - Cycle: event chain cycle detection
 - FFI: cross-language/bridge errors

### Structure
- Pure AZL interpreter: records `{ kind, message, context }` in `::errors` and emits `log_error`. Event cycle/recursion guards return safe statuses and log.
- (Historical) Rust `AzlError` variants existed; treat as legacy. The pure runtime uses AZL-level structures.

### Practices
- Always attach spans where an error originates and where it is observed
- Preserve causes (`source`) for chained errors
- Log with structured fields (component, operation, span, error_kind)
- In events and FFI, never swallow errors; propagate or convert with fidelity
 - Current implementation: new variants (`Timeout`, `Cycle`, `Ffi`) are available and used by runtime; span/call-context propagation is planned during interpreter/VM work. *[VERIFIED: Error variants implemented in src/error.rs:88-96 with proper thiserror integration; helper methods at lines 138-148]*

### Recovery Policies
- Parser: continue to next statement boundary; accumulate diagnostics
- Interpreter: continue unless state would be corrupted; otherwise abort current component with precise error
- EventBus: recursion guard, timeout; log and drop offending event if exceeded; report summary

### Quality Gates
- No `placeholder|TODO|FIXME` in `.azl` sources committed to main.
- Event recursion/cycle detection must be active by default.
- I/O and HTTP in pure mode must route through virtual OS stores.
- **GitHub Actions:** PR/push to **`main`**/**`master`** is gated by **`test-and-deploy.yml`**; **`main`** branch protection requires **eight** of those jobs ( **`release/ci/required_github_status_checks.json`** + **`docs/GITHUB_BRANCH_PROTECTION.md`** ). CI runs **`verify_required_github_status_checks_contract.sh`** so renames cannot drift silently. Failing steps surface **`ERROR:`** / numeric exits — no silent green. **`ci.yml`** and **`native-release-gates.yml`** are **`workflow_dispatch` only**. **`nightly.yml`** runs **`check_azl_native_gates.sh`** then sysproxy E2E. Full matrix: **`docs/CI_CD_PIPELINE.md`**.

### Shell helpers (release + live verify)

Production scripts return **non-zero** with **`ERROR:`** on **stderr**; no silent fallback.

| Script | Exit | Meaning |
|--------|------|---------|
| `scripts/self_check_release_helpers.sh` | **40** | **`rg`** not found |
| | **41** | Expected release helper file missing |
| | **42** | **`bash -n`** failed on a helper script |
| | **43** | **`azl_release_tag_policy.sh`** direct run did not exit **2** |
| | **44** | Direct-run **ERROR** message contract broken |
| | **45** | Valid tag **`v1.2.3`** rejected by policy |
| | **46** | Invalid tag assert did not exit **87** |
| | **47** | **`gh_verify_remote_tag.sh`** no-arg exit not **2** |
| | **48** | **`gh_verify_remote_tag.sh`** usage text missing |
| | **49** | **`jq`** not found |
| | **50** | **`release/native/manifest.json`** unreadable or invalid JSON |
| | **51** | **`gates[]`** entry not a non-empty string |
| | **57** | **`gates[]`** path not a file on disk |
| | **52** | **`github_release`** not an object |
| | **53** | **`github_release.workflow`** missing or not a non-empty string |
| | **54** | **`github_release.workflow`** file missing on disk |
| | **55** | **`github_release.scripts`** not an array |
| | **56** | **`github_release.scripts`** entry not a non-empty string |
| | **58** | **`github_release.scripts`** path not a file on disk |
| `scripts/azl_release_tag_policy.sh` | **2** | Run directly — **source** from release scripts only |
| `scripts/gh_verify_remote_tag.sh` | **2** | Usage: missing **`<tag>`** argument |
| | **3** | **`GITHUB_REPOSITORY`** unset |
| | **4** | **`GH_TOKEN`** unset |
| | **5** | **`gh`** or **`jq`** not found |
| | **6** | Tag shape invalid (see **`scripts/azl_release_tag_policy.sh`**) |
| | **7** | **`refs/tags/<tag>`** not found on remote (**`gh api`** failed) |
| | **9** | **`jq @uri`** encoding failed for **`refs/tags/<tag>`** |
| `scripts/gh_create_sample_release.sh` | **2** | **`gh`** not found |
| | **3** | **`GITHUB_REPOSITORY`** or **`GH_TOKEN`** unset; or **`GITHUB_REF`** unset when **`AZL_RELEASE_TAG`** unset |
| | **4** | **`GITHUB_REF`** not **`refs/tags/v*.*.*`** and **`AZL_RELEASE_TAG`** unset |
| | **5** | Tag does not match **`vMAJOR.MINOR.PATCH`** (+ optional **`-prerelease`** / **`+build`**) — **`azl_release_tag_policy.sh`** |
| | **6** | Missing file under **`dist/`** |
| | **7** | GitHub Release already exists for that tag |
| | **8** | **`gh release create`** failed |
| `scripts/verify_native_runtime_live.sh` | **69** | **`AZL_NATIVE_ENGINE_BIN`** set but file missing or not executable |
| | **70** | Engine did not reach **`/healthz`** + **`/readyz`** HTTP **200** in time |
| | **71** | **`/healthz`**, **`/readyz`**, **`/status`**, or **`/api/exec_state`** contract failed |
| | **72** | Native-only **`scripts/azl run`** not blocked (**rc ≠ 64**) |
| | **74** | **`/api/llm/capabilities`** not **`ok`** |
| | **75** | Capabilities missing **`ollama_http_proxy`** |
| | **76** | Invalid **`gguf_in_process`** shape |
| | **77** | Capabilities stub/embedded contract mismatch |
| `scripts/verify_enterprise_native_http_live.sh` | **80** | **`healthz` + `readyz`** not HTTP **200** within deadline |
| | **81** | **`healthz` / `readyz` / `status` / `exec_state`** contract failed |
| | **82** | **`healthz`** missing enterprise entry hint (**`build.daemon.enterprise`**) |
| | **83** | Could not parse **`combined`** path from **`/status`** |
| | **84** | **`/status` `combined`** path mismatch vs built enterprise combined |
| | **85** | **`/api/llm/capabilities`** not **`ok`** |
| | **86** | Capabilities missing **`ollama_http_proxy`** |
| | **87** | Stub/embedded capabilities contract mismatch (**`ERR_*` / `error:null`**) |
| | **88** | Embedded **`gguf`** shape invalid or **`gguf_in_process`** boolean missing |

### Native gates (`scripts/check_azl_native_gates.sh`)

**Gate 0** runs **`self_check_release_helpers.sh`** — its exits **40–58** propagate unchanged.

| Exit | Meaning |
|------|---------|
| **10** | **`start_azl_native_mode.sh`** missing **`AZL_NATIVE_ONLY`** guard |
| **12** | **`verify_native_runtime_live.sh`** not executable |
| **13** | **`verify_quantum_lha3_stack.sh`** not executable |
| **14** | **`verify_azl_grammar_conformance.sh`** not executable |
| **16** | **`verify_enterprise_native_http_live.sh`** not executable |
| **19** | VM opcode token missing in **`azl/runtime/vm/azl_vm.azl`** |
| **20** | Native engine binary not built or not executable |
| **21** | **`tools/azl_native_engine.c`** not enforcing **`AZL_NATIVE_RUNTIME_CMD`** |
| **22** | Native engine missing **`GET /api/llm/capabilities`** |
| **23** | **`azl-interpreter-minimal`** missing after build |
| **24** | C minimal **`c_minimal_link_ping`** run failed |
| **25** | C minimal output missing **`C_MINIMAL_LINK_PING_OK`** |
| **26** | Python spine host **`c_minimal_link_ping`** run failed |
| **27** | C vs Python **`c_minimal_link_ping`** stdout mismatch |
| **28** | P0 slice C run failed or output missing **`P0_SEMANTIC_INTERPRETER_SLICE_OK`** |
| **29** | Python spine host P0 slice run failed |
| **30** | C vs Python P0 slice stdout mismatch |
| **31** | Script defaults **`AZL_ENABLE_LEGACY_HOST`** to **1** (**forbidden**) |

**Gate G** runs **`verify_runtime_spine_contract.sh`** — exits **90–96** propagate (table below). **Gate H** runs **`verify_p0_interpreter_tokenizer_boundary.sh`** (Python **`SystemExit`**, typically **1** with **`ERROR:`** on stderr).

### Runtime spine contract (`scripts/verify_runtime_spine_contract.sh`)

| Exit | Meaning |
|------|---------|
| **90** | Default **`AZL_RUNTIME_SPINE`** must resolve to C minimal launcher |
| **91** | **`AZL_RUNTIME_SPINE=azl_interpreter`** must resolve to semantic launcher |
| **92** | **`python3`** not found |
| **93** | Spine host invalid combined path did not exit **71** |
| **94** | Spine host stderr missing **`ERR_AZL_COMBINED_PATH_INVALID`** |
| **95** | Spine host **`c_minimal_link_ping`** did not exit **0** |
| **96** | Spine host output missing **`C_MINIMAL_LINK_PING_OK`** |

### Strength bar (`scripts/verify_azl_strength_bar.sh`)

Prefix **`ERROR[AZL_STRENGTH_BAR]:`** on stderr for script-owned failures.

| Exit | Meaning |
|------|---------|
| **1** | Not run from repo root |
| **2** | **`rg`** not found |
| **3** | **`jq`** not found |
| **4** | **`python3`** not found |
| **5** | **`gcc`** not found |
| **10** | Step 1: **`check_azl_native_gates.sh`** failed (see exits above) |
| **11** | Step 2: **`verify_native_runtime_live.sh`** failed |
| **12** | Step 3: **`verify_enterprise_native_http_live.sh`** failed |

### Release checkout assertion (`scripts/gh_assert_checkout_matches_tag.sh`)

Used by **`.github/workflows/release.yml`** after **`actions/checkout`** at the release tag.

| Exit | Meaning |
|------|---------|
| **2** | Usage: missing **`<tag>`** argument |
| **3** | **`refs/tags/<tag>^{commit}`** not found (shallow clone or wrong tag) |
| **4** | **`HEAD`** ≠ peeled tag commit |
| **5** | **`git`** not found |

### Native release profile completeness (`scripts/verify_native_release_profile_complete.sh`)

**Tier A** ceremony: runs **`verify_required_github_status_checks_contract.sh`**, **`run_full_repo_verification.sh`** with **`RUN_OPTIONAL_BENCHES=0`**, **`verify_azl_strength_bar.sh`**. See **`docs/PROJECT_COMPLETION_STATEMENT.md`**.

| Exit | Meaning |
|------|---------|
| *(propagated)* | Same code as the first failing child script (contract **11–17**, release/verify/strength-bar tables, etc.) |

### Required GitHub status checks contract (`scripts/verify_required_github_status_checks_contract.sh`)

Runs in **CI** ( **`test-and-deploy.yml`**, **`azl-ci.yml`** ): validates **`release/ci/required_github_status_checks.json`** against **`.github/workflows/test-and-deploy.yml`** (job ids, **`name:`** lines, matrix variants). No GitHub API.

| Exit | Meaning |
|------|---------|
| **11** | **`jq`** not found |
| **12** | Config missing / invalid JSON / bad **`workflow_assertions`** / **`must_not_require_job_ids`** inconsistency |
| **13** | **`workflow_file`** path missing on disk |
| **14** | Job block or **`name:`** line mismatch vs assertion |
| **15** | Matrix variant missing under **`matrix.include`** |
| **16** | Forbidden context string appears in derived required list |
| **17** | Derived required-context list empty |

### Branch protection (`scripts/gh_apply_main_branch_protection.sh`)

Maintainer / local: **PUT**, **`--dry-run`**, or **`--verify`** **GET**. Required contexts are read from **`release/ci/required_github_status_checks.json`** (not hard-coded). **`--dry-run`** needs **`jq`** only. **PUT** / **`--verify`** need **`gh`** + auth (**`--verify`** needs permission to read protection). Not invoked from Actions.

| Exit | Meaning |
|------|---------|
| **0** | **`--help`** / **`-h`** (usage on stderr), or **`--verify`** success |
| **2** | Invalid arguments (e.g. both **`--dry-run`** and **`--verify`**, or extra branch argument) |
| **3** | **`GITHUB_REPOSITORY`** unset and **`gh repo view`** could not resolve owner/repo |
| **4** | **`release/ci/required_github_status_checks.json`** missing, invalid JSON, or cannot derive contexts |
| **5** | **`gh`** or **`jq`** not found |
| **6** | **`gh`** not authenticated (N/A for **`--dry-run`**) |
| **7** | GitHub API **PUT** **`…/branches/<branch>/protection`** failed (**stderr** includes API body if present) |
| **8** | **`--verify`**: branch not protected or **GET** **404** / “Branch not protected” |
| **9** | **`--verify`**: **`strict`** is not **true**, or required **contexts** / **`checks[].context`** set ≠ expected (sorted JSON arrays differ) |
| **10** | **`--verify`**: **GET** failed (non-404), or response was not valid JSON |


