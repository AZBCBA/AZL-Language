# Runtime spine decision (source of truth)

**Purpose:** One place to read **how native execution is supposed to work** and **what is true today**. Contributors should use this doc instead of inferring architecture only from shell defaults.

**Last updated:** 2026-03-22

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

**P0b (spine selector + semantic executor phase 1, 2026-03-19):** `AZL_RUNTIME_SPINE` chooses the default `AZL_NATIVE_RUNTIME_CMD` when it is unset — **`scripts/azl_resolve_native_runtime_cmd.sh`**. Values **`c_minimal`** (default) or unset → `scripts/azl_c_interpreter_runtime.sh`; **`azl_interpreter`** or **`semantic`** → `scripts/azl_azl_interpreter_runtime.sh` → **`tools/azl_runtime_spine_host.py`** → **`tools/azl_semantic_engine/minimal_runtime.py`** (Python, **parity** with `tools/azl_interpreter_minimal.c` on the supported subset). Native gate **F2** diffs stdout vs C on `azl/tests/c_minimal_link_ping.azl`; **`scripts/verify_runtime_spine_contract.sh`** (gate **G**) covers resolver + host env errors + same fixture success. **P0.1a (2026-03-20):** gate **G2** — **`scripts/verify_semantic_spine_owner_contract.sh`** asserts the semantic launcher still **`exec python3`** the spine host and that **`--semantic-owner`** reports **`AZL_SEMANTIC_OWNER=minimal_runtime_python`**. **P0.1b (2026-03-21):** **`scripts/verify_azl_interpreter_semantic_spine_smoke.sh`** (step **3** of **`run_full_repo_verification.sh`**) runs the **real** **`azl/runtime/interpreter/azl_interpreter.azl`** through the Python spine host with a harness-only **`::azl.security`** stub (**`azl/tests/stubs/azl_security_for_interpreter_spine.azl`**) so **`init`** completes without **`link`** failure; **not** full **`behavior`** execution yet (**`docs/ERROR_SYSTEM.md`** exits **286–290**). **Full P0** (run `azl_interpreter.azl` as AZL source) remains open — see **`docs/PROJECT_COMPLETION_ROADMAP.md`**.

**P0c (interpreter-shaped slice, 2026-03-20):** Fixture **`azl/tests/p0_semantic_interpreter_slice.azl`** mirrors a larger prefix of **`::azl.interpreter` `init`**: empty **`::azl.security`** stub; **`set`** with **`[]` / `{…}`** balanced aggregates (keyed object literals are consumed as one **`{…}`** region and stored as the string **`{}`** in the minimal contract); **`set ::halt_on_error = ((::internal.env("AZL_STRICT") or "1") == "1")`** via **`==` / `!=` / `or` / `(` `)` / `null`** and **`::internal.env("…")`** (real environment, empty string if unset); **`if EXPR { … }`**; **`link ::azl.security`**; boot **`say`** lines + **`P0_SEMANTIC_INTERPRETER_SLICE_OK`**. Tokenizer emits **`==`** and **`!=`** as single tokens. Expression errors: C exits **5**; Python **`SemanticEngineError(5)`** (handled in **`run_file`**). Native gate **F3** asserts **byte-identical stdout** C vs Python. Smoke: **`bash scripts/run_semantic_interpreter_slice.sh`**.

**P0d (`.toInt()` + dotted `set` for perf, 2026-03-20):** Minimal C + Python evaluators accept **`.toInt()`** immediately after a parenthesized expression, e.g. **`((::internal.env("AZL_PARSE_CACHE") or "512").toInt())`** — string parsed as base-10 integer, invalid/empty → **`0`**. Fixture **F3** now includes **`set ::perf = { … cap: (.toInt()) }`**, **`set ::perf.stats = { … }`**, **`set ::perf.expr_cache = {}`** aligned with **`azl_interpreter.azl`** init order (still stores whole **`{…}`** RHS as **`{}`** for aggregate literals). Duplicate **`set ::dispatch_stack` / `::recursion_depth`** lines removed from **`azl_interpreter.azl`**. **Still open for full P0:** behavior/`=>` functions, tokenizer/parser execution, **`AZL_USE_VM`** breadth — see roadmap.

**P0e (nested `listen` + emit flush in listener bodies, 2026-03-20):** **`exec_listen`** in **`tools/azl_interpreter_minimal.c`** and **`tools/azl_semantic_engine/minimal_runtime.py`** registers **`listen for "…" [then] { … }`** while executing **`init`** or an active listener body. **`emit`** inside **`exec_block`** now calls **`process_events()`** after enqueue so chained handlers run before the outer listener continues (same pattern as **`azl_interpreter.azl`** registering **`tokenize_complete`** / **`parse_complete`** before **`emit tokenize`**). Native gate **F4**: **`azl/tests/p0_nested_listen_emit_chain.azl`**, C ↔ Python stdout byte match.

**P0f (var alias via `set ::dst = ::src`, 2026-03-20):** Fixture **`azl/tests/p0_semantic_var_alias.azl`** — **`set ::mirror = ::seed`** after string init; **`say ::mirror`**; marker **`P0_SEMANTIC_VAR_ALIAS_OK`**. Native gate **F5**: C minimal vs Python spine host **byte-identical stdout**. **Literal codec (parallel):** **`tools/azl_literal_codec/`** implements **AZL0** v1 **identity** encode/decode + CRC-32C; **`scripts/verify_azl_literal_codec_roundtrip.sh`** in **`run_tests.sh`**.

**P0g (`+` expressions + zlib container, 2026-03-20):** Token **`+`** in C + Python minimal tokenizers; **`eval_sum`** / additive chain before **`==` / `!=`** (int add if both canonical base-10 else string concat). Fixture **`azl/tests/p0_semantic_expr_plus_chain.azl`**, gate **F6**. **Literal:** **`codec_id=1`** **zlib** (`encode_zlib_v1` / decode), **`CODEC_DECOMPRESS_FAILED`** (**exit 271**); round-trip harness covers zlib + CRC-correct invalid stream.

**P0h (dotted global keys, 2026-03-20):** Fixture **`azl/tests/p0_semantic_dotted_counter.azl`** — **`::perf.stats.tok_hits`** as a single token key with **`set`** / **`+`** increments (interpreter-shaped); gate **F7** (exits **61–63**).

**P0i (behavior + `interpret` listener, 2026-03-20):** Fixture **`azl/tests/p0_semantic_behavior_interpret_listen.azl`** — stub component with **`behavior { listen for "interpret" { … } }`**, **`boot.entry`** **`emit interpret`** after **`link`**; gate **F8** (exits **64–66**). Same outer shape as **`::azl.interpreter`** dispatch entry. Event payload and **`::event.data.*`** for listeners: **P0k** / gate **F10**.

