# AZL project status

Short, **verified** snapshot of the pure-AZL path. For strategy and gaps, see [AZL_PERFECTION_PLAN.md](AZL_PERFECTION_PLAN.md). For quantum/memory honesty, see [DEEP_AUDIT_QUANTUM_MEMORY_PHYSICS.md](DEEP_AUDIT_QUANTUM_MEMORY_PHYSICS.md).

## Verified (working now)

- **Interpreter:** `azl/runtime/interpreter/azl_interpreter.azl` — components, init/behavior, say/set/emit, listener registry, recursion/cycle guard, common expressions.
- **Virtual OS:** `azl/system/azl_system_interface.azl` — `syscall` listener; in-memory fs/http/console/proc; deterministic behavior.
- **Stdlib:** `azl/stdlib/core/azl_stdlib.azl` — core types, math, time, deterministic RNG hooks, helpers backed by the virtual OS.
- **Native profile:** C HTTP engine `tools/azl_native_engine.c`, sysproxy, shell orchestration — gated by `scripts/check_azl_native_gates.sh`, `verify_native_runtime_live.sh`, and `run_all_tests.sh`.
- **Compiler / VM (AZL):** bytecode pipeline exists under `azl/core/compiler/` and `azl/runtime/vm/`. Optional **`AZL_USE_VM=1`**: `::azl.interpreter` can compile a **restricted** AST slice to linear ops and run `vm_run_bytecode_program` (see `docs/AZL_NATIVE_RUNTIME_CONTRACT.md`). Default remains full tree execution.

## Deprecated / historical

- **Rust runtime at repo root:** not used for core execution; ignore old docs that reference `cargo`, `src/lib.rs`, or a Rust lexer/parser as the live runtime.

## Open work (high level)

- Raise automated **test coverage** (AZL tests under `azl/testing/`).
- **Wire VM/bytecode** as an optional or default execution path (`AZL_USE_VM` or equivalent), documented in [AZL_NATIVE_RUNTIME_CONTRACT.md](AZL_NATIVE_RUNTIME_CONTRACT.md).
- **Package ecosystem:** `.azlpack` spec in [AZLPACK_SPEC.md](AZLPACK_SPEC.md); publish and dogfood installs.
- **LSP:** beyond skeleton — diagnostics, go-to-def, CI smoke ([AZL_LSP_SETUP.md](AZL_LSP_SETUP.md)).

## Quality gates

- No `placeholder|TODO|FIXME` in `.azl` / `.rs` (see `scripts/check_no_placeholders.sh`).
- Native gates + grammar / LHA3 verifiers as run by `scripts/run_all_tests.sh`.
- Pre-release sequence: [RELEASE_READY.md](../RELEASE_READY.md).
