# Runtime spine decision (source of truth)

**Purpose:** One place to read **how native execution is supposed to work** and **what is true today**. Contributors should use this doc instead of inferring architecture only from shell defaults.

**Last updated:** 2026-03-20

---

## Is P0 (spine wiring) already done?

**No — not for the default canonical path.**

If you run:

```bash
bash scripts/start_azl_native_mode.sh
```

the trace today is: **`start_azl_native_mode.sh`** → **`run_enterprise_daemon.sh`** → native engine **`tools/azl_native_engine.c`** forks **`AZL_NATIVE_RUNTIME_CMD`**, which defaults to **`bash scripts/azl_c_interpreter_runtime.sh`** → **`azl-interpreter-minimal`** reads **`AZL_COMBINED_PATH`** and executes a **small C subset** of AZL on the combined bundle.

**`azl/runtime/interpreter/azl_interpreter.azl` is not invoked on that path.** Full AZL semantics (parser, `execute`, `AZL_USE_VM`, etc.) live in that file, but the enterprise hot path does not enter it today.

**P0a (C minimal correctness, 2026-03-19):** `link` and entry `run()` must scope `behavior` / `init` discovery to a single component body. A bug used `find_block_end(j)` where `j` pointed at the opening `{`; `find_block_end` expects the first token *inside* the block (`j+1`), which wrongly extended the body and could match the *next* component’s `init`, causing infinite `link` → `exec_init` recursion and SIGSEGV. **Fixed** in `tools/azl_interpreter_minimal.c`; regression coverage: `azl/tests/c_minimal_link_ping.azl` and **`scripts/check_azl_native_gates.sh`** gate **F**. This does **not** complete P0 (default path still uses C minimal as semantic engine).

**P0b (spine selector + semantic executor phase 1, 2026-03-19):** `AZL_RUNTIME_SPINE` chooses the default `AZL_NATIVE_RUNTIME_CMD` when it is unset — **`scripts/azl_resolve_native_runtime_cmd.sh`**. Values **`c_minimal`** (default) or unset → `scripts/azl_c_interpreter_runtime.sh`; **`azl_interpreter`** or **`semantic`** → `scripts/azl_azl_interpreter_runtime.sh` → **`tools/azl_runtime_spine_host.py`** → **`tools/azl_semantic_engine/minimal_runtime.py`** (Python, **parity** with `tools/azl_interpreter_minimal.c` on the supported subset). Native gate **F2** diffs stdout vs C on `azl/tests/c_minimal_link_ping.azl`; **`scripts/verify_runtime_spine_contract.sh`** (gate **G**) covers resolver + host env errors + same fixture success. **Full P0** (run `azl_interpreter.azl` as AZL source) remains open — see **`docs/PROJECT_COMPLETION_ROADMAP.md`**.

**P0c (interpreter-shaped slice, 2026-03-20):** Fixture **`azl/tests/p0_semantic_interpreter_slice.azl`** mirrors a larger prefix of **`::azl.interpreter` `init`**: empty **`::azl.security`** stub; **`set`** with **`[]` / `{…}`** balanced aggregates (keyed object literals are consumed as one **`{…}`** region and stored as the string **`{}`** in the minimal contract); **`set ::halt_on_error = ((::internal.env("AZL_STRICT") or "1") == "1")`** via **`==` / `!=` / `or` / `(` `)` / `null`** and **`::internal.env("…")`** (real environment, empty string if unset); **`if EXPR { … }`**; **`link ::azl.security`**; boot **`say`** lines + **`P0_SEMANTIC_INTERPRETER_SLICE_OK`**. Tokenizer emits **`==`** and **`!=`** as single tokens. Expression errors: C exits **5**; Python **`SemanticEngineError(5)`** (handled in **`run_file`**). Native gate **F3** asserts **byte-identical stdout** C vs Python. Smoke: **`bash scripts/run_semantic_interpreter_slice.sh`**. Still omitted from the slice until the minimal contract grows: **`.toInt()`**, dotted **`set`**, full **`::perf.stats`**, etc.

**Partial / adjacent (not P0 complete):**

- **`AZL_NATIVE_RUNTIME_CMD`** is intentionally pluggable; an operator can point it at a custom launcher without changing the C engine.
- **`scripts/azl_bootstrap.sh`** + **`scripts/azl_seed_runner.sh`** can run a **bootstrap bundle** that embeds interpreter sources and `::boot.entry` — a **different** shape than “combined enterprise file + default C minimal”.

**P0 is complete when:** the **same** canonical command (or an explicitly documented primary profile) traces execution into the **AZL interpreter** as the component that applies **full language semantics** to the combined program, with the C engine limited to **HTTP / process / FIFO / env** as below. Verification is by **tracing the process** and/or a **small integration test** that fails if the C minimal is still the semantic owner.

---

## Decision: target architecture (spine)

| Layer | Role |
|--------|------|
| **C native engine** (`tools/azl_native_engine.c`) | HTTP API, child process lifecycle, `AZL_COMBINED_PATH` / `AZL_ENTRY` / token env, health/status. **Not** the long-term owner of full AZL language semantics. |
| **AZL interpreter** (`azl/runtime/interpreter/azl_interpreter.azl` + its wired dependencies) | **Semantic core:** parse, execute, events, components, and (optionally) `AZL_USE_VM` bytecode path for eligible slices. |
| **C minimal interpreter** (`tools/azl_interpreter_minimal.c`) | **Bootstrap, tests, constrained mode, or temporary fallback** — not the specification of “what AZL means” at scale. |

This is **Option B** in planning terms: **C orchestrates; AZL interprets.**

---

## Current state vs target state (explicit)

