# Project completion roadmap

This is the **honest** map from **today’s repository** to the **contract goals** in [AZL_NATIVE_RUNTIME_CONTRACT.md](AZL_NATIVE_RUNTIME_CONTRACT.md) and the **spine decision** in [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md). “Finishing the whole project” is **phased**; some layers depend on others.

**Strategic consensus (vision, compression policy, research wedges, phased plan):** [AZL_STRATEGIC_CONSENSUS_AND_EXECUTION_PLAN.md](AZL_STRATEGIC_CONSENSUS_AND_EXECUTION_PLAN.md) — read this **before** starting new initiatives so narrative and execution stay aligned.

**Not the same as “shipping complete”:** when the **native release profile** is done for release purposes, see [PROJECT_COMPLETION_STATEMENT.md](PROJECT_COMPLETION_STATEMENT.md) **Tier A** and `scripts/verify_native_release_profile_complete.sh`. This roadmap is **Tier B** — language/platform depth beyond that bar.

**Actionable queue (IDs, acceptance hints):** [TIER_B_BACKLOG.md](TIER_B_BACKLOG.md).

## Layer 0 — Done / continuously verified

- Native HTTP engine, sysproxy wiring, gates in `scripts/check_azl_native_gates.sh`, `scripts/run_all_tests.sh`.
- C minimal interpreter contract (`tools/azl_interpreter_minimal.c`) for a **narrow** subset; **not** full AZL semantics.
- AZL-in-AZL interpreter source (`azl/runtime/interpreter/azl_interpreter.azl`) + VM slice + docs for `AZL_USE_VM`.
- LSP, azlpack dogfood, grammar / LHA3 verifiers as wired in CI scripts.

## Layer 1 — P0 spine (in progress)

**Target (full P0):** The runtime child must be able to apply **full** language semantics from `azl_interpreter.azl` to the enterprise combined program (AZL-in-AZL self-host or equivalent).

### P0.1 — Long-term execution order (vertical slices)

**Principle:** Prefer increments that unlock a **contiguous** region of **`azl/runtime/interpreter/azl_interpreter.azl`** on the **Python semantic spine** (`tools/azl_semantic_engine/minimal_runtime.py`). Extend **C minimal** only where **`scripts/check_azl_native_gates.sh`** already enforces parity. **Gates F2–F141** (and successors) are **regression anchors**; they do **not** replace **deeper interpreter smokes** that prove the **real file** advances.

