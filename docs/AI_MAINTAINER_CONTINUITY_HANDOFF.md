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
| 2026-03-21 | **P0.1 vertical-slice execution order** (phases **A–F**) in **[PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md)** § **P0.1** + checklist in **[TIER_B_BACKLOG.md](TIER_B_BACKLOG.md)**; pointers from **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**, strategic plan, **[INTEGRATION_VERIFY.md](INTEGRATION_VERIFY.md)**, **[AGENTS.md](../AGENTS.md)**. |
| 2026-03-21 | Native semantic parity **F5–F73** on fixtures (**ERROR_SYSTEM** § Native gates; **271** skipped — literal codec): through **F71** **`split_chars()` + char `for`** (**311–313**, **P0u**); **F72** **`set ::buf.push(…)`** (**314–316**, **P0push**); **F73** int **`-`** + **`.length`** (**317–319**, **P0sub**). New behavior = **`p0_semantic_*.azl`** + C + Python + **`check_azl_native_gates.sh`** + doc rows — no silent exits. |
| 2026-03-22 | Native semantic parity **F74–F87** (tokenize + parse + execute stub): **F74–F82** tokenize (**323–349**); **F83–F85** parse (**350–358**); **F86–F87** execute payload + **`execute_complete`**, **`AZL_USE_VM`** env-off (**359–364**, **P0execpayload** / **P0usevmoff**). **Open next:** halt / **`ast.nodes`** loop / VM (**F88+**). Gate **F87** requires **`AZL_USE_VM` unset** in native gate runner. **`make verify`** green; cross-docs + **CHANGELOG** updated. |
| 2026-03-20 | Initial continuity handoff after long alignment discussion; links strategic plan + spine + audit. |