**P0r (`return` in listener / `if`, 2026-03-21):** **`return`** exits the current listener body (top-level or from inside **`if { … }`** when **`g_listener_nesting`/`_listener_nesting` > 0**); **`return`** in top-level **`init`** skips the rest of **`init`**. Gate **F68**: **`azl/tests/p0_semantic_return_in_listener_if.azl`**, C ↔ Python byte-identical stdout (exits **291–293**).

**P0s (`split` + `for-in` listener loop, 2026-03-21):** **`set ::dst = ::src.split("literal")`** stores **`::src`** split on the unescaped delimiter, segments joined by newline; **`for ::var in ::seq { … }`** runs only in **listener** bodies ( **`init`** rejects **`for-in`** with typed error exit **5**). Nested **`exec_block`** from **`for`** uses **`preserve_listener_break_on_exit`** so **`return`** inside the loop body still exits the outer listener. Gate **F69**: **`azl/tests/p0_semantic_for_split_line_loop.azl`**, C ↔ Python byte-identical stdout (exits **294–296**).

**P0t (`::var.length` in expressions, 2026-03-21):** Primary **`::name.length`** (single token, including dotted globals like **`::perf.stats`**) evaluates to the **decimal string** length of **`var_get(::name)`**; unset → **`"0"`**. Gate **F70**: **`azl/tests/p0_semantic_dot_length_global.azl`**, C ↔ Python byte-identical stdout (exits **297–299**).

**P0u (`split_chars` + char **`for`**, 2026-03-21):** **`set ::dst = ::src.split_chars()`** stores UTF-8 **scalar values** (Python **`str`** elements / C **`utf8_scalar_byte_len`**) joined by newline; **`for ::c in ::dst`** iterates them — matches **`for ::char in ::line_text`** in **`azl_interpreter.azl`**. Gate **F71**: **`azl/tests/p0_semantic_split_chars_for.azl`**, C ↔ Python byte-identical stdout (exits **311–313**).

**P0push (`set ::buf.push`, 2026-03-21):** **`set ::buf.push("literal")`** or **`::var`** appends one newline-delimited segment; unset / **`[]`** starts fresh (same encoding as **`split`** / **`for ::row in`**). **Object-literal** **`push`** and list **`.concat`** — **P0tz**. Gate **F72**: **`azl/tests/p0_semantic_push_string_listener.azl`**, C ↔ Python byte-identical stdout (exits **314–316**).

**P0sub (binary int `-`, 2026-03-21):** Expression **`::a - ::b`** when both sides are canonical base-10 integers (including **`::name.length`** primaries) subtracts; non-integer **`-`** is a **typed error** in Python (**`SemanticEngineError(5)`**) and **`eval_expr`** failure in C (**exit 5**). Gate **F73**: **`azl/tests/p0_semantic_int_sub_column_length.azl`**, C ↔ Python byte-identical stdout (exits **317–319**).

**P0str (`in_string` + quote toggle, 2026-03-22):** **`for ::c in ::line.split_chars()`** with nested **`if`** and per-iteration **`::handled`** so closing and opening **`"`** on the same character do not double-toggle (minimal has no **`else`**). Gate **F74**: **`azl/tests/p0_semantic_tokenize_in_string_char.azl`** (exits **323–325**).

**P0tz (token rows + **`.concat`**, 2026-03-22):** **`set ::buf.push({ type: "…", value: "…", line: N, column: M })`** (**flat** keys; values quoted or decimal) appends a **`tz|…|…|…|…`** segment (**`\|`** / **`\\`** escapes). **`set ::acc = ::lhs.concat(::rhs)`** joins two buffers with newline (**`[]`** / empty treated like other list walks). Gate **F75**: **`azl/tests/p0_semantic_tokens_push_tz_concat.azl`** (exits **326–328**). **Implementation note (2026-03-22):** C **`parse_push_tz_object`** formats the row into a **512-byte** scratch buffer, then copies **at most `seg_sz - 1`** bytes into the caller buffer (typically **256** in **`exec_set`**), so **`gcc -Wformat-truncation`** is not tripped on **`snprintf`** and oversized escaped rows are truncated consistently with **`Var.v[256]`**; Python **`minimal_runtime`** stores **`joined[:255]`** after **`.push`**. **F123+** remains the spine queue for deeper **`execute_ast`** vs **`execute_component` / `execute_listen`** — not part of this hygiene fix.

**P0inc (line + accumulator, 2026-03-22):** **`set ::line = ::line + 1`** (canonical int **`+`**) and **`set ::current = ::current + ::c`** (string concat) inside **`split_chars`** loops — matches **`tokenize_line`** increment / **`::current + ::char`**. Gate **F76**: **`azl/tests/p0_semantic_tokenize_line_inc_concat.azl`** (exits **329–331**).

**P0outer (tokenize listener line loop, 2026-03-22):** **`set ::lines = ::code.split("\\n")`**, **`for ::line_text in ::lines`**, per-line **`::chunk.push({ … value: ::line_text, line: ::line, … })`**, **`::tokens = ::tokens.concat(::chunk)`**, eol **`push`**, **`::line = ::line + 1`** — matches **`listen for "tokenize"`** outer loop in **`azl_interpreter.azl`** before **`::tokenize_line(...)`** exists as a callable (fixture uses a stub **`id`** row per line). Object **`.push`** values may be **`::var`** (not only literals). Gate **F77**: **`azl/tests/p0_semantic_tokenize_outer_line_loop.azl`** (exits **332–334**).

**P0dip (double-quoted `say` interpolation, 2026-03-22):** **`say "…"`** expands **`::dotted.path`** and **`::path.length`** (same **`.length`** rule as expressions: byte length of stored value). **`say '…'`** remains literal. Matches **`azl_interpreter.azl`** tokenize listener tail **`say "📝 Generated ::tokens.length tokens"`** at the **string-interpolation** level (fixture uses ASCII markers). Gate **F78**: **`azl/tests/p0_semantic_say_double_interpolate.azl`** (exits **335–337**).

**P0emitbind (`emit with` payload `::var`, 2026-03-22):** In **`emit … with { key: ::var }`**, payload values that are **`::…`** tokens are **`var_get`** at **emit** time (unset → empty string), so downstream **`::event.data.key`** receives the **value**, not the token text. Matches **`emit tokenize_complete with { tokens: ::tokens }`** in **`azl_interpreter.azl`**. Gate **F79**: **`azl/tests/p0_semantic_emit_payload_var_bind.azl`** (exits **338–340**).

