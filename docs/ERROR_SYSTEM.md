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
| `scripts/gh_verify_remote_tag.sh` | **2** | Usage: missing **`<tag>`** argument |
| | **3** | **`GITHUB_REPOSITORY`** unset |
| | **4** | **`GH_TOKEN`** unset |
| | **5** | **`gh`** or **`python3`** not found |
| | **6** | Tag shape invalid (must match **`gh_create_sample_release`** pattern) |
| | **7** | **`refs/tags/<tag>`** not found on remote (**`gh api`** failed) |
| `scripts/gh_create_sample_release.sh` | **2** | **`gh`** not found |
| | **3** | **`GITHUB_REPOSITORY`** or **`GH_TOKEN`** unset; or **`GITHUB_REF`** unset when **`AZL_RELEASE_TAG`** unset |
| | **4** | **`GITHUB_REF`** not **`refs/tags/v*.*.*`** and **`AZL_RELEASE_TAG`** unset |
| | **5** | Tag does not match **`vMAJOR.MINOR.PATCH`** (+ optional **`-prerelease`** / **`+build`**) |
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


