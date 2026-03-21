# GPU, neural, LHA3 & RepertoireField modules — surface map

**Purpose:** Map what exists in `azl/` for **GPU / device policy**, **LLM & neural orchestration**, **LHA3 memory** (name TBD — see [AZL_BCBA_NAMING_FRAME.md](AZL_BCBA_NAMING_FRAME.md)), and the libraries historically under **`azl/quantum/`** (**RepertoireField** in public language) — including files that are easy to miss because they are **not** on the default minimal native child path.

**Regenerate / verify listing:** `bash scripts/audit_gpu_neural_quantum_surfaces.sh`

**Related:** [LLM_INFRASTRUCTURE_AUDIT.md](LLM_INFRASTRUCTURE_AUDIT.md) (HTTP / Ollama / GGUF honesty), [LHA3_STDLIB_API.md](LHA3_STDLIB_API.md), [LHA3_COMPRESSION_HONESTY.md](LHA3_COMPRESSION_HONESTY.md) (**compaction** events = heuristic retention, not byte codec), [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md), [AZL_ENGINEERING_REALITY_AUDIT.md](AZL_ENGINEERING_REALITY_AUDIT.md) (what the code actually does vs product story).

---

## 0. RepertoireField (public name) — legacy path `azl/quantum/`

**Surface contract (verified in CI):** `REPERTOIREFIELD_SURFACE_CONTRACT_V1`

**Product name (chosen):** **RepertoireField** — the subsystem where the program holds the **whole situation**, then **commits to one outcome** (see [AZL_BCBA_NAMING_FRAME.md](AZL_BCBA_NAMING_FRAME.md)). In behavior analysis, a **repertoire** is the set of behaviors available; the **field** is the **whole active set** at once. **Real software** on normal CPUs/GPUs — **not** laboratory quantum computing and **not** “pretend physics.”

**Legacy in repo:** folders and components often still say **quantum** (e.g. **`azl/quantum/`**). That is a **path name**, not a claim about hardware. When a rename milestone lands, **`azl/repertoire_field/`** (or similar) can replace it — **meaning unchanged**.

**Also-approved names** for sub-features or docs (same idea): ContingencyGraph, Synoptic, Nexus, Confluence — see [AZL_BCBA_NAMING_FRAME.md](AZL_BCBA_NAMING_FRAME.md) §2.

---

## 1. Runtime context

| Fact | Implication |
|------|-------------|
| Default native mode often runs a **minimal** child (C or Python subset) on the **combined** bundle | Many modules below are **not executed** on that path unless they are in the bundle **and** reached by the runner you use. |
| **No CUDA / Metal / OpenCL kernel bridge** in-tree for arbitrary AZL-defined tensor ops today | `device: "cuda"` in APIs is mostly **configuration and orchestration shape** until a native FFI path exists. |
| **Native GGUF** | **`POST /api/llm/gguf_infer`** + **`AZL_GGUF_PATH`** — see [LLM_INFRASTRUCTURE_AUDIT.md](LLM_INFRASTRUCTURE_AUDIT.md). |

---

## 2. GPU / device / VRAM (AZL surface)

| Location | Role | Binding to GPU? |
|----------|------|-----------------|
| `azl/api/endpoints.azl` | `device` / `cuda` / `gpu_limit` / `num_gpus` validation, training toggles | **Config & policy**; no device kernels here |
| `azl/core/neural/neural.azl` | **`neural.core.configure_device`**, **`initialize_neural`**, **`neural.llm.native_infer_gpu_hint`** | Training **policy** + **hint** for native-engine LLM env (§2.1); not llama.cpp itself |
| `azl/orchestrator/parallel_training_orchestrator.azl` | Multi-GPU orchestration narrative, `per_device` metrics | **Logical** scheduling shape |
| `azl/orchestrator/comprehensive_training_controller.azl` | Default `device: "cpu"` | Baseline |
| `azl/system/http_server.azl` | Training config JSON includes `device`, `gpu_limit` | **API shape** |
| `azl/nlp/advanced_training_system.azl` | Training pipeline; ties to RepertoireField / `azl/quantum/` hooks where linked | **Mixed** surface |
| `azl/neural/qwen_72b_quantum_attention.azl` | Large-model naming + attention story | **Naming / graph**; not a full in-repo 72B weights implementation |
| `azl/quantum/processor/quantum_behavior_modeling.azl` | Uses runtime env flags where present | **Event / env path** unless host fills values |
| `azl/ffi/torch.azl` | Optional **Torch FFI** (`AZL_ENABLE_TORCH_FFI`); default `::device = "cuda"` in **data** | Requires external Python/torch helper when enabled |
| `azl/system/hw.azl` | Hardware / capability hints | See file for env-driven behavior |

**Gap:** native tensor in pure AZL; **GPU/tensor bridge** for arbitrary AZL-defined ops is **future work** (design + native layer).

### 2.1 LLM inference GPU (native `azl-native-engine`, llama.cpp)

