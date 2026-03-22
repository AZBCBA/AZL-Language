# AI & maintainer continuity — handoff (do not skip)

**Status:** **Permanent project memory** (git). AI sessions **do not** retain chat history across disconnects. **This file + linked docs are the continuity layer.** Re-read them at the **start** of substantive work.

**Audience:** Any human maintainer or **any AI assistant** joining cold.

**Last updated:** 2026-03-22

---

## 1. How we got here (reality, not story)

This direction was **not** invented in one message. It comes from a **long discussion**: vision (AZL leading; speed as real hardware outcomes; challenge legacy ML assumptions), **critical thinking** (what is proven vs aspirational), and **research grounding** (compression, codegen, information limits where relevant).

**Arrived-at consensus** is written in:

| Read first | Why |
|------------|-----|
| **[AZL_STRATEGIC_CONSENSUS_AND_EXECUTION_PLAN.md](AZL_STRATEGIC_CONSENSUS_AND_EXECUTION_PLAN.md)** | North star, phases, literal vs serving vs semantic, wedges W1–W3, harness vs language |
| **[PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md)** | P0–P5 spine, gates, what is **actually** queued; **§ P0.1** = ordered vertical-slice plan toward **`azl_interpreter.azl`** on the spine |
| **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)** | **Process trace truth** — what runs today (C minimal, semantic Python, etc.) |

**Honesty about code vs narrative:**

| Doc | Role |
|-----|------|
| **[AZL_ENGINEERING_REALITY_AUDIT.md](AZL_ENGINEERING_REALITY_AUDIT.md)** | What the repo **really** does vs product language |
| **[LHA3_COMPRESSION_HONESTY.md](LHA3_COMPRESSION_HONESTY.md)** | Heuristic retention vs **literal** byte codecs — do not conflate |
| **[AZL_LITERAL_CODEC_CONTAINER_V0.md](AZL_LITERAL_CODEC_CONTAINER_V0.md)** | **Exact** tier wire format + **`CODEC_*`** errors (normative); decoder implementation = subsequent harness work |

---

## 2. What is reality today vs what we are building

- **Reality today:** Partial spine, narrow interpreters, docs and `.azl` files that sometimes **read** more complete than the **default trace**. Rust may live **off-repo**; **0** `*.rs` in-tree per audit.
- **Target (not yet fully real):** Native **AOT/codegen** backbone; **literal** codecs **where Exact is claimed**; **serving/quantized** paths where scale matters; **LHA3/policy** as semantic layer; **bootstrap** then **self-host**; **CLI** install story; **tests/harness** separate from language with **explicit errors** per **[ERROR_SYSTEM.md](ERROR_SYSTEM.md)**.
- **Release verify:** **`make verify`** runs **`scripts/verify_azl_interpreter_semantic_spine_smoke.sh`** (step **3** after native gates) — proves the **real** **`azl/runtime/interpreter/azl_interpreter.azl`** file completes **`init`** on the **Python** semantic spine with a harness **`::azl.security`** stub (**P0.1b**); **not** full **`behavior`**. See **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)** **P0.1b**, **[CONNECTIVITY_AUDIT.md](CONNECTIVITY_AUDIT.md)** step **3**.

**Any assistant must treat “target” as a roadmap, not as shipped fact** — unless a **gate, test, or trace** proves it.

---

## 3. Instructions to your future AI self (anti-loop, anti-fake)

**Do:**

1. **Open the three docs in §1** before large refactors or “architecture” answers.
2. **Trace the process** (spine doc) when claiming what “runs” or “is canonical.”
3. **Separate** harness from language; **name errors**; **no silent success** on failure.
4. **Match vision to implementation:** if adding **literal** compression, add **round-trip proof** in harness — update **LHA3** honesty docs if behavior changes.
5. **Respect maintainer rules:** production mindset, error system, fix originals — no duplicate “enhanced/simple” file trees.

**Do not:**