**P0tokcache (tokenize cache check + miss counter, 2026-03-22):** **`if (::cached_tok != null) { … return }`** on the cache-hit path; on miss, **`::perf.stats.tok_misses = ::perf.stats.tok_misses + 1`** — aligns **`listen for "tokenize"`** ~**75–83** vs ~**101** (fixture uses **`::cached_tok`** because minimal **`set`** requires **`::`** LHS; real file uses **`cached_tok`** / map lookup). Gate **F80**: **`azl/tests/p0_semantic_tokenize_cache_miss_branch.azl`** (exits **341–343**).

**P0tokhit (tokenize cache hit + `tok_hits`, 2026-03-22):** When **`::cached_tok != null`**, **`::perf.stats.tok_hits = ::perf.stats.tok_hits + 1`**, **`set ::tokens = ::cached_tok`**, then **`return`** after the tokenize tail (real file: double-quoted **`say`**, **`emit tokenize_complete with { tokens: ::tokens }`**, **`return`** ~**76–82**). Fixture seeds **`::cached_tok`** in **`init`** and uses **`say`** markers (**`CACHE_HIT`**, **`hit-body`**) instead of **`emit`**. Gate **F81**: **`azl/tests/p0_semantic_tokenize_cache_hit_branch.azl`** (exits **344–346**).

**P0tokemit (tokenize cache hit + `emit tokenize_complete`, 2026-03-22):** Same hit path as **P0tokhit**, then **`emit tokenize_complete with { tokens: ::tokens }`** so **`::event.data.tokens`** is visible in a **`listen for "tokenize_complete"`** body. Real file registers that listener in **`init`** before **`emit tokenize`** (~**46** vs ~**81**); fixture registers **`tokenize_complete`** before the starter event. Gate **F82**: **`azl/tests/p0_semantic_tokenize_cache_hit_emit_complete.azl`** (exits **347–349**).

**P0parsemiss (parse cache miss + `ast_misses`, 2026-03-22):** **`set ::tokens = ::event.data.tokens`** then **`if (::cached_ast != null)`** miss branch + **`::perf.stats.ast_misses + 1`** — aligns **`listen for "parse"`** ~**109–127** (fixture uses **`::cached_ast`** stand-in for **`cached_ast`** / **`::perf.ast_cache[::key]`**). Gate **F83**: **`azl/tests/p0_semantic_parse_cache_miss_branch.azl`** (exits **350–352**).

**P0parsehit (parse cache hit + `ast_hits`, 2026-03-22):** Hit path **`::perf.stats.ast_hits + 1`**, **`set ::ast = ::cached_ast`**, **`return`** (~**113–119**). Gate **F84**: **`azl/tests/p0_semantic_parse_cache_hit_branch.azl`** (exits **353–355**).

**P0parseemit (parse cache hit + `emit parse_complete`, 2026-03-22):** Hit path + **`emit parse_complete with { ast: ::ast }`**; inner **`listen for "parse_complete"`** reads **`::event.data.ast`**. Gate **F85**: **`azl/tests/p0_semantic_parse_cache_hit_emit_complete.azl`** (exits **356–358**).

**P0execpayload (execute listener payload + `execute_complete`, 2026-03-22):** **`set ::ast = ::event.data.ast`**, **`set ::scope = ::event.data.scope`**, stub **`::result`**, **`emit execute_complete with { result: ::result }`** — aligns **`listen for "execute"`** ~**130–132**, tree-walk tail ~**159–162** (no **`::execute_ast`** / VM in fixture). Gate **F86**: **`azl/tests/p0_semantic_execute_payload_emit_complete.azl`** (exits **359–361**).

**P0usevmoff (`AZL_USE_VM` env probe, 2026-03-22):** **`set ::use_vm = ((::internal.env("AZL_USE_VM") or "") == "1")`**; miss branch when env unset — ~**141**. Native gate runs C + Python with **`AZL_USE_VM` unset** (**`env -u`**). Gate **F87**: **`azl/tests/p0_semantic_execute_use_vm_env_off.azl`** (exits **362–364**).

**P0halt (`halt_execution` listener, 2026-03-21):** **`listen for "halt_execution"`** — starter **`emit halt_execution with { … }`**, body **`set ::halted = true`** (ASCII **`say`** markers vs emoji in real file ~**167–170**). Gate **F88**: **`azl/tests/p0_semantic_halt_execution_listener.azl`** (exits **365–367**).

**P0execpre (execute preloop over **`::ast.nodes`**, 2026-03-21):** **`if (::ast != null && ::ast.nodes != null) { for ::n in ::ast.nodes { … } }`** — aligns **`listen for "execute"`** ~**134–139** (full AZL uses object-truthy **`::ast && ::ast.nodes`**; minimal uses **`!= null`** + **`&&`**). **`for-in`** inside **`if`** then-branch is allowed when **`g_listener_nesting` / `_listener_nesting > 0`** (not in component **`init`**). Gate **F89**: **`azl/tests/p0_semantic_execute_ast_nodes_preloop.azl`** (exits **368–370**).

**P0execvm (`AZL_USE_VM=1` compile + run stub, 2026-03-21):** **`set … = ::vm_compile_ast(::ast)`** populates **`::vc.ok`**, **`::vc.error`**, **`::vc.bytecode`** (magic tags **`F90_VM_OK`** / **`F91_VM_BAD`** / **`F92_VM_EMPTY`**); **`::vm_run_bytecode_program(::vc.bytecode)`** returns **`P0_VM_EXEC_OK`** for gate bytecode — aligns **`listen for "execute"`** ~**141–156** at the **branch / result-string** level (not real opcodes). Gates **F90**–**F92** run with **`AZL_USE_VM=1`** (exits **371–379**).

**P0exectree (`AZL_USE_VM` off — `::execute_ast` stub, 2026-03-22):** **`set ::result = ::execute_ast(::ast, ::scope)`** walks **`<astVar>.nodes`** as newline steps; **`say|TEXT`** prints **`TEXT`** and sets return string to **`Said: TEXT`** (last step wins); empty/missing **`.nodes`** → **`Execution completed`** — aligns **`listen for "execute"`** ~**159–162** + **`::execute_ast`** ~**750–768** at the **tree-walk / result-string** level (not real **`component` / `listen`** nodes yet). Gate **F93**: **`azl/tests/p0_semantic_execute_ast_tree_walk.azl`** with **`AZL_USE_VM` unset** (exits **380–382**).

**P0exectreeemit (`execute_ast` **`emit|`** step, 2026-03-22):** **`emit|eventName`** queues a **bare** event (no **`with`** payload), then drains the queue like **`emit`** in **`exec_block`** — return string **`Emitted: eventName`** (mirrors **`execute_emit`** result shape at the string level). Gate **F94**: **`azl/tests/p0_semantic_execute_ast_emit_step.azl`** (exits **383–385**).

