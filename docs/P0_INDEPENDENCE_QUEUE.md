# P0 independence queue — 100-item backlog

**Purpose:** Ordered checklist toward **semantic independence** (spec in `azl/runtime/interpreter/azl_interpreter.azl`, spine proof, C↔Python parity where gated). Derived from maintainer strategy; **not** a substitute for [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md) or [TIER_B_BACKLOG.md](TIER_B_BACKLOG.md).

**How to use:** Work top-to-bottom; check `[x]` when done. Link PRs/commits in parentheses if useful.

---

## A. Spine truth and policy (1–12)

- [ ] 1. Treat RUNTIME_SPINE_DECISION.md as authority for default vs semantic launcher traces.
- [ ] 2. Keep Gate G (`verify_runtime_spine_contract.sh`) passing after resolver/launcher edits.
- [ ] 3. Keep Gate G2 passing (semantic launcher → Python `minimal_runtime`).
- [ ] 4. Do not flip default `AZL_RUNTIME_SPINE` until P0.2 + product sign-off.
- [ ] 5. When P0.2 happens, update resolver + contract + ops docs in one PR.
- [ ] 6. Keep P0.1b green (`verify_azl_interpreter_semantic_spine_smoke.sh`).
- [ ] 7. Keep P0.1c green (`verify_azl_interpreter_semantic_spine_behavior_smoke.sh`).
- [ ] 8. Extend P0.1c only with tight stdout + ERROR_SYSTEM updates.
- [ ] 9. Document which `azl_interpreter.azl` lines each P0.1c extension covers.
- [ ] 10. New spine failures typed; no silent success (ERROR_SYSTEM-shaped where applicable).
- [ ] 11. Keep `make verify` steps 3–4 authoritative for interpreter-file release claims.
- [ ] 12. Refresh roadmap/TIER_B F-gate ranges when the suite moves (e.g. F172+).

## B. C↔Python parity gates (13–35)

- [ ] 13. Run `bash scripts/check_azl_native_gates.sh` before merge when touching minimal C/Python.
- [x] 14. **F172** — `::parse_tokens` `listen { set … ; emit … with { k: v } }` — fixture + gate + ERROR_SYSTEM + AGENTS. (shipped with this file)
- [ ] 15. **F173** — same with multi-pair `with { a: b, c: d }` after `set`.
- [ ] 16. **F174** — `listen { say … ; set … ; emit … }` three-statement order.
- [ ] 17. **F175** — `listen { emit … ; set … }` reverse order regression.
- [ ] 18. **F176** — `listen { if (true) { say … } }` in parse_tokens inner (if supported).
- [ ] 19. **F177** — early `return` in inner listen parse (aligned with F68).
- [ ] 20. **F178** — `memory` + `listen` interaction in same `parse_tokens` walk (if spec requires).
- [ ] 21. **F179** — quoted vs bare inner `emit` in multi-line listen body.
- [ ] 22. **F180** — inner `emit with` payload `::var` resolution in listen body.
- [ ] 23. Audit Var.v / row buffers after new listen shapes; extend with gates not silent truncation.
- [ ] 24. Keep `build_azl_interpreter_minimal.sh` strict defaults; document CI toolchain overrides.
- [ ] 25. Mirror new F blocks: C → Python → byte diff in `check_azl_native_gates.sh`.
- [ ] 26. Reserve non-colliding ERROR_SYSTEM exits before adding gates.
- [ ] 27. No Python-only features without C parity or explicit documented non-parity.
- [ ] 28. Re-check F9-class ordering if emit/listener drain semantics change.
- [ ] 29. Keep F2 (`c_minimal_link_ping`) on resolver changes.
- [ ] 30. Keep F87 / F90–F92 VM env contract stable on execute-path edits.
- [ ] 31. Extend F93–F148 only with new `execute_ast` node kinds + three exits each.
- [ ] 32. Refresh Gate H if `azl_interpreter.azl` tokenizer/balance expectations shift.
- [ ] 33. Default F-gate success = byte-identical stdout unless documented exception.
- [ ] 34. CI clean build + native gates + minimal Werror path stays green.
- [ ] 35. Retire F gates in one PR (ERROR_SYSTEM + script), no zombie exits.

## C. Real file: `azl_interpreter.azl` depth (36–58)

