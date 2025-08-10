## Strict Mode and Feature Flags

### Environment Variables
- `AZL_STRICT=1|true`: enable strict production behavior (default in CI)
  - Disables speculative/experimental hooks
  - Fails bootstrap if core files missing
  - Tightens timeouts/recursion guards
- `AZL_ENABLE_CONSCIOUSNESS=1|true`: opt-in experimental hooks (ignored when strict)

### Defaults
- CI, release images: strict ON
- Developer local runs: strict recommended; experimental flags for research ONLY

### Failure Behavior
- Strict mode converts missing dependencies and partial bootstraps into hard errors
- Experimental flags MUST NOT change semantics in strict mode

### Implementation Notes (current)
- Pure AZL runtime enforces recursion/cycle guards and deterministic execution when `AZL_STRICT` is enabled.
- Virtual OS uses in-memory stores only in strict mode; external bridges are disabled.
- Strict-mode policies are implemented in `azl/runtime/interpreter/azl_interpreter.azl` and `azl/system/azl_system_interface.azl`.


