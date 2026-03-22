# RepertoireField, LHA3, speed, security — engineering reality vs product intent

**Audience:** Maintainers (BCBA-led vision: **RepertoireField**, **ABA-shaped learning**, **LHA3 memory**).  
**Purpose:** Map **what the repo actually does today** to **what you describe** (research-grounded novelty, extreme speed, fluency, correctness, security, “black hole” class ideas, Rust).  
**This document does not cite external papers** — it audits **code and docs in-tree only**. Claims like “first in code worldwide” need **bibliography + independent review** outside this file.

**Related:** [AZL_BCBA_NAMING_FRAME.md](AZL_BCBA_NAMING_FRAME.md) (naming), [AZL_GPU_NEURAL_SURFACE_MAP.md](AZL_GPU_NEURAL_SURFACE_MAP.md) (file map), [LLM_INFRASTRUCTURE_AUDIT.md](LLM_INFRASTRUCTURE_AUDIT.md) (LLM honesty).

---

## 1. Executive summary

| Your theme | In-repo today (honest) |
|------------|-------------------------|
| **RepertoireField** (whole situation → one outcome) | **Documented** as product language. **Most `azl/quantum/` code** is still **named** “quantum” and mixes **several different things**: textbook **state-vector gate math**, **event graphs**, **p-adic digit arithmetic**, **fractal iteration**, **narrative / demo encryption**. **Not** one unified RepertoireField implementation spec. |
| **Physics / research translated to code** | **`p_adic_processor.azl`** implements **p-adic digit expansion, add, multiply, distance** in AZL — **real discrete math**. **`fractal_memory_compression.azl`** includes a **real Mandelbrot escape-time loop** (iterative complex dynamics). **`real_quantum_processor.azl`** holds **fixed gate matrices** and a **16-amplitude state vector** — standard **numerical QC-style** layer; **not** a laboratory QPU. **No in-tree bibliography** tying modules to specific papers. |
| **LHA3 — amazing compression, internal circles, “black hole” class** | **LHA3 event graph exists** (`::memory.lha3_quantum`, `::quantum.memory.lha3_quantum_engine`). **`compaction_fractal_memory` / `quantum_engine.apply_compaction`** use **scalar formulas on counts** (e.g. `compacted_size ≈ total_items * (0.98 - 0.03 * level)`), **not** lossless/lossy **byte compression** of payloads. **`create_quantum_state` / `create_fractal_index`** are **small structured hints** derived from flags/modulo — **not** full physics or fractal analysis of data. **“Black hole”**: only **string labels** in `azme/cognitive/azme_cosmic_intelligence.azl` — **no** LHA3 / horizon / GR implementation found. |
| **Extreme speed & fluency** | **Hot paths** for default native mode remain **C minimal / Python minimal** on a **subset** — see [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md). Large `.azl` graphs are **not** all on that path. **Speed** = **profiling + native bridges + fewer round-trips** — **not** proven by LHA3 formulas alone. |
| **Correctness** | **Parity gates F2–F128** (native **`check_azl_native_gates.sh`**) prove **subset** C↔Python behavior on **fixtures only**. **`scripts/verify_azl_interpreter_semantic_spine_smoke.sh`** ( **`make verify`** step **3** ) proves the **real** **`azl/runtime/interpreter/azl_interpreter.azl`** file reaches **`init`** completion on the **Python** semantic spine when a harness **`::azl.security`** stub is prepended — **not** full **`behavior`** / interpreter semantics. **No** repo-wide proof that RepertoireField or LHA3 semantics match a written spec. |
| **Security** | **`quantum_encryption.azl`** is a **demo** (`"QE" + shift + ":" + text`); **decrypt path does not restore plaintext** from that format — **not production cryptography**. Real security needs **audited crypto**, **key management**, **threat model**. |
| **Rust libraries** | **`*.rs` count in this repository: 0.** If Rust lives **elsewhere** or was **removed**, this tree **does not** contain it. |

**Native minimal C (2026-03-22):** **`tools/azl_interpreter_minimal.c`** **`.push({ … })` → `tz|…|…|…|…`** uses a **512-byte** **`snprintf`** scratch buffer, then copies into the caller buffer (bounded by **`Var.v[256]`**), so **`gcc -Wformat-truncation`** is not raised on the row formatter; oversized escaped fields truncate consistently with Python **`minimal_runtime`** **`joined[:255]`**. Gates **F123**–**F128** (preloop + **`component|`** / **`memory|emit|…|with|…`** (incl. dual / triple rows) / memory interleave — **P0execpreilcomponentmemorysetlistenstack**, **P0execpreiltwocomponentmemorysay**, **P0execpreilthreecomponentmemorysay**, **P0execpreilcomponentmemoryemitcomponentsay**, **P0execpreilcomponentmemorydualemitcomponentsay**, **P0execpreilcomponentmemorytripleemitcomponentsay**) are documented in **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)**. Deeper spine work after **F128** is **F129+** — same doc **Open next**, plus **P0tz**, **P0execpreil**, **P0execpreilmemory**, **P0execpreilsaymemory**, **P0execpreilemitmemory**, **P0execpreilmemorylistenemitwithmulti**, **P0execpreilmemorylistenstack**, **P0execpreilsaymemorylistenstack**, **P0execpreilemitmemorylistenstack**, **P0exectreememorylisten**, **P0exectreememorylistenemitwith**, **P0exectreememorylistenemitwithmulti**, **P0exectreememorylistenstack**.

---

## 2. RepertoireField vs `azl/quantum/` contents