| Phase | Intent | Exit criteria (claim “done” only if these hold) | Primary verification |
|-------|--------|---------------------------------------------------|----------------------|
| **A — Parity safety net** | C ↔ Python stay aligned on the **contracted** subset | `bash scripts/check_azl_native_gates.sh` exits **0** (includes **F**, **F2–F141**, **G**, **G2**, **H**, engine build as wired) | Native gates |
| **B — Real interpreter file, shallow** | Stub + real source **`init`** completes on spine | `bash scripts/verify_azl_interpreter_semantic_spine_smoke.sh` exits **0**; marker **`azl-interpreter-semantic-spine-smoke-ok`**; see **ERROR_SYSTEM** **286–290** | **`make verify`** step **3** (`run_full_repo_verification.sh`) |
| **C — Vertical slice: tokenize** | Match **`listen for "tokenize"`** control/data flow (line **`split`**, **`for ::line_text`**, **`::tokens.concat`**, eol **`push`**, **`::line + 1`**, **`return`**, **`.length`**, **`split_chars`** + **`for ::c`**, **`tz|…`**, double-quoted **`say`**, **`emit … with { tokens: ::tokens }`**, …) | **F71**–**F82** with **fixture + F-gate + ERROR_SYSTEM** (see **Layer 1**); optional **extended smoke** or **`verify_*`** proves **more lines** of the real file execute **without silent failure** | Parity gates + smoke / verify script named in PR |
| **D — Vertical slice: parse** | **`listen for "parse"`** — **`::tokens` from **`::event.data.tokens`**, cache **`::cached_ast`** stand-in, **`ast_hits` / `ast_misses`**, **`emit parse_complete with { ast: ::ast }`**, nested **`parse_complete`** listener | **F83**–**F85** landed (**Layer 1**); same pattern for deeper **`parse_tokens`** / map keys when minimal gains them | Parity gates + smoke when extended |
| **E — Vertical slice: execute** | **`listen for "execute"`** — **`::ast` / `::scope`**, **`::ast.nodes`** preloop + **`&&`**, **`emit execute_complete`**, **`AZL_USE_VM`**, **`halt_execution`**, stub **`::vm_compile_ast`** / **`::vm_run_bytecode_program`** when **`AZL_USE_VM=1`**, stub **`::execute_ast`** (**`import|/`link|`** preloop incl. **F112**–**F114** + **F118** + **F120**–**F141** (**`say|`** / **`emit|…|with|…`** / **`component|`** + **`memory|emit|…|with|…`** between **`component|`** + **dual** **`memory|emit|…|with|…`** between **`component|`** + **triple** **`memory|emit|…|with|…`** between **`component|`** + **bare** **`memory|emit|…`** between **`component|`** + **dual** **bare** **`memory|emit|…`** between **`component|`** + **triple** **bare** **`memory|emit|…`** between **`component|`** + **bare** then **`with`** **`memory|emit|…`** between **`component|`** + **`with`** then **bare** **`memory|emit|…`** between **`component|`** + **`with`** + **bare** + **`with`** **`memory|emit|…`** between **`component|`** + **bare** + **`with`** + **bare** **`memory|emit|…`** between **`component|`** + **bare** + **dual** **`with`** + **bare** **`memory|emit|…`** between **`component|`** + **`with`** + **dual** **bare** + **`with`** **`memory|emit|…`** between **`component|`** + **bare** + **`with`** + **bare** + **`with`** **`memory|emit|…`** between **`component|`** + **dual** **`memory|emit|…|with|…`** + **dual** **bare** **`memory|emit|…`** between **`component|`** + **penta** **bare**/**`with`**/**bare**/**`with`**/**bare** **`memory|emit|…`** between **`component|`** + **penta** **`with`**/**bare**/**`with`**/**bare**/**`with`** **`memory|emit|…`** between **`component|`** + **triple** **`component|`** + **`memory|say|…`** interleave + dual **`memory|set|`** + **`memory|listen|…`** stacks + **`emit|…|with`** multi-pair + **`memory|emit|…`** + **`memory|say|…`** between preloop and tail), **`component|`**, **`memory|set|…`** / **`memory|say|…`** / **`memory|emit|…`** / **`memory|emit|…|with|…`** (incl. multi-pair), **`memory|listen|…`** (**F115**–**F119**, incl. stacked **`say`** stubs + **`emit|…|with|…`** one-pair + multi-pair stub tail), **F108**–**F111** mixed ordering, **`listen|…|say|…`**, **`listen|…|emit|…`**, **`listen|…|emit|…|with|…`** multi-pair, **`listen|…|set|…`**, **`say|`**, **`emit|`**, **`emit|…|with|…`**, **`set|`**) when off | **F86**–**F141** landed (**Layer 1**); deeper **`execute_component` / `execute_listen`** / real opcodes when minimal supports them | Parity gates + smoke when extended |
| **F — Self-host / full behavior claim** | **`behavior`** from **`azl_interpreter.azl`** is **actually** driven by **`minimal_runtime`** (or a documented successor) | **Explicit** acceptance checklist (to be tightened when **C–E** narrow); **not** met by **init-only** smoke alone | Process trace + gates + integration |

**Explicit non-goals until the matching roadmap work exists:**

- Flipping **default** **`AZL_RUNTIME_SPINE`** to **`azl_interpreter`** (**Layer 1** item 2 below) before **C–E** materially advance — see **P0.2** in [TIER_B_BACKLOG.md](TIER_B_BACKLOG.md).
- Claiming **Benchmarks Game–style “AZL on the chart”** before there is a **conforming `.azl` workload + stable entry + timed harness** — see [BENCHMARKS_AZL_VS_REAL_WORLD.md](BENCHMARKS_AZL_VS_REAL_WORLD.md).

**Sprint pointer:** Same steps as a short checklist in [TIER_B_BACKLOG.md](TIER_B_BACKLOG.md) § **P0.1 execution checklist**.

**Done (phase 1 — shipped):**

- `AZL_RUNTIME_SPINE=c_minimal` (default): `scripts/azl_c_interpreter_runtime.sh` → `azl-interpreter-minimal` (C).
- `AZL_RUNTIME_SPINE=azl_interpreter` or `semantic`: `scripts/azl_azl_interpreter_runtime.sh` → `tools/azl_runtime_spine_host.py` → **`tools/azl_semantic_engine/`** (`minimal_runtime.py`), a **Python** executor with **execution parity** to the C minimal contract (say / set / emit / link / component init+behavior / quoted `listen for`). **Gate F2** in `check_azl_native_gates.sh` asserts **byte-identical stdout** vs C on `azl/tests/c_minimal_link_ping.azl`.
- **P0.1b (release smoke):** `scripts/verify_azl_interpreter_semantic_spine_smoke.sh` is step **3** of `scripts/run_full_repo_verification.sh` (**`make verify`**): concatenates **`azl/tests/stubs/azl_security_for_interpreter_spine.azl`** + **`azl/runtime/interpreter/azl_interpreter.azl`**, runs the spine host with **`AZL_ENTRY=azl.interpreter`**, asserts **`init`** completes without unresolved **`link ::azl.security`** (**`docs/ERROR_SYSTEM.md`** **286–290**). Does **not** prove **`behavior`** from that file runs on **`minimal_runtime`** yet.
- **Gate F3:** `azl/tests/p0_semantic_interpreter_slice.azl` — C vs Python **byte parity** on interpreter **`init`** prefix including **`.toInt()`** on parenthesized env/or, dotted **`::perf.stats`** / **`::perf.expr_cache`**, `set []` / `{ }`, `link`, `say`; `scripts/run_semantic_interpreter_slice.sh`.
- **Gate F4:** `azl/tests/p0_nested_listen_emit_chain.azl` — nested **`listen`** registered during a listener body, then **`emit`** drains the queue (**`process_events`** from **`exec_block`**) so chained handlers match the **`azl_interpreter.azl`** interpret→downstream pattern; C vs Python **byte parity**.
- **Gate F5:** `azl/tests/p0_semantic_var_alias.azl` — **`set ::mirror = ::seed`** (copy global) + **`say ::mirror`**; C vs Python **byte parity**.
- **Gate F6:** `azl/tests/p0_semantic_expr_plus_chain.azl` — **`+`** in expressions, **`::var + n`**, **`5 == 2 + 3`**; C vs Python **byte parity**.
- **Gate F7:** `azl/tests/p0_semantic_dotted_counter.azl` — dotted global **`::perf.stats.tok_hits`** with **`+`** increments; C vs Python **byte parity**.
- **Gate F8:** `azl/tests/p0_semantic_behavior_interpret_listen.azl` — **`behavior`** + **`listen for "interpret"`** + **`emit interpret`** (no payload); C vs Python **byte parity**.
- **Gate F9:** `azl/tests/p0_semantic_behavior_listen_then.azl` — same as F8 with explicit **`then`** before **`{`**; C vs Python **byte parity**.
- **Gate F10:** `azl/tests/p0_semantic_emit_event_payload.azl` — **`emit … with { key: "value" }`** binds **`::event.data.<key>`** for the listener body; C vs Python **byte parity**.
- **Gate F11:** `azl/tests/p0_semantic_emit_multi_payload.azl` — **`emit … with { a: "…", b: "…" }`** (multi-key payload); C vs Python **byte parity**.
- **Gate F12:** `azl/tests/p0_semantic_emit_queued_payloads.azl` — two **`emit … with`** in one **`init`**, distinct events and payloads; C vs Python **byte parity**.
- **Gate F13:** `azl/tests/p0_semantic_payload_expr_chain.azl` — **`::event.data.*`** on **`set`** RHS with **`+`**; C vs Python **byte parity**.
- **Gate F14:** `azl/tests/p0_semantic_payload_if_branch.azl` — **`if`** condition compares **`::event.data.*`** while payload is active; C vs Python **byte parity**.
- **Gate F15:** `azl/tests/p0_semantic_nested_emit_payload.azl` — nested **`emit`** + inner **`with`**; outer payload keys preserved across inner dispatch when distinct; C vs Python **byte parity**.
- **Gate F16:** `azl/tests/p0_semantic_quoted_emit_with_payload.azl` — quoted **`emit "…" with { … }`**; C vs Python **byte parity**.
- **Gate F17:** `azl/tests/p0_semantic_payload_ne_branch.azl` — **`!=`** on **`::event.data.*`** in **`if`**; C vs Python **byte parity**.
- **Gate F18:** `azl/tests/p0_semantic_payload_or_fallback.azl` — **`or`** fallback when **`::event.data.*`** is unset; C vs Python **byte parity**.
- **Gate F19:** `azl/tests/p0_semantic_emit_empty_with.azl` — **`emit … with { }`**; C vs Python **byte parity**.
- **Gate F20:** `azl/tests/p0_semantic_payload_single_quote.azl` — single-quoted payload values; C vs Python **byte parity**.
- **Gate F21:** `azl/tests/p0_semantic_payload_key_collide.azl` — same payload key **`trace`** on nested **`emit`**; clear semantics after inner; C vs Python **byte parity**.
- **Gate F22:** `azl/tests/p0_semantic_nested_listen_emit_payload.azl` — dynamic **`listen`** inside listener + **`emit … with { … }`**; C vs Python **byte parity**.
- **Gate F23:** `azl/tests/p0_semantic_nested_listen_then_payload.azl` — nested **`listen … then`** + **`emit with`**; C vs Python **byte parity**.
- **Gate F24:** `azl/tests/p0_semantic_payload_numeric_value.azl` — **`with`** payload bare integer; C vs Python **byte parity**.
- **Gate F25:** `azl/tests/p0_semantic_link_in_listener.azl` — **`link`** from listener body; C vs Python **byte parity**.
- **Gate F26:** `azl/tests/p0_semantic_payload_bool_true.azl` — payload value **`true`**; C vs Python **byte parity**.
- **Gate F27:** `azl/tests/p0_semantic_nested_multikey_payload.azl` — nested **`listen`** + inner **`emit … with { a:, b: }`**; C vs Python **byte parity**.
- **Gate F28:** `azl/tests/p0_semantic_payload_bool_false.azl` — payload value **`false`**; C vs Python **byte parity**.
- **Gate F29:** `azl/tests/p0_semantic_payload_null_value.azl` — payload token **`null`** (literal line **`null`**); C vs Python **byte parity**.
- **Gate F30:** `azl/tests/p0_semantic_first_matching_listener.azl` — duplicate **`listen for`** same event, first wins; C vs Python **byte parity**.
- **Gate F31:** `azl/tests/p0_semantic_payload_float_value.azl` — payload **`3.14`**; C vs Python **byte parity**.
- **Gate F32:** `azl/tests/p0_semantic_payload_missing_eq_null.azl` — absent **`::event.data.*`** **`== null`**; C vs Python **byte parity**.
- **Gate F33:** `azl/tests/p0_semantic_payload_big_int.azl` — payload **`65535`**; C vs Python **byte parity**.
- **Gate F34:** `azl/tests/p0_semantic_set_from_payload.azl` — **`set ::… = ::event.data.*`**; C vs Python **byte parity**.
- **Gate F35:** `azl/tests/p0_semantic_payload_present_ne_null.azl` — present field **`!= null`**; C vs Python **byte parity**.
- **Gate F36:** `azl/tests/p0_semantic_payload_quoted_negative.azl` — payload **`"-7"`**; C vs Python **byte parity**.
- **Gate F37:** `azl/tests/p0_semantic_emit_from_listener_chain.azl` — **`emit`** inside listener; nested stdout order; C vs Python **byte parity**.
- **Gate F38:** `azl/tests/p0_semantic_payload_trailing_colon_key.azl` — **`traceid:`** key token; C vs Python **byte parity**.
- **Gate F39:** `azl/tests/p0_semantic_if_true_literal_listener.azl` — **`if (true)`** in listener; C vs Python **byte parity**.
- **Gate F40:** `azl/tests/p0_semantic_if_false_literal_listener.azl` — **`if (false)`** skips branch; C vs Python **byte parity**.
- **Gate F41:** `azl/tests/p0_semantic_listen_in_init_emit.azl` — **`listen`** in **`init`** then **`emit`**; C vs Python **byte parity**.
- **Gate F42:** `azl/tests/p0_semantic_payload_squote_space.azl` — single-quoted payload with space; C vs Python **byte parity**.
- **Gate F43:** `azl/tests/p0_semantic_sequential_payload_events.azl` — two **`emit … with`** distinct events/payloads; C vs Python **byte parity**.
- **Gate F44:** `azl/tests/p0_semantic_if_one_literal_listener.azl` — **`if (1)`**; C vs Python **byte parity**.
- **Gate F45:** `azl/tests/p0_semantic_emit_quoted_event_only.azl` — **`emit "…"`** without **`with`**; C vs Python **byte parity**.
- **Gate F46:** `azl/tests/p0_semantic_say_unset_blank_line.azl` — **`say`** unset **`::event.data.*`** → blank line; C vs Python **byte parity**.
- **Gate F47:** `azl/tests/p0_semantic_if_global_from_payload.azl` — **`set ::flag`** from payload then **`if (::flag)`**; C vs Python **byte parity**.
- **Gate F48:** `azl/tests/p0_semantic_if_zero_literal_listener.azl` — **`if (0)`** skips branch; C vs Python **byte parity**.
- **Gate F49:** `azl/tests/p0_semantic_emit_unquoted_event_only.azl` — **`emit bare`** without **`with`**; C vs Python **byte parity**.
- **Gate F50:** `azl/tests/p0_semantic_say_empty_string_global.azl` — **`say ::empty`** with **`""`**; C vs Python **byte parity**.
- **Gate F51:** `azl/tests/p0_semantic_if_string_false_from_payload.azl` — string **`"false"`** not truthy in **`if (::flag)`**; C vs Python **byte parity**.
- **Gate F52:** `azl/tests/p0_semantic_if_var_true_string.azl` — **`set ::t = "true"`** then **`if (::t)`**; C vs Python **byte parity**.
- **Gate F53:** `azl/tests/p0_semantic_same_event_twice_payload.azl` — same event name twice, different payloads, queue order; C vs Python **byte parity**.
- **Gate F54:** `azl/tests/p0_semantic_listen_in_boot_entry.azl` — **`listen`** + **`emit`** in **`::boot.entry`** **`init`**; C vs Python **byte parity**.
- **Gate F55:** `azl/tests/p0_semantic_if_var_one_string.azl` — **`set ::t = "1"`** then **`if (::t)`**; C vs Python **byte parity**.
- **Gate F56:** `azl/tests/p0_semantic_if_var_zero_string.azl` — string **`"0"`** not truthy in **`if (::t)`**; C vs Python **byte parity**.
- **Gate F57:** `azl/tests/p0_semantic_if_var_empty_string.azl` — empty string not truthy in **`if (::t)`**; C vs Python **byte parity**.
- **Gate F58:** `azl/tests/p0_semantic_cross_component_first_listener.azl` — duplicate event across two components: first **`link`** wins; C vs Python **byte parity**.
- **Gate F59:** `azl/tests/p0_semantic_double_emit_same_event.azl` — two bare **`emit`** same name, listener runs twice; C vs Python **byte parity**.
- **Gate F60:** `azl/tests/p0_semantic_if_or_empty_then_one_string.azl` — **`if (::a or "1")`** with empty **`::a`**; C vs Python **byte parity**.
- **Gate F61:** `azl/tests/p0_semantic_if_global_eq_globals.azl` — **`if (::a == ::b)`** on equal string globals; C vs Python **byte parity**.
- **Gate F62:** `azl/tests/p0_semantic_if_global_ne_globals.azl` — **`if (::a != ::b)`** when globals differ; C vs Python **byte parity**.
- **Gate F63:** `azl/tests/p0_semantic_if_global_ne_equal_skip.azl` — **`if (::a != ::b)`** skipped when equal; C vs Python **byte parity**.
- **Gate F64:** `azl/tests/p0_semantic_set_global_concat_globals.azl` — **`set ::u = ::a + ::b`** string concat; C vs Python **byte parity**.
- **Gate F65:** `azl/tests/p0_semantic_if_literal_eq_strings.azl` — **`if ("x" == "x")`**; C vs Python **byte parity**.
- **Gate F66:** `azl/tests/p0_semantic_if_literal_ne_strings.azl` — **`if ("a" != "b")`**; C vs Python **byte parity**.
- **Gate F67:** `azl/tests/p0_semantic_set_triple_concat_mixed.azl` — **`set ::out = "pre" + ::mid + "post"`**; C vs Python **byte parity**.
- **Gate F68:** `azl/tests/p0_semantic_return_in_listener_if.azl` — **`return`** inside **`if`** in **`listen`** body; C vs Python **byte parity**; exits **291–293**.
- **Gate F69:** `azl/tests/p0_semantic_for_split_line_loop.azl` — **`::blob.split("delim")`** + **`for ::line in ::lines`** in listener; C vs Python **byte parity**; exits **294–296**.
- **Gate F70:** `azl/tests/p0_semantic_dot_length_global.azl` — **`::var.length`** in **`if`** (unset → **`0`**); C vs Python **byte parity**; exits **297–299**.
- **Gate F71:** `azl/tests/p0_semantic_split_chars_for.azl` — **`set ::chars = ::line.split_chars()`** + **`for ::c in ::chars`** (UTF-8 scalar units; C mirrors Python); C vs Python **byte parity**; exits **311–313**.
- **Gate F72:** `azl/tests/p0_semantic_push_string_listener.azl` — **`set ::buf.push("…")`** appends newline-delimited segments (same encoding as **`split`** / **`for ::row in`**); C vs Python **byte parity**; exits **314–316**.
- **Gate F73:** `azl/tests/p0_semantic_int_sub_column_length.azl` — **`set ::start = ::column - ::current.length`** (binary **`-`**, both operands canonical integers); C vs Python **byte parity**; exits **317–319**.
- **Gate F74:** `azl/tests/p0_semantic_tokenize_in_string_char.azl` — **`in_string`** / quote toggle + **`::handled`** over **`split_chars`**; C vs Python **byte parity**; exits **323–325**.
- **Gate F75:** `azl/tests/p0_semantic_tokens_push_tz_concat.azl` — **`tz|…`** object **`.push`** + **`::acc.concat`**, **`::var`** in object fields; C vs Python **byte parity**; exits **326–328**.
- **Gate F76:** `azl/tests/p0_semantic_tokenize_line_inc_concat.azl` — **`::line + 1`**, **`::current + ::c`**; C vs Python **byte parity**; exits **329–331**.
- **Gate F77:** `azl/tests/p0_semantic_tokenize_outer_line_loop.azl` — outer **`tokenize`** loop: **`::code.split("\\n")`**, **`for ::line_text`**, **`concat`** + eol **`push`**, **`::line + 1`**; C vs Python **byte parity**; exits **332–334**.
- **Gate F78:** `azl/tests/p0_semantic_say_double_interpolate.azl` — double-quoted **`say`** expands **`::dotted.path`** and **`::path.length`** (single-quoted literal); C vs Python **byte parity**; exits **335–337**.
- **Gate F79:** `azl/tests/p0_semantic_emit_payload_var_bind.azl` — **`emit … with { key: ::var }`** resolves **`::var`** at **`emit`** time (e.g. **`tokenize_complete`** **`tokens`**); C vs Python **byte parity**; exits **338–340**.
- **Gate F80:** `azl/tests/p0_semantic_tokenize_cache_miss_branch.azl` — **`if (::cached_tok != null) { … return }`** miss path + **`::perf.stats.tok_misses + 1`** (minimal uses **`::`** cache slot stand-in); C vs Python **byte parity**; exits **341–343**.
- **Gate F81:** `azl/tests/p0_semantic_tokenize_cache_hit_branch.azl` — cache **hit** path: **`tok_hits + 1`**, **`set ::tokens = ::cached_tok`**, markers + **`return`** (init seeds **`::cached_tok`**); C vs Python **byte parity**; exits **344–346**.
- **Gate F82:** `azl/tests/p0_semantic_tokenize_cache_hit_emit_complete.azl` — same hit path as **F81**, then **`emit tokenize_complete with { tokens: ::tokens }`**; **`listen for "tokenize_complete"`** registered **before** the starter event (matches **`azl_interpreter.azl`** ~**46–82** ordering); C vs Python **byte parity**; exits **347–349**.
- **Gate F83:** `azl/tests/p0_semantic_parse_cache_miss_branch.azl` — **`set ::tokens = ::event.data.tokens`**, miss path + **`::perf.stats.ast_misses + 1`** (**`::cached_ast`** stand-in); exits **350–352**.
- **Gate F84:** `azl/tests/p0_semantic_parse_cache_hit_branch.azl` — parse cache hit: **`ast_hits + 1`**, **`set ::ast = ::cached_ast`**, **`return`**; exits **353–355**.
- **Gate F85:** `azl/tests/p0_semantic_parse_cache_hit_emit_complete.azl` — hit path + **`emit parse_complete with { ast: ::ast }`** + inner **`parse_complete`** listener; exits **356–358**.
- **Gate F86:** `azl/tests/p0_semantic_execute_payload_emit_complete.azl` — **`::event.data.ast` / `::scope`**, stub **`::result`**, **`emit execute_complete with { result: ::result }`** + inner listener; exits **359–361**.
- **Gate F87:** `azl/tests/p0_semantic_execute_use_vm_env_off.azl` — **`((::internal.env("AZL_USE_VM") or "") == "1")`** with **`AZL_USE_VM` unset** in **`check_azl_native_gates.sh`**; exits **362–364**.
- **Gate F88:** `azl/tests/p0_semantic_halt_execution_listener.azl` — **`emit halt_execution with { … }`** from a listener, **`listen for "halt_execution"`** with **`set ::halted = true`**; exits **365–367**.
- **Gate F89:** `azl/tests/p0_semantic_execute_ast_nodes_preloop.azl` — **`if (::ast != null && ::ast.nodes != null)`**, **`for ::n in ::ast.nodes`**, then **`emit execute_complete`**; exits **368–370**.
- **Gates F90–F92:** **`AZL_USE_VM=1`** in **`check_azl_native_gates.sh`** — **`set … = ::vm_compile_ast(::ast)`** (**`::vc.ok`**, **`::vc.error`**, **`::vc.bytecode`**; magic tags **`F90_VM_OK`** / **`F91_VM_BAD`** / **`F92_VM_EMPTY`**) + **`::vm_run_bytecode_program(::vc.bytecode)`** (**`p0_semantic_execute_vm_path_ok.azl`**, **`p0_semantic_execute_vm_compile_error.azl`**, **`p0_semantic_execute_vm_empty_bytecode.azl`**); exits **371–379**, **P0execvm** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F93:** **`p0_semantic_execute_ast_tree_walk.azl`** — **`AZL_USE_VM` unset**, **`set ::result = ::execute_ast(::ast, ::scope)`** walks **`::ast.nodes`** **`say|…`** steps; exits **380–382**, **P0exectree** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F94:** **`p0_semantic_execute_ast_emit_step.azl`** — **`execute_ast`** **`emit|…`** bare emit + listener drain; exits **383–385**, **P0exectreeemit** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F95:** **`p0_semantic_execute_ast_set_step.azl`** — **`execute_ast`** **`set|::global|value`**; exits **386–388**, **P0exectreeset** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F96:** **`p0_semantic_execute_ast_emit_with_step.azl`** — **`execute_ast`** **`emit|ev|with|key|value`** (one payload field); exits **389–391**, **P0exectreewith** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F97:** **`p0_semantic_execute_ast_emit_multi_with_step.azl`** — **`execute_ast`** **`emit|ev|with|k1|v1|k2|v2`**; exits **392–394**, **P0exectreewithmulti** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F98:** **`p0_semantic_execute_ast_import_link_preloop.azl`** — **`execute_ast`** **`import|/`link|`** preloop (stub + **`link`** side-effect); exits **395–397**, **P0execpreil** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F99:** **`p0_semantic_execute_ast_component_listen_step.azl`** — **`execute_ast`** **`component|`** + **`listen|ev|say|payload`** stub dispatch; exits **398–400**, **P0exectreecomplisten** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F100:** **`p0_semantic_execute_ast_listen_emit_stub.azl`** — **`execute_ast`** **`listen|ev|emit|inner`** stub (queues inner bare event, nested dispatch); exits **401–403**, **P0exectreelistenemit** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F101:** **`p0_semantic_execute_ast_listen_set_stub.azl`** — **`execute_ast`** **`listen|ev|set|::global|value`** stub (**`var_set`** on dispatch); exits **404–406**, **P0exectreelistenset** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F102:** **`p0_semantic_execute_ast_listen_emit_with_stub.azl`** — **`execute_ast`** **`listen|ev|emit|inner|with|k|v`** stub (payload on inner **`emit`**); exits **407–409**, **P0exectreelistenemitwith** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F103:** **`p0_semantic_execute_ast_listen_emit_multi_with_stub.azl`** — **`execute_ast`** **`listen|ev|emit|inner|with|k1|v1|k2|v2`** stub (F97-shaped multi-pair tail); exits **410–412**, **P0exectreelistenemitwithmulti** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F104:** **`p0_semantic_execute_ast_memory_set_step.azl`** — **`execute_ast`** **`memory|set|::global|value`** (stub **`execute_component`** memory row) + **`say|…`** in same walk; exits **413–415**, **P0exectreememory** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F105:** **`p0_semantic_execute_ast_memory_emit_step.azl`** — **`execute_ast`** **`memory|emit|…`** (bare emit + drain, F94-shaped); exits **416–418**, **P0exectreememoryemit** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F106:** **`p0_semantic_execute_ast_memory_emit_with_step.azl`** — **`execute_ast`** **`memory|emit|inner|with|k|v`** (F96-shaped payload); exits **419–421**, **P0exectreememoryemitwith** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F107:** **`p0_semantic_execute_ast_memory_emit_multi_with_step.azl`** — **`execute_ast`** **`memory|emit|inner|with|k1|v1|k2|v2`** (F97-shaped); exits **422–424**, **P0exectreememoryemitwithmulti** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F108:** **`p0_semantic_execute_ast_memory_multi_row_order.azl`** — consecutive **`memory|say|…`** + trailing **`say|`** preserve source order; exits **425–427**, **P0exectreememorymultirow** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F109:** **`p0_semantic_execute_ast_memory_mixed_order.azl`** — **`memory|set|…`**, **`memory|emit|…`**, **`memory|say|…`** in one walk (order + global survives); exits **428–430**, **P0exectreememorymixed** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F110:** **`p0_semantic_execute_ast_memory_mixed_emit_with_order.azl`** — **`memory|set|…`**, **`memory|emit|…|with|k|v`**, **`memory|say|…`**; exits **431–433**, **P0exectreememorymixedemitwith** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F111:** **`p0_semantic_execute_ast_memory_mixed_emit_multi_with_order.azl`** — **`memory|set|…`**, multi-pair **`memory|emit|…|with|…`**, **`memory|say|…`**; exits **434–436**, **P0exectreememorymixedemitwithmulti** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F112:** **`p0_semantic_execute_ast_preloop_then_memory_say.azl`** — **`import|/`link|`** preloop then **`memory|say|…`**; exits **437–439**, **P0execpreilmemory** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F113:** **`p0_semantic_execute_ast_preloop_say_then_memory_say.azl`** — same preloop as **F112**, then top-level **`say|`** then **`memory|say|…`**; exits **440–442**, **P0execpreilsaymemory** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F114:** **`p0_semantic_execute_ast_preloop_emit_then_memory_say.azl`** — same preloop as **F112**, then top-level **`emit|…|with|…`** then **`memory|say|…`**; exits **443–445**, **P0execpreilemitmemory** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F115:** **`p0_semantic_execute_ast_memory_listen_emit_say.azl`** — **`memory|listen|…`** stub + **`memory|emit|…`** drain + **`memory|say|…`**; exits **446–448**, **P0exectreememorylisten** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F116:** **`p0_semantic_execute_ast_memory_listen_emit_with_say.azl`** — **`memory|listen|…|emit|…|with|…`** stub + **`memory|emit|…`** + **`memory|say|…`** (inner event + payload); exits **449–451**, **P0exectreememorylistenemitwith** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F117:** **`p0_semantic_execute_ast_memory_listen_emit_multi_with_say.azl`** — **`memory|listen|…|emit|…|with|k1|v1|k2|v2`** stub + **`memory|emit|…`** + **`memory|say|…`**; exits **452–454**, **P0exectreememorylistenemitwithmulti** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F118:** **`p0_semantic_execute_ast_preloop_memory_listen_emit_multi_with_say.azl`** — preloop **`import|/`link|`** then **F117**-shaped memory listen multi-**`|with|`** chain; exits **455–457**, **P0execpreilmemorylistenemitwithmulti** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F119:** **`p0_semantic_execute_ast_memory_listen_stack_say.azl`** — two stacked **`memory|listen|…|say|…`** stubs, dual **`memory|emit|…`**, trailing **`memory|say|…`**; exits **458–460**, **P0exectreememorylistenstack** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F120:** **`p0_semantic_execute_ast_preloop_memory_listen_stack_say.azl`** — preloop **`import|/`link|`** then **F119**-shaped stacked memory listens + dual emits + **`memory|say|…`**; exits **461–463**, **P0execpreilmemorylistenstack** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F121:** **`p0_semantic_execute_ast_preloop_say_then_memory_listen_stack_say.azl`** — preloop then **`say|`** then **F119** stack; exits **464–466**, **P0execpreilsaymemorylistenstack** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F122:** **`p0_semantic_execute_ast_preloop_emit_then_memory_listen_stack_say.azl`** — preloop then **`emit|…|with|…`** then **F119** stack; exits **467–469**, **P0execpreilemitmemorylistenstack** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F123:** **`p0_semantic_execute_ast_preloop_component_memory_set_listen_stack.azl`** — preloop then **`component|`** + dual **`memory|set|…`** + **F119**-shaped memory listen stack; exits **470–472**, **P0execpreilcomponentmemorysetlistenstack** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F124:** **`p0_semantic_execute_ast_preloop_two_component_memory_say.azl`** — preloop then **`component|`** + **`memory|say|…`** + **`component|`** + **`memory|say|…`**; exits **473–475**, **P0execpreiltwocomponentmemorysay** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F125:** **`p0_semantic_execute_ast_preloop_three_component_memory_say.azl`** — preloop then **three** **`component|`** rows with **`memory|say|…`** between; exits **476–478**, **P0execpreilthreecomponentmemorysay** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F126:** **`p0_semantic_execute_ast_preloop_component_memory_emit_component_say.azl`** — preloop then **`component|`** + **`memory|emit|…|with|…`** + **`component|`** + **`memory|say|…`**; exits **479–481**, **P0execpreilcomponentmemoryemitcomponentsay** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F127:** **`p0_semantic_execute_ast_preloop_component_memory_dual_emit_component_say.azl`** — preloop then **`component|`** + **two** **`memory|emit|…|with|…`** + **`component|`** + **`memory|say|…`**; exits **482–484**, **P0execpreilcomponentmemorydualemitcomponentsay** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F128:** **`p0_semantic_execute_ast_preloop_component_memory_triple_emit_component_say.azl`** — preloop then **`component|`** + **three** **`memory|emit|…|with|…`** + **`component|`** + **`memory|say|…`**; exits **485–487**, **P0execpreilcomponentmemorytripleemitcomponentsay** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F129:** **`p0_semantic_execute_ast_preloop_component_memory_bare_emit_component_say.azl`** — preloop then **`component|`** + **bare** **`memory|emit|…`** + **`component|`** + **`memory|say|…`**; exits **488–490**, **P0execpreilcomponentmemorybareemitcomponentsay** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F130:** **`p0_semantic_execute_ast_preloop_component_memory_dual_bare_emit_component_say.azl`** — preloop then **`component|`** + **two** bare **`memory|emit|…`** + **`component|`** + **`memory|say|…`**; exits **491–493**, **P0execpreilcomponentmemorydualbareemitcomponentsay** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F131:** **`p0_semantic_execute_ast_preloop_component_memory_triple_bare_emit_component_say.azl`** — preloop then **`component|`** + **three** bare **`memory|emit|…`** + **`component|`** + **`memory|say|…`**; exits **494–496**, **P0execpreilcomponentmemorytriplebareemitcomponentsay** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F132:** **`p0_semantic_execute_ast_preloop_component_memory_mixed_bare_with_emit_component_say.azl`** — preloop then **`component|`** + **bare** **`memory|emit|…`** + **`memory|emit|…|with|…`** + **`component|`** + **`memory|say|…`**; exits **497–499**, **P0execpreilcomponentmemorymixedbarewithemitcomponentsay** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F133:** **`p0_semantic_execute_ast_preloop_component_memory_mixed_with_bare_emit_component_say.azl`** — preloop then **`component|`** + **`memory|emit|…|with|…`** + **bare** **`memory|emit|…`** + **`component|`** + **`memory|say|…`**; exits **500–502**, **P0execpreilcomponentmemorymixedwithbareemitcomponentsay** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F134:** **`p0_semantic_execute_ast_preloop_component_memory_triple_mixed_emit_component_say.azl`** — preloop then **`component|`** + **`memory|emit|…|with|…`** + **bare** **`memory|emit|…`** + **`memory|emit|…|with|…`** + **`component|`** + **`memory|say|…`**; exits **503–505**, **P0execpreilcomponentmemorytriplemixedemitcomponentsay** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F135:** **`p0_semantic_execute_ast_preloop_component_memory_triple_mixed_bare_with_bare_emit_component_say.azl`** — preloop then **`component|`** + **bare** **`memory|emit|…`** + **`memory|emit|…|with|…`** + **bare** **`memory|emit|…`** + **`component|`** + **`memory|say|…`**; exits **506–508**, **P0execpreilcomponentmemorytriplemixedbarewithbareemitcomponentsay** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F136:** **`p0_semantic_execute_ast_preloop_component_memory_quad_mixed_bare_with_with_bare_emit_component_say.azl`** — preloop then **`component|`** + **bare** + **two** **`memory|emit|…|with|…`** + **bare** **`memory|emit|…`** + **`component|`** + **`memory|say|…`**; exits **509–511**, **P0execpreilcomponentmemoryquadmixedbarewithwithbareemitcomponentsay** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F137:** **`p0_semantic_execute_ast_preloop_component_memory_quad_mixed_with_bare_bare_with_emit_component_say.azl`** — preloop then **`component|`** + **`memory|emit|…|with|…`** + **two** bare **`memory|emit|…`** + **`memory|emit|…|with|…`** + **`component|`** + **`memory|say|…`**; exits **512–514**, **P0execpreilcomponentmemoryquadmixedwithbarebarewithemitcomponentsay** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F138:** **`p0_semantic_execute_ast_preloop_component_memory_quad_mixed_bare_with_bare_with_emit_component_say.azl`** — preloop then **`component|`** + **bare** **`memory|emit|…`** + **`memory|emit|…|with|…`** + **bare** **`memory|emit|…`** + **`memory|emit|…|with|…`** + **`component|`** + **`memory|say|…`**; exits **515–517**, **P0execpreilcomponentmemoryquadmixedbarewithbarewithemitcomponentsay** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F139:** **`p0_semantic_execute_ast_preloop_component_memory_quad_mixed_with_with_bare_bare_emit_component_say.azl`** — preloop then **`component|`** + **two** **`memory|emit|…|with|…`** + **two** bare **`memory|emit|…`** + **`component|`** + **`memory|say|…`**; exits **518–520**, **P0execpreilcomponentmemoryquadmixedwithwithbarebareemitcomponentsay** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F140:** **`p0_semantic_execute_ast_preloop_component_memory_penta_mixed_bare_with_bare_with_bare_emit_component_say.azl`** — preloop then **`component|`** + **five** **`memory|emit|…`** rows (**bare** / **`with`** / **bare** / **`with`** / **bare**) + **`component|`** + **`memory|say|…`**; exits **521–523**, **P0execpreilcomponentmemorypentamixedbarewithbarewithbareemitcomponentsay** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Gate F141:** **`p0_semantic_execute_ast_preloop_component_memory_penta_mixed_with_bare_with_bare_with_emit_component_say.azl`** — preloop then **`component|`** + **five** **`memory|emit|…`** rows (**`with`** / **bare** / **`with`** / **bare** / **`with`**) + **`component|`** + **`memory|say|…`**; exits **524–526**, **P0execpreilcomponentmemorypentamixedwithbarewithbarewithemitcomponentsay** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**.
- **Open next (documented):** richer **`execute_ast`** vs **`execute_component` / `execute_listen`** — **F142+**; **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)** “Open next”.
- **Gate H:** `scripts/verify_p0_interpreter_tokenizer_boundary.sh` — tokenizer on interpreter prefix, **`component ::azl.interpreter` anchor**, and **`{` / `}` token balance** on the full file (structural milestone; not execution).

**Still open (full P0):**

1. Widen the semantic engine until it can **load and run** `azl/runtime/interpreter/azl_interpreter.azl` as source (or introduce a verified compile path to the same semantics).
2. Only then flip **default** `AZL_RUNTIME_SPINE` to `azl_interpreter` if product wants the Python (or future native) semantic child as canonical over C minimal.
3. Keep [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md) and [AZL_NATIVE_RUNTIME_CONTRACT.md](AZL_NATIVE_RUNTIME_CONTRACT.md) aligned with each change.

## Layer 2 — P1 HTTP / API parity

Depends on **which stack** answers requests (C-only vs AZL `http_server.azl`). Do after spine choice is unambiguous for the canonical profile.

**Shipped (instrumentation + docs, not “one true server”):**

- **C native engine:** `GET /api/llm/capabilities`, `POST /api/ollama/generate` → Ollama; `scripts/run_native_engine_llm_bench.sh` + `scripts/benchmark_llm_ollama.sh` (bench skips non-proxy ports so enterprise :8080 is not mistaken for the C proxy).
- **Enterprise combined daemon:** `azl/system/http_server.azl` exposes **`POST /v1/chat`** (Bearer); `scripts/benchmark_enterprise_v1_chat.sh` for latency when the daemon is up.

**Still open:** pick or document the **canonical** HTTP profile per deployment (C-only supervisor vs full AZL HTTP server) and align default startup scripts and audits so product expectations match the process trace.

## Layer 3 — P2 process capability policy

`proc.exec` / `proc.spawn` under explicit AZL policy — see contract.

## Layer 4 — P3 VM breadth

Widen `AZL_USE_VM` slice **after** tree-walking interpreter is canonical on the spine.

## Layer 5 — P4 packages

Resolution, publishing — see [AZLPACK_SPEC.md](AZLPACK_SPEC.md).

## Layer 6 — P5 native GGUF

Explicitly **deferred** unless product requires in-process weights; capabilities endpoint must stay honest.

---

## Next actions (do in order)

Completed queue rows and verification commands: **[AZL_DOCUMENTATION_CANON.md](AZL_DOCUMENTATION_CANON.md)** §1.6–§5. **Automation:** `bash scripts/run_full_repo_verification.sh` (see [RELEASE_READY.md](../RELEASE_READY.md)).

Summary:

1. **Product benchmarks** — Run via full verification (optional) or `run_product_benchmark_suite.sh`.
2. **P0** — Gate **H** shipped (tokenizer + brace balance). **Open:** execute full `azl_interpreter.azl` on semantic spine (large effort).
3. **Canonical HTTP** — **[CANONICAL_HTTP_PROFILE.md](CANONICAL_HTTP_PROFILE.md)**.
4. **GGUF / GPU** — Deferred; honesty verified in native live check.

---

**Rule of thumb:** If a milestone claims “full AZL semantics on the enterprise path,” the **process trace** must show the **AZL interpreter** executing user/combined code, not only the C minimal binary. Until then, documentation and env flags must **not** imply parity.