**P0exectreeset (`execute_ast` **`set|`** step, 2026-03-22):** **`set|::global|value`** assigns **`var_set(::global, value)`**; return string **`Set ::global = value`** (mirrors **`execute_set`** return shape; minimal stub does **not** print the interpreter **`say`** line). Gate **F95**: **`azl/tests/p0_semantic_execute_ast_set_step.azl`** (exits **386–388**).

**P0exectreewith (`execute_ast` **`emit|…|with|…`** step, 2026-03-22):** **`emit|event|with|payloadKey|payloadValue`** queues one key/value (pipe encoding); return string **`Emitted: event`**. Gate **F96**: **`azl/tests/p0_semantic_execute_ast_emit_with_step.azl`** (exits **389–391**).

**P0exectreewithmulti (`execute_ast` multi-pair **`emit|…|with|…`** tail, 2026-03-22):** **`emit|event|with|k1|v1|k2|v2|…`** (repeat **`|key|value`** after the first **`|with|`**); up to **`MAX_PAYLOAD_KEYS`**; return string **`Emitted: event`**. Gate **F97**: **`azl/tests/p0_semantic_execute_ast_emit_multi_with_step.azl`** (exits **392–394**).

**P0execpreil (`execute_ast` **`import|/`link|`** preloop, 2026-03-22):** Before **`say|`** / **`emit|`** / **`set|`**, walk **`import|module`** (stub → **`::p0_exec_import_last`**) and **`link|::component`** (same side-effect as **`link`** in **`init`**) — aligns **`listen for "execute"`** ~**134–139** at the **ordering / stub** level (not real **`resolve_module_now`**). Gate **F98**: **`azl/tests/p0_semantic_execute_ast_import_link_preloop.azl`** (exits **395–397**). See **F112** (**P0execpreilmemory**) when the first **post-preloop** row is **`memory|say|…`**.

**P0exectreecomplisten (`execute_ast` **`component|`** + **`listen|…|say|…`**, 2026-03-22):** **`component|name`** runs **`run_linked_component`** (same as **`link`**); return **`Component: name`**. **`listen|event|say|payload`** registers a **stub** listener (cleared each **`execute_ast`** walk); if **`process_events`** finds **no** token **`listen`** for that event, the stub **`say`** runs. Gate **F99**: **`azl/tests/p0_semantic_execute_ast_component_listen_step.azl`** (exits **398–400**).

**P0exectreelistenemit (`execute_ast` **`listen|…|emit|…`** stub, 2026-03-22):** **`listen|event|emit|innerEvent`** registers a stub that **queues** **`innerEvent`** (bare emit, no payload) and drains the queue — nested dispatch before the outer **`execute_ast`** step continues (mirrors **`emit`** inside a real listener body at a minimal level). Event name must not contain **`|`** (F100 encoding). Gate **F100**: **`azl/tests/p0_semantic_execute_ast_listen_emit_stub.azl`** (exits **401–403**).

**P0exectreelistenset (`execute_ast` **`listen|…|set|::global|value`** stub, 2026-03-22):** **`listen|event|set|::key|value`** registers a stub that **`var_set`s** the global when the event is dispatched and no token **`listen`** matches (same queue path as F99/F100). Gate **F101**: **`azl/tests/p0_semantic_execute_ast_listen_set_stub.azl`** (exits **404–406**, **P0exectreelistenset**).

**P0exectreelistenemitwith (`execute_ast` **`listen|…|emit|…|with|…`** stub, 2026-03-22):** **`listen|event|emit|inner|with|k|v(|k|v)*`** registers a stub that **`queue_push_event`s** the inner event with the same **`execute_ast_parse_with_pairs`** payload as a direct **`emit|inner|with|…`** row (F96 shape). Gate **F102**: **`azl/tests/p0_semantic_execute_ast_listen_emit_with_stub.azl`** (exits **407–409**, **P0exectreelistenemitwith**).

**P0exectreelistenemitwithmulti (`execute_ast` **`listen|…|emit|…|with`** multi-pair stub, 2026-03-22):** Same as **F102** with **two or more** **`k|v`** pairs after **`|with|`** (F97 parity for stub path). Gate **F103**: **`azl/tests/p0_semantic_execute_ast_listen_emit_multi_with_stub.azl`** (exits **410–412**, **P0exectreelistenemitwithmulti**).

**P0exectreememory (`execute_ast` **`memory|`** stub row, 2026-03-22):** **`memory|set|::global|value`** delegates to the same **`set|…`** path as **F95**; **`memory|say|payload`** prints and sets return like **`say|`**. Mirrors **`execute_component`** running **`component.sections.memory.statements`** as **`execute_statement`** at **one pipe-encoded row** per line (not multi-statement bodies yet). Gate **F104**: **`azl/tests/p0_semantic_execute_ast_memory_set_step.azl`** (exits **413–415**, **P0exectreememory**).

**P0exectreememoryemit (`execute_ast` **`memory|emit|…`** bare, 2026-03-22):** **`memory|emit|event`** delegates to the same **`emit|…`** path as **F94** (queue + **`process_events`**). Gate **F105**: **`azl/tests/p0_semantic_execute_ast_memory_emit_step.azl`** (exits **416–418**, **P0exectreememoryemit**).

**P0exectreememoryemitwith (`execute_ast` **`memory|emit|…|with|…`** one pair, 2026-03-22):** **`memory|emit|inner|with|k|v`** delegates like **F96**. Gate **F106**: **`azl/tests/p0_semantic_execute_ast_memory_emit_with_step.azl`** (exits **419–421**, **P0exectreememoryemitwith**).

**P0exectreememoryemitwithmulti (`execute_ast` **`memory|emit|…|with`** multi-pair, 2026-03-22):** Two or more **`k|v`** pairs after **`|with|`** (F97 parity under **`memory|`**). Gate **F107**: **`azl/tests/p0_semantic_execute_ast_memory_emit_multi_with_step.azl`** (exits **422–424**, **P0exectreememoryemitwithmulti**).

**P0exectreememorymultirow (`execute_ast` multi-row **`memory|`** source order, 2026-03-22):** Consecutive **`memory|say|…`** rows run in **source line order** before a trailing top-level **`say|`** in the same **`.nodes`** walk (stdout ordering regression). Gate **F108**: **`azl/tests/p0_semantic_execute_ast_memory_multi_row_order.azl`** (exits **425–427**, **P0exectreememorymultirow**).

**P0exectreememorymixed (`execute_ast` mixed **`memory|`** row kinds, 2026-03-22):** **`memory|set|::global|value`**, then **`memory|emit|…`** (queue + drain), then **`memory|say|…`** — **source order** on stdout; **`set`** visible after the full walk. Gate **F109**: **`azl/tests/p0_semantic_execute_ast_memory_mixed_order.azl`** (exits **428–430**, **P0exectreememorymixed**).

**P0exectreememorymixedemitwith (`execute_ast` **`memory|set|…`** then **`memory|emit|…|with|…`** then **`memory|say|…`**, 2026-03-22):** Same ordering stress as **F109**, but the middle row carries a **one-pair** **`|with|`** payload (**F106**-shaped under **`memory|`**). Gate **F110**: **`azl/tests/p0_semantic_execute_ast_memory_mixed_emit_with_order.azl`** (exits **431–433**, **P0exectreememorymixedemitwith**).

**P0exectreememorymixedemitwithmulti (`execute_ast` **`memory|set|…`** then **`memory|emit|…|with`** multi-pair then **`memory|say|…`**, 2026-03-22):** Same as **F110**, but the middle row carries **two or more** **`k|v`** pairs after **`|with|`** (**F107**-shaped under **`memory|`**). Gate **F111**: **`azl/tests/p0_semantic_execute_ast_memory_mixed_emit_multi_with_order.azl`** (exits **434–436**, **P0exectreememorymixedemitwithmulti**).

**P0execpreilmemory (`execute_ast` **`import|/`link|`** preloop then **`memory|say|…`**, 2026-03-22):** Same **`import|/`link|`** preloop as **F98** (**P0execpreil**), but the first **main-loop** row is **`memory|say|…`** — **`link`** side-effect and **`::p0_exec_import_last`** occur **before** memory stdout (ordering toward real **`execute`** + memory section). Gate **F112**: **`azl/tests/p0_semantic_execute_ast_preloop_then_memory_say.azl`** (exits **437–439**, **P0execpreilmemory**).

**P0execpreilsaymemory (`execute_ast` **`import|/`link|`** preloop then **`say|`** then **`memory|say|…`**, 2026-03-22):** Same preloop as **F112**, but a **top-level** **`say|`** row runs **before** **`memory|say|…`** in the main walk (stdout: **`link`** init, **`say`**, **`memory|say`**). Gate **F113**: **`azl/tests/p0_semantic_execute_ast_preloop_say_then_memory_say.azl`** (exits **440–442**, **P0execpreilsaymemory**).