**Product intent (§0 of [AZL_GPU_NEURAL_SURFACE_MAP.md](AZL_GPU_NEURAL_SURFACE_MAP.md)):** whole situation → one outcome; BA-aligned; **not** lab quantum as the meaning of the word.

**Code reality:** ~37 files under `azl/quantum/` (processors, memory, mathematics, consciousness, optimizer, etc.). They **do not** share one formal “RepertoireField API.” Many files are **orthogonal concerns** (QC-style numerics, messaging names, topology scaffolds).

**Gap:** A **single technical spec** (inputs, outputs, invariants, tests) for **RepertoireField** would let you **delete or rename** misleading pieces and **keep** what truly implements your idea.

---

## 3. LHA3 — what is real vs heuristic

### 3.1 Real (concrete behavior in code)

- **Typed memory buckets** (episodic, semantic, working, …) with **store / retrieve by id**, **counters**, **engine handoff events**.
- **Explicit error emission** on invalid memory kind (`log_error` + `InvalidMemoryKind`).
- **Engine** stores **named quantum_states** records and **hyperdimensional_vectors** as **structured maps** with config (`p_adic_prime`, `precision`, …).

### 3.2 Heuristic / not byte-level compression

- **`compaction_fractal_memory`:** `compacted_size` is a **function of item count and level**, not **encoded bytes** of `payload`.
- **`quantum_engine.apply_compaction`:** `compressed_items = memory_items * effective_ratio` — **same issue** (ratio on a count).
- **Conclusion:** **“Amazing compression”** is **not yet backed** by **codec-style** compression of memory contents in these handlers. To match the story, you need **real algorithms** (e.g. transform + entropy coding) or **honest renaming** of these events to **“compaction policy / retention ratio.”**
- **Shipped honesty contract:** [LHA3_COMPRESSION_HONESTY.md](LHA3_COMPRESSION_HONESTY.md) (**`LHA3_COMPRESSION_HONESTY_CONTRACT_V1`**) + **`scripts/verify_lha3_compression_honesty_contract.sh`** (runs inside **`verify_quantum_lha3_stack.sh`**). Source markers: **`LHA3_COMPRESSION_MODEL=heuristic_retention`**.

### 3.3 “Internal circles” / black hole

- **No** implementation found under `azl/memory` or `azl/quantum` for **black-hole-like** storage or **GR-inspired** mechanics.
- **Next step if you want this:** define **one precise metaphor → math → API** (even if classical), then implement **with tests**; avoid **cosmic labels** without **measurable behavior**.

---

## 4. Fractal and p-adic (research-adjacent)

| Module | What it actually does |
|--------|------------------------|
| **`azl/memory/fractal_memory_compression.azl`** | **Mandelbrot escape iteration** in AZL; builds **indices / maps** — **real iterative math**; not automatically “best compression in the world” without measuring on data. |
| **`azl/quantum/processor/p_adic_processor.azl`** | **p-adic** digit representation, **add**, **multiply**, **distance** — **legitimate p-adic arithmetic** in AZL for the implemented prime/precision. |
| **`azl/quantum/real_quantum_processor.azl`** | **4-qubit** complex state vector + **H, X, Z, CNOT** matrices; **FFI** hooks to external numerics — **QC pedagogy / numerical layer** in software. |

**Research claim process:** For each module you believe is **novel**, add **`docs/research/…`** with **citation**, **what you implemented**, **what you did not**, and **tests** that would **fail** if the math regressed.

---

## 5. Security (must not be overstated)

- **`quantum_encryption.azl`:** **Not** a secure cipher — **`security_tier: DEMO_NON_CRYPTO`** on ready/complete; decrypt is **rejected** with **`quantum.encryption.failed`**. **Do not** present as **quantum-safe** or **production** crypto.
- **Superiority** in security requires: **threat model**, **audited primitives** (e.g. libsodium / OS APIs), **key rotation**, **constant-time** where needed, **capabilities** honesty on [native HTTP](docs/LLM_INFRASTRUCTURE_AUDIT.md).

---

## 6. Rust

- **This repository:** **no Rust source files** were found (`**/*.rs` glob empty).
- If Rust is part of your story, either **bring it into this repo** with **build + tests**, or **link** the **exact** external crate/repo in docs.

---

## 7. Recommended work order (ties your vision to engineering)

1. **RepertoireField spec** — one markdown spec + **3–5 integration tests** that define success.  
2. **LHA3 honesty pass** — **done (contract + CI + API rename):** [LHA3_COMPRESSION_HONESTY.md](LHA3_COMPRESSION_HONESTY.md) + verify script; primary events renamed **`compaction_*`** / **`quantum_engine.apply_compaction`** (breaking vs legacy `compress_*`).  
3. **Crypto** — **done for `quantum_encryption.azl`:** **`DEMO_NON_CRYPTO`** labeling + **`quantum.encryption.failed`** on decrypt; further work = real audited primitives or remove from enterprise bundle.  
4. **Black hole / exotic** — **define behavior** numerically or drop label until defined.  
5. **Bibliography** — for each “research says” claim, **paper + mapping to function names**.  
6. **Performance** — **benchmarks** on paths you care about (native engine, bundle size, hot handlers), not only **say** lines.

---

## 8. Error / policy alignment

- Prefer **explicit `log_error` / contract errors** over **silent “success: true”** when work is heuristic.  
- Extend [ERROR_SYSTEM.md](ERROR_SYSTEM.md) when new **LHA3 / RepertoireField** gates are added.