Orchestration `.azl` surfaces (`device: "cuda"`, **`AZL_HAS_GPU`**, parallel training) describe **training / policy shape** and **Torch FFI** — they do **not** automatically reconfigure the C engine. For **whatever GGUF** you point at, **GPU offload is llama.cpp’s job**:

| Mechanism | Role |
|-----------|------|
| **`AZL_LLAMA_NGL`** or **`AZL_LLM_GPU_LAYERS`** | Passed to llama.cpp as **`n_gpu_layers`** (embedded build) or **`-ngl`** on **`llama-cli`** (subprocess). **`AZL_LLM_GPU_LAYERS`** is a model-agnostic alias. |
| **`GET /api/llm/capabilities`** | Reports **`llm_n_gpu_layers`**, **`llm_n_gpu_layers_env_set`**, **`llm_gpu_stack`**. |
| **`::neural.core`** event **`neural.llm.native_infer_gpu_hint`** | Echoes host-seeded **`::internal.env`** after **`exec_bridge`** **`merge_host_env_into_internal`**. |
| **Build** | llama.cpp must be compiled with the relevant **CUDA / Vulkan / Metal** backend for layers to apply. |

---

## 3. Neural / LLM (AZL surface)

| Location | Role |
|----------|------|
| `azl/neural/model_loader.azl` | Model paths via events; **`load_gguf_native`** surfaces explicit errors when misused |
| `azl/neural/*.azl` | Model / attention / orchestration graphs |
| [LLM_INFRASTRUCTURE_AUDIT.md](LLM_INFRASTRUCTURE_AUDIT.md) | Native engine proxy vs GGUF — **source of truth** for HTTP path |

---

## 4. Memory / LHA3 / fractal

| Location | Role |
|----------|------|
| `azl/memory/lha3_quantum_memory.azl` | LHA3 memory types, store/retrieve |
| `azl/memory/lha3_memory_system.azl` | LHA3 system facade |
| `azl/quantum/memory/lha3_quantum_engine.azl` | Engine stats; **“compression”** = **heuristic ratio × item counts** ([LHA3_COMPRESSION_HONESTY.md](LHA3_COMPRESSION_HONESTY.md)) |
| `azl/memory/fractal_memory_compression.azl` | Mandelbrot/Julia / box-counting — iterative math in AZL |
| `azl/runtime/memory/lha3_memory_system.azl` | Runtime integration |

API summary: [LHA3_STDLIB_API.md](LHA3_STDLIB_API.md).

---

## 5. RepertoireField processors & mathematics (`azl/quantum/` — selected)

These paths implement **RepertoireField** reasoning and math **in software** (see §0).

| Path | Note |
|------|------|
| `azl/quantum/real_quantum_processor.azl` | Vectors, gates, and state evolution in AZL — **RepertoireField engine** (legacy path name) |
| `azl/ffi/math_engine.azl` | Linear algebra / softmax / gate-style events |
| `azl/quantum/processor/p_adic_processor.azl` | p-adic arithmetic events |
| `azl/quantum/memory/quantum_entanglement_network.azl` | Multi-part protocol composition |
| `azl/quantum/processor/quantum_behavior_modeling.azl` | Large surface — treat as **library**; validate before product claims |
| `azl/quantum/mathematics/*.azl` | Topology / geometry / algebra / chaos — **per-file** behavior in source |

**Tests:** `azl/testing/quantum/*`, `azl/testing/integration/test_quantum_neural_integration.azl` — run when your runner loads them.

### 5.1 Mathematics stack (`azl/quantum/mathematics/`) — file index

| File | Component (typical) | Role (short) |
|------|---------------------|--------------|
| `advanced_topology.azl` | `::quantum.mathematics.advanced_topology` | Topology / persistence-style outputs |
| `quantum_topology.azl` | `::quantum.mathematics.topological_intelligence` | Homology-style helpers |
| `quantum_integrator.azl` | `::quantum.mathematics.integrator` | Unifies framework names |
| `quantum_geometry.azl` | `::quantum.mathematics.geometric_structures` | Manifold / axiom flow |
| `quantum_chaos.azl` | `::quantum.mathematics.chaos_theory` | Attractor stepping; read file for metric details |
| `quantum_category.azl` | `::quantum.mathematics.category_theory` | Categorical scaffolding |
| `quantum_algebra.azl` | `::quantum.mathematics.algebraic_structures` | Algebraic scaffolding |

**Filename note:** `quantum_math.azl` was renamed to `advanced_topology.azl` (2026-03-19) to match `::quantum.mathematics.advanced_topology`.

---

## 6. Placeholders and explicit errors

- **`scripts/check_no_placeholders.sh`** scans `.azl` / `.rs` for `TODO|FIXME|placeholder` (case insensitive).
- Prefer **explicit errors** (e.g. `load_gguf_native`) over silent success when a capability is missing.

---

## 7. Suggested follow-ups

1. Trace `AZL_DEVICE` / `AZL_HAS_GPU` from `::internal.env` to **C** or **sysproxy** consumers.
2. Prototype **one** GPU bridge design (options: CUDA FFI vs external process vs Ollama-only).