**P0execpreilemitmemory (`execute_ast` **`import|/`link|`** preloop then **`emit|…|with|…`** then **`memory|say|…`**, 2026-03-22):** Same preloop as **F112**, but a **top-level** **`emit|…|with|k|v`** row runs **before** **`memory|say|…`** in the main walk (queue + drain so listener stdout appears **before** **`memory|say`**). Gate **F114**: **`azl/tests/p0_semantic_execute_ast_preloop_emit_then_memory_say.azl`** (exits **443–445**, **P0execpreilemitmemory**).

**P0exectreememorylisten (`execute_ast` **`memory|listen|…`** stub row, 2026-03-22):** Under the **`memory|`** prefix, **`listen|ev|say|…`** (and same shapes as top-level **F99**–**F103** stubs) registers into the **`execute_ast`** stub table; **`memory|emit|ev`** then drains so the stub runs **before** a trailing **`memory|say|…`**. Gate **F115**: **`azl/tests/p0_semantic_execute_ast_memory_listen_emit_say.azl`** (exits **446–448**, **P0exectreememorylisten**).

**P0exectreememorylistenemitwith (`execute_ast` **`memory|listen|…|emit|…|with|…`** stub, 2026-03-22):** Under **`memory|`**, **`listen|ev|emit|inner|with|k|v`** (**F102**-shaped); **`memory|emit|ev`** drains the stub, which queues the inner event with payload so a **token** listener can **`say ::event.data.<k>`** before **`memory|say|…`**. Gate **F116**: **`azl/tests/p0_semantic_execute_ast_memory_listen_emit_with_say.azl`** (exits **449–451**, **P0exectreememorylistenemitwith**).

**P0exectreememorylistenemitwithmulti (`execute_ast` **`memory|listen|…|emit|…|with`** multi-pair stub, 2026-03-22):** Under **`memory|`**, **`listen|ev|emit|inner|with|k1|v1|k2|v2`** (**F103**-shaped); same drain + dual-payload **`::event.data.*`** read as **F103** before **`memory|say|…`**. Gate **F117**: **`azl/tests/p0_semantic_execute_ast_memory_listen_emit_multi_with_say.azl`** (exits **452–454**, **P0exectreememorylistenemitwithmulti**).

**P0execpreilmemorylistenemitwithmulti (`execute_ast` **`import|/`link|`** preloop then **F117**-shaped **`memory|listen|…|emit|…|with`** multi-pair + **`memory|emit|…`** + **`memory|say|…`**, 2026-03-22):** **`link|`** side-effect (**`P118_LINK_SID`**) runs in the preloop before the main walk; ordering matches **F112** + **F117** composed. Gate **F118**: **`azl/tests/p0_semantic_execute_ast_preloop_memory_listen_emit_multi_with_say.azl`** (exits **455–457**, **P0execpreilmemorylistenemitwithmulti**).

**P0exectreememorylistenstack (`execute_ast` stacked **`memory|listen|…|say|…`** stubs, 2026-03-22):** Two consecutive **`memory|listen|ev|say|payload`** rows register distinct stub entries; **`memory|emit|ev1`** then **`memory|emit|ev2`** drain in **source order** before **`memory|say|…`**. Gate **F119**: **`azl/tests/p0_semantic_execute_ast_memory_listen_stack_say.azl`** (exits **458–460**, **P0exectreememorylistenstack**).

**P0execpreilmemorylistenstack (`execute_ast` **`import|/`link|`** preloop then **F119**-shaped stacked **`memory|listen|…|say|…`** + dual **`memory|emit|…`** + **`memory|say|…`**, 2026-03-22):** Composes **F112** preloop (**`P120_LINK_SID`**) with **F119** main-walk ordering. Gate **F120**: **`azl/tests/p0_semantic_execute_ast_preloop_memory_listen_stack_say.azl`** (exits **461–463**, **P0execpreilmemorylistenstack**).

**P0execpreilsaymemorylistenstack (`execute_ast` preloop then top-level **`say|`** before first **`memory|listen|…`** in an **F119** stack, 2026-03-22):** **F113** ordering (**`say|`** between preloop tail and memory section) composed with **F119** stacked listens + dual **`memory|emit|…`**. Gate **F121**: **`azl/tests/p0_semantic_execute_ast_preloop_say_then_memory_listen_stack_say.azl`** (exits **464–466**, **P0execpreilsaymemorylistenstack**).

**P0execpreilemitmemorylistenstack (`execute_ast` preloop then top-level **`emit|…|with|…`** before first **`memory|listen|…`** in an **F119** stack, 2026-03-22):** **F114**-shaped **`emit`** (queue + drain, token listener reads payload) before **F119** stacked listens. Gate **F122**: **`azl/tests/p0_semantic_execute_ast_preloop_emit_then_memory_listen_stack_say.azl`** (exits **467–469**, **P0execpreilemitmemorylistenstack**).

**P0execpreilcomponentmemorysetlistenstack (`execute_ast` **`import|/`link|`** preloop then **`component|`** then **two** **`memory|set|…`** then **F119**-shaped stacked **`memory|listen|…|say|…`** + dual **`memory|emit|…`** + **`memory|say|…`**, 2026-03-22):** Composes **F112** preloop + **F99** **`component|`** + **F104** dual **`memory|set|`** + **F119** memory listen stack. Gate **F123**: **`azl/tests/p0_semantic_execute_ast_preloop_component_memory_set_listen_stack.azl`** (exits **470–472**, **P0execpreilcomponentmemorysetlistenstack**).