1. **Loop** the same abstract lecture (e.g. entropy / lossless limits) **unless** the user is making a **specific impossible lossless claim** — then **one precise sentence**, then return to **their** engineering goal (AOT, policy, codecs, spine).
2. **Imply** “pure AZL / no Rust / interpreter replaces everything” **without** aligning to **RUNTIME_SPINE_DECISION.md** — that **wastes** maintainer time and **erodes trust**.
3. **Invent** milestones, green CI, or “done” states **not** backed by scripts/gates in repo.
4. **Conflate** marketing names (RepertoireField, quantum labels) with **one unified implementation** without reading **GPU_NEURAL_SURFACE_MAP** + audit.

---

## 4. Maintainer vision (one paragraph, stable)

**AZL** is the **leading** language for the system — **not Python-shaped** long-term. **Speed** means **measured** outcomes on CPU/GPU/VRAM/IO. **Primary backbone:** **compile to native / AOT** (e.g. LLVM-class), with honest **bootstrap**; **self-host** is the **same** project, staged. **Compression/memory:** **Exact** artifacts need **literal, proven** codecs + **errors**; **scale** needs **lossy/structural** paths + **metrics**; **LHA3** owns **semantic policy** — do not oversell heuristics as byte codecs. **Research** challenges dense weights / flat bytes / generic compression **as wedges** with **hypotheses and tests**. **Shipping:** CLI / GitHub-style workflow, not desktop-first.

---

## 5. If you are an AI and only remember one thing

**The repo + these linked documents are the memory.**  
**Re-read this handoff and the strategic consensus doc at session start.**  
**Aspiration is real work; lies and loops are not.**

---

## 6. Changelog (this file)

