# LHA3 “compression” — honesty contract (AZL)

**Audience:** Anyone integrating, benchmarking, or marketing LHA3 memory.  
**Purpose:** State **exactly** what in-tree LHA3 code does when names referred to **compress** / **compression_ratio**, so docs and tests do not imply **byte codecs** where none exist. **Event names** now use **compaction** for the primary heuristic path (breaking rename from legacy `compress_*`).

**Contract version (verified in CI):** `LHA3_COMPRESSION_HONESTY_CONTRACT_V1`

**Related:** [AZL_ENGINEERING_REALITY_AUDIT.md](AZL_ENGINEERING_REALITY_AUDIT.md) §3, [LHA3_STDLIB_API.md](LHA3_STDLIB_API.md), [ERROR_SYSTEM.md](ERROR_SYSTEM.md) § LHA3 compression honesty contract.

---

## 1. What “compaction” is **not** (in the primary LHA3 engine path)

In **`::quantum.memory.lha3_quantum_engine`** (`quantum_engine.apply_compaction`) and **`::memory.lha3_quantum`** (`compaction_fractal_memory` → engine):

- **Not** lossless or lossy **encoding of payload bytes** (no gzip-/LZ-style codec over stored data).
- **Not** a guarantee that **less information** is preserved bit-for-bit; ratios are **scalar policy math** on **counts** and **config**, not measured entropy of contents.

If you need **real compression** of blobs, use an explicit **codec** component and document **format + reversibility**; do not overload these events without renaming.

---

## 2. What the code **actually** does (primary path)

| Location | Behavior |
|----------|----------|
| `azl/quantum/memory/lha3_quantum_engine.azl` — `quantum_engine.apply_compaction` | Takes `memory_items` and `level`. Sets `compressed_items = memory_items * effective_ratio` where `effective_ratio` is clamped from **`config.target_compression_ratio`** (default-ish **0.85**). Emits **`quantum_engine.compaction_applied`** with **ratio** and **item counts** — **heuristic retention / bookkeeping**, not byte compression. |
| `azl/memory/lha3_quantum_memory.azl` — `compaction_fractal_memory` | Sums **memory type counters**, forwards to the engine, then builds **`compaction_result`** where **`compacted_size`** is **`total_items * (0.98 - 0.03 * level)`** — again a **formula on counts**, not encoded payload size. Emits **`memory.lha3.compaction_applied`**. |

**Honest names for this behavior:** **compaction** / **retention ratio** — not “codec compression” unless you add a real codec.

---

## 3. Other modules (do not confuse with §2)

- **`azl/memory/fractal_memory_compression.azl`** — Uses **Mandelbrot / box-counting**-style math and can compute **`compressed_size / original_size`** from **its own size fields** in that module. That is **still not** a general-purpose byte codec for arbitrary AZL memory payloads unless separately specified and tested.
- **`azl/runtime/memory/lha3_memory_system.azl`** — **`apply_quantum_compression`** filters amplitudes/phases by thresholds; **ratio** is **length ratio** of those arrays — **structural pruning**, not a standard compression algorithm on opaque bytes.

Each path should be **documented and tested on its own**; do not merge claims across paths.

---

## 4. Product language

- **OK:** “LHA3 applies **heuristic compaction metrics**,” “**policy ratio** on item counts,” “**demo / experimental** memory shaping.”
- **Avoid without proof:** “Amazing **compression**” implying **byte-level** or **information-theoretic** guarantees on **stored payloads**.

---

## 5. Verification

- **`scripts/verify_lha3_compression_honesty_contract.sh`** — fails the build if this doc, the contract anchor, or **implementation markers** (`LHA3_COMPRESSION_MODEL=heuristic_retention`) drift.
- Invoked from **`scripts/verify_quantum_lha3_stack.sh`** and promoted **doc pieces** (**`make verify`** step 0).

---

## 6. Error system

Failures use **`ERROR[LHA3_COMPRESSION_HONESTY]:`** on stderr and exits **220–225** — see [ERROR_SYSTEM.md](ERROR_SYSTEM.md).