**P0execpreiltwocomponentmemorysay (`execute_ast` **`import|/`link|`** preloop then **`component|alpha`** then **`memory|say|…`** then **`component|beta`** then **`memory|say|…`**, 2026-03-22):** Two distinct **`component|`** rows interleaved with a memory stdout row — source order vs **`run_linked_component`**. Gate **F124**: **`azl/tests/p0_semantic_execute_ast_preloop_two_component_memory_say.azl`** (exits **473–475**, **P0execpreiltwocomponentmemorysay**).

**P0execpreilthreecomponentmemorysay (`execute_ast` **`import|/`link|`** preloop then **three** **`component|…`** rows each separated by **`memory|say|…`**, 2026-03-22):** Triple linked-**`init`** interleave + trailing **`memory|say|…`**. Gate **F125**: **`azl/tests/p0_semantic_execute_ast_preloop_three_component_memory_say.azl`** (exits **476–478**, **P0execpreilthreecomponentmemorysay**).

**P0execpreilcomponentmemoryemitcomponentsay (`execute_ast` **`import|/`link|`** preloop then **`component|…`** then **`memory|emit|ev|with|k|v`** (queue + drain) then **`component|…`** then **`memory|say|…`**, 2026-03-22):** Memory-section **`emit|…|with|…`** between two **`run_linked_component`** steps — listener stdout before second **`init`**. Gate **F126**: **`azl/tests/p0_semantic_execute_ast_preloop_component_memory_emit_component_say.azl`** (exits **479–481**, **P0execpreilcomponentmemoryemitcomponentsay**).

**P0execpreilcomponentmemorydualemitcomponentsay (`execute_ast` **`import|/`link|`** preloop then **`component|…`** then **two** **`memory|emit|ev|with|k|v`** rows (FIFO queue + drain) then **`component|…`** then **`memory|say|…`**, 2026-03-22):** Like **F126**, but two sequential memory-section **`emit|…|with|…`** rows before the second **`component|`** — ordered listener stdout (**`F127_K1`** then **`F127_K2`**) before second **`init`**. Gate **F127**: **`azl/tests/p0_semantic_execute_ast_preloop_component_memory_dual_emit_component_say.azl`** (exits **482–484**, **P0execpreilcomponentmemorydualemitcomponentsay**).

**P0execpreilcomponentmemorytripleemitcomponentsay (`execute_ast` **`import|/`link|`** preloop then **`component|…`** then **three** **`memory|emit|ev|with|k|v`** rows (FIFO queue + drain) then **`component|…`** then **`memory|say|…`**, 2026-03-22):** Like **F127**, but three sequential memory-section **`emit|…|with|…`** rows — ordered listener stdout (**`F128_K1`** … **`F128_K3`**) before second **`init`**. Gate **F128**: **`azl/tests/p0_semantic_execute_ast_preloop_component_memory_triple_emit_component_say.azl`** (exits **485–487**, **P0execpreilcomponentmemorytripleemitcomponentsay**).

**P0execpreilcomponentmemorybareemitcomponentsay (`execute_ast` **`import|/`link|`** preloop then **`component|…`** then **bare** **`memory|emit|ev`** (no **`|with|…`**, same queue + drain as **F105**) then **`component|…`** then **`memory|say|…`**, 2026-03-22):** **F126**-shaped interleave but **F105**-style bare memory **`emit`** — listener body does not rely on **`::event.data.*`**. Gate **F129**: **`azl/tests/p0_semantic_execute_ast_preloop_component_memory_bare_emit_component_say.azl`** (exits **488–490**, **P0execpreilcomponentmemorybareemitcomponentsay**).