| Date | Change |
|------|--------|
| 2026-03-22 | Gate **F126** — **`execute_ast`** preloop **`import|/`link|`** then **`component|p126.a`** then **`memory|emit|f126_mid|with|key|…`** (queue + drain) then **`component|p126.b`** then **`memory|say|…`** (**`p0_semantic_execute_ast_preloop_component_memory_emit_component_say.azl`**; exits **479–481**, **P0execpreilcomponentmemoryemitcomponentsay**). Parity range docs now **F2–F126**; **Open next** **F127+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)** (vertical slice **E**). |
| 2026-03-22 | Gate **F125** — **`execute_ast`** preloop **`import|/`link|`** then **three** **`component|p125.(a|b|c)`** rows with **`memory|say|…`** between each segment (**`p0_semantic_execute_ast_preloop_three_component_memory_say.azl`**; exits **476–478**, **P0execpreilthreecomponentmemorysay**). Parity range docs now **F2–F125**; **Open next** **F126+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)** (vertical slice **E**). |
| 2026-03-22 | Gate **F124** — **`execute_ast`** preloop **`import|/`link|`** then **`component|p124.alpha`** then **`memory|say|…`** then **`component|p124.beta`** then **`memory|say|…`** (**`p0_semantic_execute_ast_preloop_two_component_memory_say.azl`**; exits **473–475**, **P0execpreiltwocomponentmemorysay**). Parity range docs now **F2–F124**; **Open next** **F125+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)** (vertical slice **E**). |
| 2026-03-22 | Gate **F123** — **`execute_ast`** preloop **`import|/`link|`** then **`component|`** + dual **`memory|set|…`** then **F119**-shaped stacked **`memory|listen|…|say|…`** + dual **`memory|emit|…`** + **`memory|say|…`** (**`p0_semantic_execute_ast_preloop_component_memory_set_listen_stack.azl`**; exits **470–472**, **P0execpreilcomponentmemorysetlistenstack**). Parity range docs now **F2–F123**; **Open next** **F124+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)** (vertical slice **E**). |
| 2026-03-22 | Gate **F122** — **`execute_ast`** preloop **`import|/`link|`** then **`emit|…|with|…`** then **F119**-shaped stacked **`memory|listen|…|say|…`** + dual **`memory|emit|…`** + **`memory|say|…`** (**`p0_semantic_execute_ast_preloop_emit_then_memory_listen_stack_say.azl`**; exits **467–469**, **P0execpreilemitmemorylistenstack**). Parity range docs now **F2–F122**; **Open next** **F123+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)** (vertical slice **E**). |
| 2026-03-22 | Gate **F121** — **`execute_ast`** preloop **`import|/`link|`** then **`say|`** then **F119**-shaped stacked **`memory|listen|…|say|…`** + dual **`memory|emit|…`** + **`memory|say|…`** (**`p0_semantic_execute_ast_preloop_say_then_memory_listen_stack_say.azl`**; exits **464–466**, **P0execpreilsaymemorylistenstack**). Parity range docs now **F2–F121**; **Open next** **F122+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)** (vertical slice **E**). |
| 2026-03-22 | Gate **F120** — **`execute_ast`** preloop **`import|/`link|`** then **F119**-shaped stacked **`memory|listen|…|say|…`** + dual **`memory|emit|…`** + **`memory|say|…`** (**`p0_semantic_execute_ast_preloop_memory_listen_stack_say.azl`**; exits **461–463**, **P0execpreilmemorylistenstack**). Parity range docs now **F2–F120**; **Open next** **F121+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)** (vertical slice **E**). |
| 2026-03-22 | Gate **F119** — **`execute_ast`** stacked **`memory|listen|…|say|…`** stubs + dual **`memory|emit|…`** + **`memory|say|…`** (**`p0_semantic_execute_ast_memory_listen_stack_say.azl`**; exits **458–460**, **P0exectreememorylistenstack**). Parity range docs now **F2–F119**; **Open next** **F120+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)** (vertical slice **E**). |
| 2026-03-22 | Gate **F118** — **`execute_ast`** preloop **`import|/`link|`** then **F117**-shaped **`memory|listen|…|emit|…|with`** multi-pair + **`memory|emit|…`** + **`memory|say|…`** (**`p0_semantic_execute_ast_preloop_memory_listen_emit_multi_with_say.azl`**; exits **455–457**, **P0execpreilmemorylistenemitwithmulti**). Parity range docs now **F2–F118**; **Open next** **F119+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)** (vertical slice **E**). |
| 2026-03-22 | Gate **F117** — **`execute_ast`** **`memory|listen|…|emit|…|with`** multi-pair stub + **`memory|emit|…`** + **`memory|say|…`** (**`p0_semantic_execute_ast_memory_listen_emit_multi_with_say.azl`**; exits **452–454**, **P0exectreememorylistenemitwithmulti**). Parity range docs now **F2–F117**; **Open next** **F118+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)** (vertical slice **E**). |
| 2026-03-22 | Gate **F116** — **`execute_ast`** **`memory|listen|…|emit|…|with|…`** stub + **`memory|emit|…`** + **`memory|say|…`** (**`p0_semantic_execute_ast_memory_listen_emit_with_say.azl`**; exits **449–451**, **P0exectreememorylistenemitwith**). Parity range docs now **F2–F116**; **Open next** **F117+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)** (vertical slice **E**). |
| 2026-03-22 | Gate **F115** — **`execute_ast`** **`memory|listen|…`** stub + **`memory|emit|…`** + **`memory|say|…`** (**`p0_semantic_execute_ast_memory_listen_emit_say.azl`**; exits **446–448**, **P0exectreememorylisten**). Parity range docs now **F2–F115**; **Open next** **F116+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)** (vertical slice **E**). |
| 2026-03-22 | Gate **F114** — **`execute_ast`** **`import|/`link|`** preloop then **`emit|…|with|…`** then **`memory|say|…`** (**`p0_semantic_execute_ast_preloop_emit_then_memory_say.azl`**; exits **443–445**, **P0execpreilemitmemory**). Parity range docs now **F2–F114**; **Open next** **F115+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)** (vertical slice **E**). |
| 2026-03-22 | Gate **F113** — **`execute_ast`** **`import|/`link|`** preloop then **`say|`** then **`memory|say|…`** (**`p0_semantic_execute_ast_preloop_say_then_memory_say.azl`**; exits **440–442**, **P0execpreilsaymemory**). Parity range docs now **F2–F113**; **Open next** **F114+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)** (vertical slice **E**). |
| 2026-03-22 | Gate **F112** — **`execute_ast`** **`import|/`link|`** preloop then **`memory|say|…`** (**`p0_semantic_execute_ast_preloop_then_memory_say.azl`**; exits **437–439**, **P0execpreilmemory**). Parity range docs now **F2–F112**; **Open next** **F113+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)** (vertical slice **E** toward real **`execute`** + memory ordering). |
| 2026-03-22 | Gate **F111** — **`execute_ast`** **`memory|set|…`** → multi-pair **`memory|emit|…|with|…`** → **`memory|say|…`** (**`p0_semantic_execute_ast_memory_mixed_emit_multi_with_order.azl`**; exits **434–436**, **P0exectreememorymixedemitwithmulti**). Parity range docs now **F2–F111**; **Open next** **F112+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**. |
| 2026-03-22 | Gate **F110** — **`execute_ast`** **`memory|set|…`** → **`memory|emit|…|with|…`** → **`memory|say|…`** (**`p0_semantic_execute_ast_memory_mixed_emit_with_order.azl`**; exits **431–433**, **P0exectreememorymixedemitwith**). Parity range docs now **F2–F110**; **Open next** **F111+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**. |
| 2026-03-22 | Gate **F109** — **`execute_ast`** mixed **`memory|set|…`** → **`memory|emit|…`** → **`memory|say|…`** (**`p0_semantic_execute_ast_memory_mixed_order.azl`**; exits **428–430**, **P0exectreememorymixed**). Parity range docs now **F2–F109**; **Open next** **F110+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**. |
| 2026-03-22 | Gate **F108** — **`execute_ast`** multi-row **`memory|say|…`** + trailing **`say|`** order (**`p0_semantic_execute_ast_memory_multi_row_order.azl`**; exits **425–427**, **P0exectreememorymultirow**). Parity range docs now **F2–F108**; **Open next** **F109+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**. |
| 2026-03-22 | Gate **F107** — **`execute_ast`** **`memory|emit|…|with`** multi-pair stub (**`p0_semantic_execute_ast_memory_emit_multi_with_step.azl`**; exits **422–424**, **P0exectreememoryemitwithmulti**). Parity range docs now **F2–F107**; **Open next** **F108+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**. |
| 2026-03-22 | Gate **F106** — **`execute_ast`** **`memory|emit|…|with|…`** stub (**`p0_semantic_execute_ast_memory_emit_with_step.azl`**; exits **419–421**, **P0exectreememoryemitwith**). Parity range docs now **F2–F106**; **Open next** **F107+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**. |
| 2026-03-22 | Gate **F105** — **`execute_ast`** **`memory|emit|…`** stub (**`p0_semantic_execute_ast_memory_emit_step.azl`**; exits **416–418**, **P0exectreememoryemit**). Parity range docs now **F2–F105**; **Open next** **F106+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**. |
| 2026-03-22 | Gate **F104** — **`execute_ast`** **`memory|set|…`** / **`memory|say|…`** stub (**`p0_semantic_execute_ast_memory_set_step.azl`**; exits **413–415**, **P0exectreememory**). Parity range docs now **F2–F104**; **Open next** **F105+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**. |
| 2026-03-22 | **C minimal `.push` `tz|…` row:** **`parse_push_tz_object`** uses a **512-byte** **`snprintf`** scratch buffer + bounded **`memcpy`** into **`seg`** (see **P0tz** note in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**) — clears **`-Wformat-truncation`** on **`gcc`**; deeper spine queue **F124+** (post-**F123**) unchanged by this hygiene fix. |
| 2026-03-22 | Gate **F103** — **`execute_ast`** **`listen|…|emit|…|with`** multi-pair stub (**`p0_semantic_execute_ast_listen_emit_multi_with_stub.azl`**; exits **410–412**, **P0exectreelistenemitwithmulti**). Parity range docs now **F2–F103**; **Open next** **F104+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**. |
| 2026-03-22 | Gate **F102** — **`execute_ast`** **`listen|…|emit|…|with|…`** stub (**`p0_semantic_execute_ast_listen_emit_with_stub.azl`**; exits **407–409**, **P0exectreelistenemitwith**). Parity range docs now **F2–F102**; **Open next** **F103+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**. |
| 2026-03-22 | Gate **F101** — **`execute_ast`** **`listen|…|set|::global|value`** stub (**`p0_semantic_execute_ast_listen_set_stub.azl`**; exits **404–406**, **P0exectreelistenset**). Parity range docs now **F2–F101**; **Open next** **F102+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**. |
| 2026-03-22 | Gate **F100** — **`execute_ast`** **`listen|…|emit|inner`** stub (**`p0_semantic_execute_ast_listen_emit_stub.azl`**; exits **401–403**, **P0exectreelistenemit**). Parity range docs now **F2–F100**; **Open next** **F101+** in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**. |
| 2026-03-21 | **P0.1 vertical-slice execution order** (phases **A–F**) in **[PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md)** § **P0.1** + checklist in **[TIER_B_BACKLOG.md](TIER_B_BACKLOG.md)**; pointers from **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**, strategic plan, **[INTEGRATION_VERIFY.md](INTEGRATION_VERIFY.md)**, **[AGENTS.md](../AGENTS.md)**. |
| 2026-03-21 | Native semantic parity **F5–F73** on fixtures (**ERROR_SYSTEM** § Native gates; **271** skipped — literal codec): through **F71** **`split_chars()` + char `for`** (**311–313**, **P0u**); **F72** **`set ::buf.push(…)`** (**314–316**, **P0push**); **F73** int **`-`** + **`.length`** (**317–319**, **P0sub**). New behavior = **`p0_semantic_*.azl`** + C + Python + **`check_azl_native_gates.sh`** + doc rows — no silent exits. |
| 2026-03-22 | Gate **F94** — **`execute_ast`** **`emit|…`** bare emit + drain (**`p0_semantic_execute_ast_emit_step.azl`**; exits **383–385**, **P0exectreeemit**). **Open next:** **`component|`** / **`emit|…|with`** / preloop — **F95+**. Cross-docs + **CHANGELOG** updated. |
| 2026-03-22 | Gate **F93** — **`::execute_ast(::ast, ::scope)`** stub (**`p0_semantic_execute_ast_tree_walk.azl`**; **`say|…`** steps in **`::ast.nodes`**; exits **380–382**, **P0exectree**). |
| 2026-03-21 | Gates **F90–F92** — **`AZL_USE_VM=1`** stub **`::vm_compile_ast`** / **`::vm_run_bytecode_program`** (**`p0_semantic_execute_vm_*.azl`**; exits **371–379**, **P0execvm**). |
| 2026-03-21 | Gate **F89** — execute **`::ast.nodes`** preloop + **`&&`**, **`for-in`** inside listener **`if`** (**`p0_semantic_execute_ast_nodes_preloop.azl`**; exits **368–370**, **P0execpre**). |
| 2026-03-21 | Gate **F88** — **`halt_execution`** listener (**`p0_semantic_halt_execution_listener.azl`**; exits **365–367**, **P0halt**). |
| 2026-03-22 | Native semantic parity **F74–F87** (tokenize + parse + execute stub): **F74–F82** tokenize (**323–349**); **F83–F85** parse (**350–358**); **F86–F87** execute payload + **`execute_complete`**, **`AZL_USE_VM`** env-off (**359–364**, **P0execpayload** / **P0usevmoff**). Gate **F87** requires **`AZL_USE_VM` unset** in native gate runner. **`make verify`** green; cross-docs + **CHANGELOG** updated. |
| 2026-03-20 | Initial continuity handoff after long alignment discussion; links strategic plan + spine + audit. |
