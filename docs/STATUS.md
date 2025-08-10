# AZL Project Status

This document reflects the current, verified state of the pure-AZL runtime and ecosystem.

## Verified (working now)
- Runtime: `azl/runtime/interpreter/azl_interpreter.azl`
  - Components with init/behavior/memory
  - say/set/emit; emit payloads via `emit name with payload`
  - Listener registry; recursion/cycle guard
  - Expression evaluator for common operations
- Virtual OS: `azl/system/azl_system_interface.azl`
  - Unified `syscall` listener; in-memory FS/HTTP/console/proc
  - Deterministic behavior; metadata for files (size/modified)
- Stdlib: `azl/stdlib/core/azl_stdlib.azl`
  - Arrays/strings/objects/math/time
  - Deterministic RNG (`random_seed`, LCG) and monotonic time ticks
  - File/network helpers backed by virtual OS stores

## Deprecated / design-only
- Native compiler and bytecode/VM documents (removed or marked as design)
- Rust runtime references are historical and not required for core execution

## Open work (next increments)
- Test harness: increase coverage using AZL tests under `azl/testing/`
- Documentation: expand Virtual OS API usage patterns; module system guide

## Quality gates
- No `placeholder|TODO|FIXME` in `.azl`
- Virtual OS paths validated by smoke tests
- Event recursion/cycle guards enabled by default