- [ ] 36. Map full `listen for "interpret"` body to harness coverage; close gaps vs P0.1c.
- [ ] 37. Map `listen for "tokenize"` to extended smoke or F-fixtures from real lines.
- [ ] 38. Map `listen for "parse"` the same way.
- [ ] 39. Map `listen for "execute"` (VM branch, halt, `execute_ast`) the same way.
- [ ] 40. Map nested `tokenize_complete` / `parse_complete` / `execute_complete` registration order.
- [ ] 41. Map `halt_execution` beyond stub gate.
- [ ] 42. Diff in-file `parse_tokens` usage vs F149–F172; add gates for gaps.
- [ ] 43. Diff in-file `execute_ast` vs F93–F148 stubs; prioritize hot node kinds.
- [ ] 44. Implement/stub only what the next interpreter slice needs.
- [ ] 45. Track minimal aggregate `{}` vs real map semantics divergence.
- [ ] 46. Align `fn` / `=>` if interpret path requires (full P0 open item).
- [ ] 47. Defer syscall/file.read listeners until core pipeline stable.
- [ ] 48. UTF-8/emoji `say` in real file: run on spine or document exclusion.
- [ ] 49. Integration/smoke for `interpretation_complete` when I/O path in scope.
- [ ] 50. Trace `emit interpret` → downstream event order vs minimal queue.
- [ ] 51. Align perf.stats counters in real file vs smokes.
- [ ] 52. Converge parse cache key story (`cached_ast` vs stand-ins).
- [ ] 53. Converge token cache key story (`cached_tok` vs stand-ins).
- [ ] 54. Harness for multi-file/combined-path edges if enterprise requires.
- [ ] 55. Keep `::azl.security` stub compatible with interpreter `link`.
- [ ] 56. Extend P0.1b only when `init` completion claim changes.
- [ ] 57. Record known non-covered interpreter regions in TIER_B or reality audit.
- [ ] 58. Re-audit AZL_ENGINEERING_REALITY_AUDIT.md per milestone.

## D. `minimal_runtime.py` quality (59–68)

- [ ] 59. SemanticEngineError codes match C exits for same constructs.
- [ ] 60. No catch-all silent success on partial execution.
- [ ] 61. DRY listen/emit/parse only when second callsite is gate-proven.
- [ ] 62. Optional script-level assertions for edge cases too heavy for full gate suite.
- [ ] 63. Stable import surface for spine host (G2 contract).
- [ ] 64. Document env vars read by minimal in spine/contract docs.
- [ ] 65. Profile hot loops only after slice gates are green.
- [ ] 66. No host shell from combined `.azl` unless designed and gated.
- [ ] 67. Pin/document Python version for CI.
- [ ] 68. Negative tests for new builtins (arity/type) with defined errors.

## E. C minimal discipline (69–76)

- [ ] 69. Match Python for every new F gate before merge.
- [ ] 70. Bounded buffers; shared fmt helpers for new format paths.
- [ ] 71. No new snprintf truncation hazards without bound strategy.
- [ ] 72. Listener nesting + `process_events` order aligned with F4/F37.
- [ ] 73. Keep `for-in` contract (listener-only unless extended with gates).
- [ ] 74. Document intentional C subset divergence in RUNTIME_SPINE_DECISION if unavoidable.
- [ ] 75. CI builds minimal with repo strict flags.
- [ ] 76. UB suspicion → loud failures in debug where policy allows.

## F. Phase F acceptance (77–88)

- [ ] 77. Documented trace: `AZL_RUNTIME_SPINE=azl_interpreter` → host → minimal_runtime → interpreter file.
- [ ] 78. G2 still passes after Phase F-class work (unless policy change).
- [ ] 79. Interpreter `behavior` runs without silent failure for claimed subset.
- [ ] 80. Failures ERROR_SYSTEM-shaped where contract promises.
- [ ] 81. TIER_B semantics row updated (proven vs partial).
- [ ] 82. F suite covers every claimed construct used on spine path.
- [ ] 83. Extended smoke or `verify_*` beyond P0.1c line coverage (backlog table).
- [ ] 84. No “full self-host” marketing until Phase F checklist satisfied.
- [ ] 85. CLI/entry paragraph accurate (AZL_NATIVE_RUNTIME_CONTRACT or RELEASE_READY).
- [ ] 86. Literal “Exact” claims tied to verify scripts.
- [ ] 87. LHA3 language aligned with LHA3_COMPRESSION_HONESTY.md.
- [ ] 88. RepertoireField: spec + 3–5 tests (reality audit) if still a pillar.

## G. Adjacent layers (89–100)

- [ ] 89. P1 — Canonical HTTP profile per deployment.
- [ ] 90. P1 — C routes vs `http_server.azl` audit table.
- [ ] 91. P2 — `proc.exec` / `proc.spawn` capability policy + tests + exits.
- [ ] 92. P3 — Widen VM after tree-walk semantics stable on spine.
- [ ] 93. P4 — azlpack per AZLPACK_SPEC when blocking.
- [ ] 94. P5 — GGUF deferred; capabilities honest.
- [ ] 95. Benchmarks on claimed paths (BENCHMARKS_AZL_VS_REAL_WORLD.md).
- [ ] 96. Security labels honest (no production crypto without audit).
- [ ] 97. INTEGRATION_VERIFY / `make verify` current when adding steps.
- [ ] 98. Gate 0 release helpers stay bash-clean and policy-aligned.
- [ ] 99. AGENTS.md + continuity docs stay onboarding truth.
- [ ] 100. Periodic `RUN_OPTIONAL_BENCHES=0 make verify` before major releases.

---

**Last updated:** 2026-03-23 (queue created; F172 landed).