**CURRENT STATE (today)**

```text
$ bash scripts/start_azl_native_mode.sh
  → enterprise daemon builds / uses combined .azl
  → C native engine starts runtime child from AZL_NATIVE_RUNTIME_CMD
  → default: azl-interpreter-minimal loads AZL_COMBINED_PATH
  → AZL interpreter sources are on disk (and often inside the bundle) but are not the executed semantic engine on this default path
```

**TARGET STATE (decided)**

```text
$ bash scripts/start_azl_native_mode.sh   # (or one clearly named primary profile)
  → C native engine loads combined bundle path + entry (unchanged orchestration role)
  → runtime child runs a launcher that executes the AZL interpreter as semantic core on that program
  → azl/runtime/interpreter/azl_interpreter.azl (wired stack) owns full semantics
  → C minimal remains available for narrow/bootstrap use, not default enterprise semantics
```

**P0 accomplishment:** For the **canonical** profile, the two diagrams above describe the **same** execution spine (modulo intentional fallbacks documented in this file).

---

## Obligations P0–P5 (concrete pointers)

These map to **`docs/AZL_NATIVE_RUNTIME_CONTRACT.md`** (“Non-Negotiable Completion Gates”) and repo reality. Order matters: **P0 before P1** until the spine is true; otherwise HTTP parity work compares the wrong execution stack.

### P0 — Spine wiring (prerequisite)

| Item | Pointers |
|------|-----------|
| Default (or single documented-primary) runtime runs AZL interpreter on combined file | `scripts/start_azl_native_mode.sh`, `scripts/run_enterprise_daemon.sh`, `scripts/start_enterprise_daemon.sh` |
| Engine passes bundle + entry into child | `tools/azl_native_engine.c` (`start_runtime_pipeline`, `AZL_COMBINED_PATH`, `AZL_ENTRY`, `AZL_NATIVE_RUNTIME_CMD`) |
| Interpreter stack entry + failure behavior | `azl/runtime/interpreter/azl_interpreter.azl`, `azl/bootstrap/azl_pure_launcher.azl`, `azl/host/exec_bridge.azl` (as wired today) |
| Contract text stays aligned | `docs/AZL_NATIVE_RUNTIME_CONTRACT.md` (§ default enterprise runtime vs pure AZL interpreter) |

### P1 — HTTP / API parity

| Item | Pointers |
|------|-----------|
| Align C engine routes with AZL server contract | `tools/azl_native_engine.c`, `azl/system/http_server.azl` |
| Auth, errors, and stable JSON shapes | Same; `docs/AZL_NATIVE_RUNTIME_CONTRACT.md`, `docs/API_REFERENCE.md` where used |

### P2 — Process capability policy

| Item | Pointers |
|------|-----------|
| `proc.exec` / `proc.spawn` under explicit capability policy | `azl/system/azl_system_interface.azl`, syscall / virtual OS paths; contract § “proc.exec / proc.spawn” |

### P3 — VM breadth (`AZL_USE_VM`)

| Item | Pointers |
|------|-----------|
| Widen compiled slice **after** tree-walking interpreter is canonical on spine | `azl/runtime/interpreter/azl_interpreter.azl` (`vm_compile_ast`, `vm_run_bytecode_program`), `azl/runtime/vm/azl_vm.azl` |
| Tests | `scripts/test_azl_use_vm_path.sh`, `azl/tests/fixtures/vm_parity_minimal.azl` |

### P4 — Package ecosystem

| Item | Pointers |
|------|-----------|
| Spec + local dogfood | `docs/AZLPACK_SPEC.md`, `scripts/build_azlpack.sh`, `scripts/azl_install.sh`, `packages/src/azl-hello/` |
| Gaps | Dependency resolution, publishing — not done |

### P5 — Native GGUF / in-process LLM

**Deferred** unless product explicitly requires “no external inference daemon.” Until then, honest surface stays as documented.

| Item | Pointers |
|------|-----------|
| Capabilities + proxy | `tools/azl_native_engine.c` (`GET /api/llm/capabilities`, `POST /api/ollama/generate`), `docs/LLM_INFRASTRUCTURE_AUDIT.md` |
| AZL error surface | `azl/neural/model_loader.azl` (`load_gguf_native`) |

---

## Quantum (one line)

**Quantum memory is part of the core language and product story** (components, events, APIs users rely on). **Physical qubits are not claimed** where the implementation is symbolic or deterministic math; see **`docs/DEEP_AUDIT_QUANTUM_MEMORY_PHYSICS.md`** for file-level honesty. Tightening **semantics + tests for guaranteed behavior** is core work; “looks quantum” without contracts is not.

---

## Related docs

| Document | Role |
|----------|------|
| [AZL_NATIVE_RUNTIME_CONTRACT.md](AZL_NATIVE_RUNTIME_CONTRACT.md) | Legal-style runtime + completion gates |
| [AZL_PERFECTION_PLAN.md](AZL_PERFECTION_PLAN.md) | Broader strategic phases (still valid; this doc narrows **spine**) |
| [STATUS.md](STATUS.md) | Short verified snapshot |
| [DEEP_AUDIT_QUANTUM_MEMORY_PHYSICS.md](DEEP_AUDIT_QUANTUM_MEMORY_PHYSICS.md) | Quantum / memory: real vs symbolic |
| [PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md) | Phased “whole project” work vs contract (P0–P5) |

---

## Changing this decision

Any PR that **changes the default native execution spine** must update **this file** and **`docs/AZL_NATIVE_RUNTIME_CONTRACT.md`** in the same change set, and add or adjust a **gate test** if the repo enforces the spine in CI.
