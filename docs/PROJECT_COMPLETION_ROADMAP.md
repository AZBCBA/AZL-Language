# Project completion roadmap

This is the **honest** map from **today’s repository** to the **contract goals** in [AZL_NATIVE_RUNTIME_CONTRACT.md](AZL_NATIVE_RUNTIME_CONTRACT.md) and the **spine decision** in [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md). “Finishing the whole project” is **phased**; some layers depend on others.

## Layer 0 — Done / continuously verified

- Native HTTP engine, sysproxy wiring, gates in `scripts/check_azl_native_gates.sh`, `scripts/run_all_tests.sh`.
- C minimal interpreter contract (`tools/azl_interpreter_minimal.c`) for a **narrow** subset; **not** full AZL semantics.
- AZL-in-AZL interpreter source (`azl/runtime/interpreter/azl_interpreter.azl`) + VM slice + docs for `AZL_USE_VM`.
- LSP, azlpack dogfood, grammar / LHA3 verifiers as wired in CI scripts.

## Layer 1 — P0 spine (in progress)

**Target (full P0):** The runtime child must be able to apply **full** language semantics from `azl_interpreter.azl` to the enterprise combined program (AZL-in-AZL self-host or equivalent).

**Done (phase 1 — shipped):**

- `AZL_RUNTIME_SPINE=c_minimal` (default): `scripts/azl_c_interpreter_runtime.sh` → `azl-interpreter-minimal` (C).
- `AZL_RUNTIME_SPINE=azl_interpreter` or `semantic`: `scripts/azl_azl_interpreter_runtime.sh` → `tools/azl_runtime_spine_host.py` → **`tools/azl_semantic_engine/`** (`minimal_runtime.py`), a **Python** executor with **execution parity** to the C minimal contract (say / set / emit / link / component init+behavior / quoted `listen for`). **Gate F2** in `check_azl_native_gates.sh` asserts **byte-identical stdout** vs C on `azl/tests/c_minimal_link_ping.azl`.

**Still open (full P0):**

1. Widen the semantic engine until it can **load and run** `azl/runtime/interpreter/azl_interpreter.azl` as source (or introduce a verified compile path to the same semantics).
2. Only then flip **default** `AZL_RUNTIME_SPINE` to `azl_interpreter` if product wants the Python (or future native) semantic child as canonical over C minimal.
3. Keep [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md) and [AZL_NATIVE_RUNTIME_CONTRACT.md](AZL_NATIVE_RUNTIME_CONTRACT.md) aligned with each change.

## Layer 2 — P1 HTTP / API parity

Depends on **which stack** answers requests (C-only vs AZL `http_server.azl`). Do after spine choice is unambiguous for the canonical profile.

## Layer 3 — P2 process capability policy

`proc.exec` / `proc.spawn` under explicit AZL policy — see contract.

## Layer 4 — P3 VM breadth

Widen `AZL_USE_VM` slice **after** tree-walking interpreter is canonical on the spine.

## Layer 5 — P4 packages

Resolution, publishing — see [AZLPACK_SPEC.md](AZLPACK_SPEC.md).

## Layer 6 — P5 native GGUF

Explicitly **deferred** unless product requires in-process weights; capabilities endpoint must stay honest.

---

**Rule of thumb:** If a milestone claims “full AZL semantics on the enterprise path,” the **process trace** must show the **AZL interpreter** executing user/combined code, not only the C minimal binary. Until then, documentation and env flags must **not** imply parity.
