# AZL strategic consensus & execution plan

**Purpose:** Preserve **vision + engineering agreement** from maintainer discussions so work does not drift. This doc is the **strategic** complement to **[PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md)** (spine/P0–P5 depth) and **[RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)** (what is true today on the native path).

**Continuity for AI/humans (read first in a new session):** [AI_MAINTAINER_CONTINUITY_HANDOFF.md](AI_MAINTAINER_CONTINUITY_HANDOFF.md). **Repo root:** [../AGENTS.md](../AGENTS.md). **Cursor:** `.cursor/rules/azl-continuity.mdc` (**alwaysApply**).

**How to use:** Before starting a new initiative, check **§ Consensus** and **§ Phases**. When scope changes, **edit this file** and cross-link gates in **[ERROR_SYSTEM.md](ERROR_SYSTEM.md)** and verification scripts (native parity **`scripts/check_azl_native_gates.sh`** through **F2–F161** on **`azl/tests/p0_semantic_*.azl`** as of 2026-03-22). **Semantic spine sequencing** (vertical slices toward self-host, not feature sprawl): **[PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md)** § **P0.1 — Long-term execution order** + **[TIER_B_BACKLOG.md](TIER_B_BACKLOG.md)** § **P0.1 execution checklist** + § **P0.1 — Semantic / runtime gaps** (narrow claims vs **Phase F**).

**Last updated:** 2026-03-21

---

## 1. Consensus (what we agreed)

### 1.1 North star

- **AZL is the product:** the language users think in; not Python-shaped as the long-term center.
- **Speed means real outcomes:** wall time, throughput, VRAM/IO — not cutting engineering corners.
- **Primary technical backbone:** **native codegen / AOT-style path** (LLVM or equivalent) is the main performance story; a VM/interpreter may exist for dev or subsets, but **must not be the only headline** if the goal is “direct on CPU/GPU.”
- **Bootstrap is honest:** a **small native entry** (driver) may load/compile/run AZL first; **more logic moves into AZL over time** via bootstrapping. The OS still loads **machine code** first — `.azl` is not the OS executable format.
- **Self-hosting remains the project:** “AZL written in AZL” is **the same roadmap** as codegen, **staged** — not a competing fairy tale. Narrative in `.azl` files must stay aligned with **process traces** (see roadmap).

### 1.2 Scale, memory, and compression (vision vs proof)

- **Vision:** challenge legacy assumptions where useful — dense weights, flat byte memory, generic compression, separation of training vs storage — as **research wedges**, not vibes.
- **Artifact policy:** **different invariants** for different things:
  - **Exact / reproducible** → **lossless literal** codec + **framing + versioning + checksums** + **[ERROR_SYSTEM.md](ERROR_SYSTEM.md)** (corrupt input, version mismatch = **defined errors**, never silent wrong output).
  - **Serving / scale** → **lossy + structural** paths (quantization, sparsity, MoE-style routing, distillation, task-native rate–distortion) — **measured** quality, not byte-identical claims.
  - **Semantic / LHA3** → **what exists** as state (repertoire, indices, policy) — may **reduce what becomes bytes**; must stay **honest** vs **[LHA3_COMPRESSION_HONESTY.md](LHA3_COMPRESSION_HONESTY.md)** where heuristic retention was named explicitly.
- **User-facing interface can be unified:** one CLI/API with **modes** (`Exact | Serving | Semantic`, or equivalent) — **one door**, multiple **behaviors**; physics does not force one internal algorithm for all goals.

### 1.3 Tests vs language

- **Harness is not the language:** verification lives **outside** the language definition; **policy** + **documented entry** (how AZL is invoked, exit codes, error shape) is the **contract** between harness and runtime.

### 1.4 Shipping shape

- **CLI / install-from-GitHub** is the serious default — not desktop-first.

### 1.5 Research partnership mode

- **Vision** proposes axioms to break; **engineering** supplies mechanisms, **crucial experiments**, and **failure modes**.
- **“Better than the stack ML assumed”** is pursued via **hypothesis → metric → minimal experiment**, not by skipping measurement.

### 1.6 Honesty line (one sentence, not a loop)

- **Lossless** byte compression cannot beat **information content** of **high-entropy** payloads; **extreme** LM-scale wins come from **changing what is stored**, **lossy/structured weights**, and **execution** — AZL’s **control plane** (policy + IR + targets) is where **novelty** compounds. **Do not** market literal codecs as doing more than tests prove.

---

## 2. Locked vocabulary (avoid drift)

| Term | Meaning |
|------|---------|
| **Driver** | Small native binary that loads/compiles/runs AZL; bootstrap until self-host is proven. |
| **Literal codec** | Byte-exact compress/decompress path with **round-trip proof** on a corpus + **explicit errors**. |
| **Serving path** | Lossy or structured representation optimized for **run cost**; **quality metrics** required. |
| **Semantic layer** | LHA3 / repertoire / AZL-native memory **policy** — not automatically a byte codec. |
| **Wedge** | One assumption cluster to attack with a **defined experiment** (§5). |

---

## 3. Phases (what to do in order — strategic layer)

Phases **overlap in calendar time** where safe; **merge gates** remain strict for anything labeled **Exact/literal**.

### Phase 0 — Freeze the story (1–2 sessions)

**Deliverables**

