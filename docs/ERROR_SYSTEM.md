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


