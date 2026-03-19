# AZL Native Runtime Contract

This document defines the hard direction for AZL as an independent language runtime.

## Objective

AZL must converge to a standalone language stack for end users:

- `AZL source -> AZL compiler -> AZL bytecode/native IR -> AZL VM/runtime`
- no required Python or JavaScript runtime for user execution paths
- no dependency on external language hosts for canonical behavior

## Native Mode Switch

`AZL_NATIVE_ONLY=1` enables strict transition behavior:

- blocks Python 24h daemon startup via `scripts/start_azme_24h_daemon.sh`
- blocks Python runner path via `scripts/azl run`
- intended startup path becomes `scripts/start_azl_native_mode.sh`
- legacy JavaScript runtime path is blocked unless `AZL_ENABLE_LEGACY_HOST=1`
- native startup requires `AZL_NATIVE_EXEC_CMD` (explicit native executor command)
- native executor requires `AZL_NATIVE_RUNTIME_CMD` for entry runtime process
- repository provides a native executor binary build path via `scripts/build_azl_native_engine.sh`
- repository includes canonical native runtime loop command: `scripts/azl_native_runtime_loop.sh`

## Current Reality (Canonical Native Stage)

The canonical execution path is native-first and enforced by release gates:

- Native startup: `scripts/start_azl_native_mode.sh`
- Native engine: `tools/azl_native_engine.c`
- Native runtime loop: `scripts/azl_native_runtime_loop.sh`
- Legacy Node harness exists only as blocked bootstrap path under native-only mode.

## Non-Negotiable Completion Gates

1. AZL VM instruction semantics fully define runtime behavior.
2. Core language control flow (`if`, `for`, `while`) behaves correctly in canonical AZL execution.
3. Event emission semantics preserve target and payload in all contexts (init + behavior + function paths).
4. Command/process capability model is enforced by AZL policy, not host-language trust.
5. Canonical API server path is AZL-native (`azl/system/http_server.azl`) with consistent auth and endpoint behavior.
6. Release mode can run user AZL programs without Python/Node execution dependencies.

## Immediate Engineering Priorities

1. Continue AZL VM and compiler contract hardening for canonical runtime behavior.
2. Harden `proc.exec` / `proc.spawn` with explicit AZL capability policy.
3. Unify runtime API behavior between AZL server and current bootstrap harness.
4. Expand integration tests that assert AZL-native behavior and reject host-only shortcuts.

## Usage

Start transition-native mode:

```bash
# Optional: provide your own native engine command
# export AZL_NATIVE_EXEC_CMD=/path/to/azl-native-engine
# Optional: provide your own runtime command launched by native engine
# export AZL_NATIVE_RUNTIME_CMD="bash scripts/azl_native_runtime_loop.sh"
bash scripts/start_azl_native_mode.sh
```

Attempting to start blocked bootstrap paths under `AZL_NATIVE_ONLY=1` should fail explicitly.

Run canonical gate checks:

```bash
bash scripts/check_azl_native_gates.sh
```