**P0execpreilcomponentmemorydualbareemitcomponentsay (`execute_ast` **`import|/`link|`** preloop then **`component|…`** then **two** bare **`memory|emit|ev`** rows (FIFO, no **`|with|…`**) then **`component|…`** then **`memory|say|…`**, 2026-03-22):** Like **F129**, but two sequential bare memory **`emit`** rows — ordered listener stdout (**`F130_BARE_1`** then **`F130_BARE_2`**) before second **`init`**. Gate **F130**: **`azl/tests/p0_semantic_execute_ast_preloop_component_memory_dual_bare_emit_component_say.azl`** (exits **491–493**, **P0execpreilcomponentmemorydualbareemitcomponentsay**).

**Open next (spine queue):** deeper **`execute_ast`** vs **`execute_component` / `execute_listen`** (triple+ bare **`memory|emit`**, mixed bare + **`with`** in one gap, non-stub memory bodies, real **`execute_listen`**) — **F131+**; **[PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md)** phase **E** depth + phase **F** behavior claim.

**P0.1 execution order (vertical slices):** Maintainership sequence for **`azl_interpreter.azl`** on the semantic spine — parity gates (**A**), real-file **`init`** smoke (**B**), then **tokenize → parse → execute** slices (**C–E**) before claiming full **behavior** (**F**). Single source: **[PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md)** § **P0.1 — Long-term execution order** and **[TIER_B_BACKLOG.md](TIER_B_BACKLOG.md)** § **P0.1 execution checklist**.

**P0j (`listen … then` in behavior, 2026-03-20):** Fixture **`azl/tests/p0_semantic_behavior_listen_then.azl`** — **`listen for "interpret" then { … }`**; gate **F9** (C/Python fail **67** / **68**; stdout mismatch **59** — distinct from **`verify_native_runtime_live.sh`** **69**).

**P0k (`emit … with { … }` → **`::event.data.*`**, 2026-03-21):** Fixture **`azl/tests/p0_semantic_emit_event_payload.azl`** — **`emit interpret with { trace: "…" }`**; listener **`say ::event.data.trace`**; event queue entries carry parsed key/value pairs, applied for the duration of the matching listener body, then cleared. Payload parser accepts **`key : value`** or **`key:`** merged as one token (minimal tokenizer includes **`:`** in identifier runs). Gate **F10** (C/Python fail **111** / **112**; stdout mismatch **113**).

**P0l (multi-key **`emit … with { … }`**, 2026-03-21):** Fixture **`azl/tests/p0_semantic_emit_multi_payload.azl`** — comma-separated pairs; **`say ::event.data.trace`** then **`say ::event.data.job`**. Gate **F11** (C/Python fail **114** / **115**; stdout mismatch **116**).

**P0m (queued **`emit`** + payloads, 2026-03-21):** Fixture **`azl/tests/p0_semantic_emit_queued_payloads.azl`** — two **`emit … with { trace: … }`** in one **`init`** to different event names (**`first`** / **`second`**); each listener sees only its payload. Gate **F12** (**117** / **118** / **119**).

**P0n (payload in **`+`** **`set`** RHS, 2026-03-21):** Fixture **`azl/tests/p0_semantic_payload_expr_chain.azl`** — `set ::out = ::event.data.trace + "-sfx"` inside listener. Gate **F13** (**120** / **121** / **122**).

**P0o (`if` on **`::event.data.*`**, 2026-03-21):** Fixture **`azl/tests/p0_semantic_payload_if_branch.azl`** — **`if ::event.data.mode == "strict" { … }`** inside listener. Gate **F14** (**123** / **124** / **125**).

**P0p–P0s (payload + control flow, 2026-03-21):** **F15** — **`p0_semantic_nested_emit_payload.azl`**: listener **`emit`** inner **`with`**; outer **`::event.data`** keys not cleared by inner payload keys remain. **F16** — **`p0_semantic_quoted_emit_with_payload.azl`**: **`emit "tick" with { … }`**. **F17** — **`p0_semantic_payload_ne_branch.azl`**: **`!=`** on **`::event.data.*`**. **F18** — **`p0_semantic_payload_or_fallback.azl`**: missing payload field + **`or`** in **`set`** RHS. Exits **126–137** (see **ERROR_SYSTEM**).

**P0t–P0u (payload surface, 2026-03-21):** **F19** — **`p0_semantic_emit_empty_with.azl`**: **`emit … with { }`**. **F20** — **`p0_semantic_payload_single_quote.azl`**: **`'…'`** string in **`with`**. Exits **138–143**.

**P0v (payload key collision, 2026-03-21):** **F21** — **`p0_semantic_payload_key_collide.azl`**: outer and inner **`with`** both set **`trace`**; after inner dispatch and clear, **`::event.data.trace`** is empty in the outer listener (**blank `say`** line before final marker). Exits **144–146**.

**P0w (nested **`listen`** + **`emit with`**, 2026-03-21):** **F22** — **`p0_semantic_nested_listen_emit_payload.azl`**: **`listen for "child"`** inside outer listener body, then **`emit child with { tag: … }`**. Exits **147–149**.

**P0x–P0z (listener ergonomics, 2026-03-21):** **F23** — **`p0_semantic_nested_listen_then_payload.azl`**: nested **`listen … then`** + **`emit with`**. **F24** — **`p0_semantic_payload_numeric_value.azl`**: payload value as bare integer. **F25** — **`p0_semantic_link_in_listener.azl`**: **`link`** inside listener. Exits **150–158**.

**F26–F28 (payload booleans + nested multi-key, 2026-03-21):** **F26** — **`p0_semantic_payload_bool_true.azl`**: bare **`true`** in **`with`**. **F27** — **`p0_semantic_nested_multikey_payload.azl`**: nested **`listen`** + inner **`emit … with { a:, b: }`**. **F28** — **`p0_semantic_payload_bool_false.azl`**: bare **`false`**. Exits **159–167**.

**F29–F31 (payload null/float + dispatch rule, 2026-03-21):** **F29** — **`p0_semantic_payload_null_value.azl`**: bare **`null`** in **`with`** (stored/said as literal **`null`**). **F30** — **`p0_semantic_first_matching_listener.azl`**: two **`listen for`** the same event — **first** registered runs, second ignored. **F31** — **`p0_semantic_payload_float_value.azl`**: bare float **`3.14`**. Exits **168–176**.

**F32–F35 (payload + **`if`** on **`null`**, 2026-03-21):** **F32** — **`p0_semantic_payload_missing_eq_null.azl`**: missing **`::event.data.*`** vs **`null`** (**`==`**). **F33** — **`p0_semantic_payload_big_int.azl`**: multi-digit bare int **`65535`** in **`with`**. **F34** — **`p0_semantic_set_from_payload.azl`**: **`set ::copy = ::event.data.msg`**. **F35** — **`p0_semantic_payload_present_ne_null.azl`**: present field **`!= null`**. Exits **177–188**. *(Bare negative ints in **`with`** are not parity-gated: minimal tokenizer splits **`-`** from digits.)*

**F36–F39 (quoted scalars + nested emit + listener **`if`**, 2026-03-21):** **F36** — **`p0_semantic_payload_quoted_negative.azl`**: payload **`"-7"`** (string). **F37** — **`p0_semantic_emit_from_listener_chain.azl`**: **`emit`** inside listener drains nested event before the outer listener continues (**`P37_IN_B`** before **`P37_AFTER_EMIT_B`**). **F38** — **`p0_semantic_payload_trailing_colon_key.azl`**: key token **`traceid:`** + value. **F39** — **`p0_semantic_if_true_literal_listener.azl`**: **`if (true)`** in listener. Exits **189–200**.

**F40–F43 (init **`listen`**, literals, payload isolation, 2026-03-21):** **F40** — **`p0_semantic_if_false_literal_listener.azl`**: **`if (false)`** skips branch (no **`F40_BAD`**). **F41** — **`p0_semantic_listen_in_init_emit.azl`**: **`listen`** in **`init`** then **`emit`** (**`F41_DYN_OK`** before boot marker). **F42** — **`p0_semantic_payload_squote_space.azl`**: single-quoted payload with space (**`a b`**). **F43** — **`p0_semantic_sequential_payload_events.azl`**: two **`emit … with`** different events → **`one`** then **`two`**. Exits **201–212**.

**F44–F47 (condition **`1`**, quoted **`emit`**, **`say`** blank, **`if`** on copied global, 2026-03-21):** **F44** — **`p0_semantic_if_one_literal_listener.azl`**: **`if (1)`** true (same rule as **`true`** / **`1`**). **F45** — **`p0_semantic_emit_quoted_event_only.azl`**: **`emit "solo"`** without **`with`**. **F46** — **`p0_semantic_say_unset_blank_line.azl`**: **`say`** unset **`::event.data.*`** → blank line, then marker. **F47** — **`p0_semantic_if_global_from_payload.azl`**: **`set ::flag = ::event.data.on`** then **`if (::flag)`** with payload **`on: "true"`**. Exits **213–224**.

**F48–F51 (falsy **`0`**, unquoted **`emit`**, empty **`say`**, string **`"false"`** truth, 2026-03-21):** **F48** — **`p0_semantic_if_zero_literal_listener.azl`**: **`if (0)`** skips (only **`true`** / **`1`** are truthy). **F49** — **`p0_semantic_emit_unquoted_event_only.azl`**: **`emit bare`** without **`with`**. **F50** — **`p0_semantic_say_empty_string_global.azl`**: **`set ::empty = ""`** then **`say ::empty`** → blank line. **F51** — **`p0_semantic_if_string_false_from_payload.azl`**: payload **`on: "false"`** copied to **`::flag`** → **`if (::flag)`** does **not** run (string **`false`** is not truthy). Exits **225–236**.

**F52–F55 (string truthy globals, same-event queue, boot **`listen`**, 2026-03-21):** **F52** — **`p0_semantic_if_var_true_string.azl`**: **`set ::t = "true"`** then **`if (::t)`** runs branch. **F53** — **`p0_semantic_same_event_twice_payload.azl`**: two **`emit x with { a: … }`** → listener **`say ::event.data.a`** prints **`first`** then **`second`**, then boot marker. **F54** — **`p0_semantic_listen_in_boot_entry.azl`**: **`listen`** + **`emit`** in **`::boot.entry`** **`init`** (**`F54_BOOT_LISTEN_OK`** before **`P0_SEMANTIC_LISTEN_IN_BOOT_ENTRY_OK`**). **F55** — **`p0_semantic_if_var_one_string.azl`**: **`set ::t = "1"`** then **`if (::t)`** runs branch (same truthy rule as bare **`1`**). Exits **237–248**.

**F56–F58 (string falsy globals, cross-component listener precedence, 2026-03-21):** **F56** — **`p0_semantic_if_var_zero_string.azl`**: **`set ::t = "0"`** → **`if (::t)`** skips (only **`true`** / **`1`** are truthy; string **`"0"`** is not). **F57** — **`p0_semantic_if_var_empty_string.azl`**: **`set ::t = ""`** → **`if (::t)`** skips. **F58** — **`p0_semantic_cross_component_first_listener.azl`**: two components each **`listen for "shared"`**; **`link`** order picks the handler (**`F58_FIRST_LINKED`** before boot marker, no **`F58_SECOND_BAD`**). Exits **249–257**.

**F59–F61 (double bare **`emit`**, **`or`** in **`if`**, global **`==`**, 2026-03-21):** **F59** — **`p0_semantic_double_emit_same_event.azl`**: two **`emit tick`** without **`with`** → listener runs twice (**`F59_TICK_HIT`** lines) then boot marker. **F60** — **`p0_semantic_if_or_empty_then_one_string.azl`**: **`set ::a = ""`** then **`if (::a or "1")`** runs branch (**`or`** fallback to truthy string). **F61** — **`p0_semantic_if_global_eq_globals.azl`**: **`set ::a` / `::b`** same literal → **`if (::a == ::b)`** runs branch. Exits **258–266**.

**F62–F64 (global **`!=`** + **`+`** concat, 2026-03-21):** **F62** — **`p0_semantic_if_global_ne_globals.azl`**: **`if (::a != ::b)`** when values differ (**`F62_NEQ_BRANCH`**). **F63** — **`p0_semantic_if_global_ne_equal_skip.azl`**: equal globals → **`!=`** branch skipped (no **`F63_BAD`**). **F64** — **`p0_semantic_set_global_concat_globals.azl`**: **`set ::u = ::a + ::b`** → **`hello`** then marker. Native gate exits **267–269**, **270** / **272** / **273**, **274–276** (**271** unused here — literal codec harness owns **271**).

**F65–F67 (literal string **`==`** / **`!=`**, triple **`+`**, 2026-03-21):** **F65** — **`p0_semantic_if_literal_eq_strings.azl`**: **`if ("x" == "x")`**. **F66** — **`p0_semantic_if_literal_ne_strings.azl`**: **`if ("a" != "b")`**. **F67** — **`p0_semantic_set_triple_concat_mixed.azl`**: **`set ::out = "pre" + ::mid + "post"`** → **`preMIDpost`**. Exits **277–285**.

**Partial / adjacent (not P0 complete):**

- **`AZL_NATIVE_RUNTIME_CMD`** is intentionally pluggable; an operator can point it at a custom launcher without changing the C engine.
- **`scripts/azl_bootstrap.sh`** + **`scripts/azl_seed_runner.sh`** can run a **bootstrap bundle** that embeds interpreter sources and `::boot.entry` — a **different** shape than “combined enterprise file + default C minimal”.

**P0 is complete when:** the **same** canonical command (or an explicitly documented primary profile) traces execution into the **AZL interpreter** as the component that applies **full language semantics** to the combined program, with the C engine limited to **HTTP / process / FIFO / env** as below. Verification is by **tracing the process** and/or a **small integration test** that fails if the C minimal is still the semantic owner.

**Next execution steps (IDs):** [TIER_B_BACKLOG.md](TIER_B_BACKLOG.md) § P0.

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

## RepertoireField (one line; legacy path `azl/quantum/`)

**RepertoireField** memory and processors (often still under **`azl/quantum/`** in paths) are part of the **core language and product story** (components, events, APIs users rely on). Public meaning: **whole situation → one committed outcome** in **real software**, BA-aligned — see **`docs/AZL_GPU_NEURAL_SURFACE_MAP.md` §0** and **`docs/AZL_BCBA_NAMING_FRAME.md`**. Tightening **semantics + tests for guaranteed behavior** is core work; vague naming without documented meaning is not.

---

## Related docs

| Document | Role |
|----------|------|
| [AZL_NATIVE_RUNTIME_CONTRACT.md](AZL_NATIVE_RUNTIME_CONTRACT.md) | Legal-style runtime + completion gates |
| [AZL_PERFECTION_PLAN.md](AZL_PERFECTION_PLAN.md) | Broader strategic phases (still valid; this doc narrows **spine**) |
| [AZL_DOCUMENTATION_CANON.md](AZL_DOCUMENTATION_CANON.md) | Shipped + verified snapshot (§1.8) |
| [AZL_GPU_NEURAL_SURFACE_MAP.md](AZL_GPU_NEURAL_SURFACE_MAP.md) | **RepertoireField** semantics + GPU / neural / LHA3 surface map |
| [AZL_BCBA_NAMING_FRAME.md](AZL_BCBA_NAMING_FRAME.md) | BCBA product language; **RepertoireField** chosen; LHA3 open |
| [PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md) | Phased “whole project” work vs contract (P0–P5) |

---

## Changing this decision

Any PR that **changes the default native execution spine** must update **this file** and **`docs/AZL_NATIVE_RUNTIME_CONTRACT.md`** in the same change set, and add or adjust a **gate test** if the repo enforces the spine in CI.
