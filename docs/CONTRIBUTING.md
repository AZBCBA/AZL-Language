## Contributing Guidelines

### Active Work Areas (do not interfere)
- `src/lib.rs`: EventBus (cycle detection, timeouts), `AzlValue` ops/coercions, `MathEngine` integration.
- `src/error.rs`: unified error taxonomy and helpers.
- `src/ffi.rs`: math bridge (`ffi_matmul`, `ffi_eigen_symmetric`, `ffi_complex_mul`).
- `Cargo.toml`: dependencies (`nalgebra`, `tracing`, `tokio`).

#### Notes
- Strict mode is enforced in CI; do not introduce speculative hooks into production paths.
- New runtime features must include docs updates and tests per `docs/TESTING_STRATEGY.md`.

**CURRENT COORDINATION STATUS**: Multiple agents detected working simultaneously (verified by recent file timestamps and duplicate function definitions in src/lib.rs). Agent coordination appears to be ongoing with priority queue implementation being actively developed.

Please avoid modifying these areas without coordination while Phase 1 is in progress. Add tests/docs freely; coordinate runtime/FFI changes via PR comments.

### Standards
- No placeholders or mock paths in production code
- Strict mode must pass before merging
- Typed errors only; no `unwrap()` in runtime paths

### Code Style
- Descriptive names; clear control flow; guard clauses
- Tests and docs required for all changes

### Process
- Small, reviewable PRs
- Update specs/checklists when changing behavior
- Add/adjust tests and docs alongside code


