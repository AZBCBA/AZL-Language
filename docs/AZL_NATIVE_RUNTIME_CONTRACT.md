# AZL Native Runtime Contract

This document defines the hard direction for AZL as an independent language runtime.

**Spine decision (current vs target, P0–P5):** [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md) — read this first so you do not confuse **today’s default runtime child** (C minimal on the combined file) with the **decided semantic core** (AZL interpreter).

## Objective

AZL must converge to a standalone language stack for end users:

- `AZL source -> AZL compiler -> AZL bytecode/native IR -> AZL VM/runtime`
- no required Python or JavaScript runtime for user execution paths
- no dependency on external language hosts for canonical behavior

## Bytecode VM hot path (optional)

`AZL_USE_VM=1` is passed through the native shell/bootstrap like any other env var (the C native engine does not strip it). When set, **`::azl.interpreter`**’s `execute` handler **attempts** to compile the parsed AST into a small linear program (`SAY`, `EMIT`) and runs it via `vm_run_bytecode_program`, which reuses **`emit_event_resolved`** so **listener dispatch matches the tree-walking executor**.

**Supported for VM compilation**

- Top-level `say` / `emit`
- `component` bodies whose **`init`** contains only `say` / `emit`, and whose **`behavior`** is empty or contains no statements (any `listen` or non-listen behavior statement is rejected with `vm_compile_error:…`)

**Not supported**

- `set` / `let`, `listen`, `fn`, calls, control flow in the compiled slice — use `AZL_USE_VM=0` (default) for full semantics.

**Files**

- Interpreter gate + opcode runner: `azl/runtime/interpreter/azl_interpreter.azl` (`vm_compile_ast`, `vm_run_bytecode_program`)
- Reference VM (separate opcode surface): `azl/runtime/vm/azl_vm.azl`

### Default enterprise runtime vs pure AZL interpreter

Canonical **native enterprise** startup (`scripts/start_azl_native_mode.sh` → `run_enterprise_daemon.sh`) sets `AZL_NATIVE_RUNTIME_CMD` when unset using **`scripts/azl_resolve_native_runtime_cmd.sh`**, which reads **`AZL_RUNTIME_SPINE`**:

| `AZL_RUNTIME_SPINE` | Default `AZL_NATIVE_RUNTIME_CMD` | Semantic owner |
|---------------------|----------------------------------|----------------|
| unset or `c_minimal` | `bash scripts/azl_c_interpreter_runtime.sh` | **C minimal** (`tools/azl_interpreter_minimal.c`) on the combined bundle |
| `azl_interpreter` or `semantic` | `bash scripts/azl_azl_interpreter_runtime.sh` | **`tools/azl_runtime_spine_host.py`** → **`tools/azl_semantic_engine/`** — Python executor with **subset parity** to C minimal (not yet `azl_interpreter.azl` self-host) |

The **C minimal** path **does not** load or execute `azl/runtime/interpreter/azl_interpreter.azl`, so it **never consults** `AZL_USE_VM`.

The **semantic** path runs the **Python minimal-parity** engine on `AZL_COMBINED_PATH` (same contract surface as C minimal). **Full** AZL-in-AZL semantics via `azl_interpreter.azl` remain a **widening** track (see **`docs/PROJECT_COMPLETION_ROADMAP.md`**). Operators can set **`AZL_NATIVE_RUNTIME_CMD`** explicitly to override both defaults.

`AZL_USE_VM` matters when execution reaches **`::azl.interpreter`**’s **`execute`** handler (pure-AZL bootstrap, self-hosted paths, tests, or any future runtime that runs the AZL interpreter instead of the C skeleton).

**Observable parity (when the AZL interpreter runs):** VM and tree-walker both use `evaluate_expression` for `say` operands and call **`emit_event_resolved`** for `emit`, so `say` lines are prefixed with `💬 ` and emits log `📡 Emitting event: …` before listener dispatch.

### Example (eligible snippet)

See `azl/tests/fixtures/vm_parity_minimal.azl`: root-level `say` / `emit`, one component with **`init`** containing only `say` / `emit` and an **empty** `behavior` block.

### Verification

- `scripts/test_azl_use_vm_path.sh` — static wiring (`verify_azl_use_vm_path.sh`), source parity (`scripts/check_azl_vm_tree_parity.py`), fixture lint (no `listen` / `set` / `if` / `fn` in the eligible fixture).
- `scripts/run_all_tests.sh` invokes the above.

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

### Native LLM surface (honesty, not inference)

- **`GET /api/llm/capabilities`** (public, no bearer): JSON describing what the engine can do — today `ollama_http_proxy: true` for `POST /api/ollama/generate`, and `gguf_in_process: false` with `ERR_NATIVE_GGUF_NOT_IMPLEMENTED` until in-process weights exist. See `docs/LLM_INFRASTRUCTURE_AUDIT.md`.

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
