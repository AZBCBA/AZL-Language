# P0 independence queue — 100-item backlog

**Purpose:** Ordered checklist toward **semantic independence** (spec in `azl/runtime/interpreter/azl_interpreter.azl`, spine proof, C↔Python parity where gated). See [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md) and [TIER_B_BACKLOG.md](TIER_B_BACKLOG.md).

**Reality:** This list mixes **one-shot deliverables**, **ongoing maintainer habits**, and **multi-quarter roadmap** (Phase F, P1–P5, RepertoireField). **Not all 100 rows can be “done” in a single change set** — some stay open until product policy or major interpreter work lands. When a row is an **ongoing obligation**, we treat it as satisfied for the queue when the repo’s **current** verify scripts are green and the rule is documented (see **Baseline** below).

**Baseline (re-verify after major spine/minimal changes):**  
`bash scripts/check_azl_native_gates.sh` → 0; `bash scripts/verify_azl_interpreter_semantic_spine_smoke.sh` → 0; `bash scripts/verify_azl_interpreter_semantic_spine_behavior_smoke.sh` → 0; optional full `RUN_OPTIONAL_BENCHES=0 make verify`.

**Gate numbering gap:** **F176–F178** are **reserved** in the doc plan for inner **`if`**, **`return`**, and **`memory`+`listen`** token walks — not yet implemented as gates (requires **`parse_listen_inner_body`** / parse loop extensions).

---

## A. Spine truth and policy (1–12)

- [x] 1. Treat RUNTIME_SPINE_DECISION.md as authority for default vs semantic launcher traces.
- [x] 2. Keep Gate G (`verify_runtime_spine_contract.sh`) passing — **baseline** (native gates include G).
- [x] 3. Keep Gate G2 passing — **baseline** (native gates include G2).
- [ ] 4. Do not flip default `AZL_RUNTIME_SPINE` until P0.2 + product sign-off — **policy** (intentionally open until decided).
- [ ] 5. When P0.2 happens, update resolver + contract + ops docs in one PR — **blocked on 4**.
- [x] 6. Keep P0.1b green — **baseline** (`verify_azl_interpreter_semantic_spine_smoke.sh`).
- [x] 7. Keep P0.1c green — **baseline** (`verify_azl_interpreter_semantic_spine_behavior_smoke.sh`).
- [x] 8. Extend P0.1c only with tight stdout + ERROR_SYSTEM updates — **process** (documented in AGENTS / ERROR_SYSTEM).
- [ ] 9. Document which `azl_interpreter.azl` lines each P0.1c extension covers — **open** (incremental doc per extension).
- [x] 10. New spine failures typed — **process** (ERROR_SYSTEM + scripts; no silent success in gates).
- [x] 11. Keep `make verify` steps 3–4 authoritative — **wired** in `run_full_repo_verification.sh`.
- [x] 12. Refresh roadmap/TIER_B F-gate ranges when the suite moves — **done** through **F180** (2026-03-24).

## B. C↔Python parity gates (13–35)

- [x] 13. Run `bash scripts/check_azl_native_gates.sh` before merge when touching minimal C/Python — **maintainer habit**; enforced by CI/strength bar.
- [x] 14. **F172** — `listen { set … ; emit … with { k: v } }` — shipped.
- [x] 15. **F173** — set + **`emit … with { a: b, c: d }`** — shipped (**768–770**).
- [x] 16. **F174** — **`say` + `set` + `emit`** — shipped (**771–773**).
- [x] 17. **F175** — **`emit` then `set`** — shipped (**774–776**).
- [ ] 18. **F176** — inner **`if (true) { say … }`** in `parse_tokens` — **open** (parser extension).
- [ ] 19. **F177** — inner **`return`** in listen parse — **open** (parser extension).
- [ ] 20. **F178** — **`memory` + `listen`** same walk — **open** (fixture + parser if needed).
- [x] 21. **F179** — quoted inner **`emit`** in multi-line listen — shipped (**777–779**).
- [x] 22. **F180** — inner **`with`** value **`::…`** token text in ast row — shipped (**780–782**).
- [x] 23. Var/row buffers audited for F173–F180 shapes — **no cap increase required** (same as F171/F172).
- [x] 24. `build_azl_interpreter_minimal.sh` strict defaults — shipped earlier; **override** via **`AZL_MINIMAL_CFLAGS`**.
- [x] 25. New F blocks mirror C → Python → diff — **pattern used** for F173–F180.
- [x] 26. New exits **768–782** reserved in ERROR_SYSTEM — no collision with **633–752** spine-behavior band.
- [x] 27. No Python-only parity drift for F173–F180 — C/Python byte match.
- [x] 28. F9-class ordering — **unchanged** this batch (regress if emit/drain edits).
- [x] 29. F2 on resolver changes — **gate present** in suite.
- [x] 30. F87 / F90–F92 — **unchanged** this batch.
- [ ] 31. Extend F93–F148 only with new node kinds — **open** (next execute_ast slices).
- [x] 32. Gate H — **runs** in native gates; refresh counts if interpreter file shifts.
- [x] 33. Byte-identical stdout — **F173–F180** match.
- [x] 34. CI clean build + Werror minimal — **default** `AZL_MINIMAL_CFLAGS` on `build_azl_interpreter_minimal.sh`.
- [ ] 35. Retire F gates in one PR when deprecating — **N/A** (none retired).

## C. Real file: `azl_interpreter.azl` depth (36–58)

- [ ] 36–58. **Open** — mapping, extended smokes, syscall path, perf/cache convergence, and audits are **incremental program work**, not closed by this batch. Track in [TIER_B_BACKLOG.md](TIER_B_BACKLOG.md) § P0.1.

## D. `minimal_runtime.py` quality (59–68)

- [x] 59–63. **Baseline** — existing gates + G2 import contract; extend with new builtins only under F gates.
- [x] 64. Env vars — **documented** in RUNTIME_SPINE_DECISION.md (minimal contract subsection).
- [ ] 65–68. **Ongoing** — profile, security, Python pin, negative tests as features land.

## E. C minimal discipline (69–76)

- [x] 69–75. **Baseline** — F173–F180 prove match; bounded fmt helpers prior art; strict build script.
- [ ] 76. UB loud failures — **open** (debug-build policy if adopted).

## F. Phase F acceptance (77–88)

- [ ] 77–88. **Not met** — full **behavior** / self-host / marketing discipline is **Phase F**; see TIER_B **Phase F acceptance**. G2 and spec owner lines pass today; **79–83** remain future work.

## G. Adjacent layers (89–100)

- [ ] 89–94. **P1–P5** — HTTP canonical profile, route audit, proc capabilities, VM breadth, azlpack, GGUF honesty: **roadmap**, not completed here.
- [ ] 95. Benchmarks on claimed paths — **open** (run when claiming perf).
- [x] 96. Security labels — **prior** DEMO_NON_CRYPTO / honesty contracts in tree.
- [x] 97. INTEGRATION_VERIFY — **wired** (`make verify`); update when adding verify steps.
- [x] 98. Gate 0 release helpers — **part of** `check_azl_native_gates.sh`.
- [x] 99. AGENTS.md + continuity — **maintained** this batch.
- [ ] 100. Periodic full `make verify` — **maintainer cadence** (run before releases).

---

## RepertoireField (queue item 88 detail)

- [ ] 88. Spec + 3–5 tests per [AZL_ENGINEERING_REALITY_AUDIT.md](AZL_ENGINEERING_REALITY_AUDIT.md) — **open** (research/product track).

**Last updated:** 2026-03-24 (F173–F180 + doc baseline; honesty pass on “cannot close in one PR” items).