- This doc committed; **link** from [PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md) (done when merged).
- One **CLI / entry** paragraph in **[AZL_NATIVE_RUNTIME_CONTRACT.md](AZL_NATIVE_RUNTIME_CONTRACT.md)** or **[RELEASE_READY.md](../RELEASE_READY.md)** — whichever is the install truth today — stating: **native driver + documented env/spine**.

**Verification**

- Doc links resolve; no contradictory “pure AZL replaces Rust” claims **without** matching process trace (see [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md)).

### Phase 1 — Truth core (literal + errors)

**Deliverables**

- **Container spec v0 (normative):** [AZL_LITERAL_CODEC_CONTAINER_V0.md](AZL_LITERAL_CODEC_CONTAINER_V0.md) — magic, `kind`, `codec_id`, `format_version`, CRC-32C, payload layout; doc contract **`AZL_LITERAL_CODEC_CONTAINER_CONTRACT_V1`** verified by **`scripts/verify_azl_literal_codec_container_doc_contract.sh`** (exits **250–254**, [ERROR_SYSTEM.md](ERROR_SYSTEM.md)).
- **CPU reference** encoder/decoder for **one** `kind` (e.g. opaque blob or tensor slice) with **CODEC_*` errors per [ERROR_SYSTEM.md](ERROR_SYSTEM.md)** taxonomy extension if needed.
- **Corpus + round-trip** automation in **harness** (not inside language grammar): compress → decompress → **byte equality**; corrupt/truncated → **defined failure**.

**Verification**

- Harness script exits non-zero on failure; **`scripts/verify_azl_literal_codec_roundtrip.sh`** runs in **`scripts/run_tests.sh`** (identity **`codec_id=0`** + negative cases). Doc contract: **`verify_azl_literal_codec_container_doc_contract.sh`**.

**Parallel track (optional same phase):** begin **IR / codegen skeleton** only if it does not block Phase 1 proof.

### Phase 2 — Serving / scale path

**Deliverables**

- **Serving** artifact format + **quality suite** (tasks relevant to AZL — not generic ML leaderboard unless chosen).
- Quantization or structured-weight **policy** documented; **no silent** quality regression — explicit metrics + errors.

**Verification**

- Thresholds checked in harness; failures are **named**, not “best effort.”

### Phase 3 — LHA3 integration (semantic + literal boundaries)

**Deliverables**

- Map **memory kinds** to **artifact kinds** (what is Exact vs Serving vs semantic-only).
- Update or extend **[LHA3_COMPRESSION_HONESTY.md](LHA3_COMPRESSION_HONESTY.md)** if new **literal** behavior replaces heuristic-only paths.

**Verification**

- Contract scripts already in tree (`scripts/verify_lha3_compression_honesty_contract.sh`, etc.) stay green or are **intentionally** revised with changelog entry.

### Phase 4 — Execution wedge (make AZL faster)

**Deliverables**

- **AOT/native** path milestones per [PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md) + compiler notes; AZL **owns** placement, precision, fusion policy in **IR** as product differentiator.
- GPU acceleration **after** CPU correctness for **literal** paths; GPU for **compute** can follow product priority.

**Verification**

- Benchmarks and/or smoke scripts documented; results not claimed beyond what was run.

### Phase 5 — Self-host milestone (same project, later gate)

**Deliverables**

- AZL compiler/runtime **sources** in AZL, **compiled** by bootstrap toolchain to **native** `azlc`/driver; **cross-check** vs previous stage.

**Verification**

- Bootstrap recipe + **failure** if byte-identical or semantic checks fail.

---

## 4. Three research wedges (depth without losing focus)

Attack **one wedge deeply** at a time; others proceed in parallel only with **separate owners** or **time-boxing**.

| ID | Wedge | Question | Success signal |
|----|--------|----------|----------------|
| **W1** | Execution | Can AZL IR express fusion/placement/precision so wall-clock beats legacy glue? | Measured latency/throughput vs baseline |
| **W2** | Memory semantics | Can LHA3 policy reduce **materialized** bytes without breaking required exactness? | Storage + task metrics under fixed policy |
| **W3** | Parameterization | Do structured weights + routing shrink **active** compute / VRAM at same quality? | Pareto vs dense baseline |

Each wedge requires a **one-sentence hypothesis** and a **minimal experiment** before expanding scope.

---

## 5. What we are explicitly not doing in this doc

- Replacing **[PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md)** P0 spine tasks — this doc **strategic**; that doc **execution queue**.
- Promising **unproven** compression ratios — **proof** lives in harness + **CHANGELOG** / honesty contracts.

---

## 6. Related documents

| Doc | Role |
|-----|------|
| [PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md) | P0–P5 spine, gates, backlog IDs |
| [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md) | Current native trace truth |
| [ERROR_SYSTEM.md](ERROR_SYSTEM.md) | Mandatory error behavior |
| [LHA3_COMPRESSION_HONESTY.md](LHA3_COMPRESSION_HONESTY.md) | Heuristic vs literal honesty |
| [AZL_ENGINEERING_REALITY_AUDIT.md](AZL_ENGINEERING_REALITY_AUDIT.md) | Code vs narrative audit |
| [AZL_PERFECTION_PLAN.md](AZL_PERFECTION_PLAN.md) | Older strategic draft — reconcile or deprecate sections that contradict this consensus |

---

## 7. Changelog (this file only)

| Date | Change |
|------|--------|
| 2026-03-20 | Initial consensus + phased plan from maintainer alignment discussion. |
