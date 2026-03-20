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


