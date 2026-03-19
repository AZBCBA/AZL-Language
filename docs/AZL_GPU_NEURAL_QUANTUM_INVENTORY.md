# GPU, neural, memory & quantum — capability inventory

**Purpose:** Map what exists in `azl/` that relates to **GPU**, **VRAM**, **large LLMs**, **memory/LHA3**, and **quantum**—including pieces that are **easy to miss** because they are not on the default native enterprise runtime path. This complements [DEEP_AUDIT_QUANTUM_MEMORY_PHYSICS.md](DEEP_AUDIT_QUANTUM_MEMORY_PHYSICS.md) (truth table for quantum/LHA3 math) and [LLM_INFRASTRUCTURE_AUDIT.md](LLM_INFRASTRUCTURE_AUDIT.md) (HTTP/Ollama/native GGUF honesty).

**Regenerate / verify listing:** `bash scripts/audit_gpu_neural_quantum_surfaces.sh`

---

## 1. Critical context (read first)

| Fact | Implication |
|------|-------------|
| Default native mode runs **C minimal** or **Python semantic subset** on the **combined** bundle | Most `.azl` files below are **not executed** on that path unless linked into the bundle **and** reached by a full interpreter. |
| **No CUDA/Metal/OpenCL kernel bridge** in-tree for AZL tensors today | `device: "cuda"` in APIs is mostly **configuration + orchestration shape** until a native FFI path exists. |
| **Native GGUF** | Explicitly **not** implemented — `neural.model_loader` emits `ERR_NATIVE_GGUF_NOT_IMPLEMENTED`; use Ollama proxy per capabilities endpoint. |
| **“Quantum” in file names** | Often **state-vector / symbolic / event** models on a **normal CPU** — not a lab QPU unless you add hardware integration. |

---

## 2. GPU / device / VRAM (AZL surface)

| Location | Role | Binding to real GPU? |
|----------|------|------------------------|
| `azl/api/endpoints.azl` | `device` / `cuda` / `gpu_limit` / `num_gpus` validation, training toggles | **Config & policy**; no device kernels here |
| `azl/orchestrator/parallel_training_orchestrator.azl` | Multi-GPU orchestration narrative, `per_device` metrics | **Logical** scheduling shape |
| `azl/orchestrator/comprehensive_training_controller.azl` | Default `device: "cpu"` | Baseline |
| `azl/system/http_server.azl` | Training config JSON includes `device`, `gpu_limit` | **API shape** |
| `azl/nlp/advanced_training_system.azl` | Training pipeline; comment on quantum vs GPU exhaustion | **Mixed** training + quantum hooks |
| `azl/neural/qwen_72b_quantum_attention.azl` | Large-model naming + attention story | **Not** a loaded 72B weights implementation in-repo |
| `azl/quantum/processor/quantum_behavior_modeling.azl` | References `gpu_available` in runtime env | **Flag / say path** unless wired to host probe |
| `azl/ffi/torch.azl` | Optional **Torch FFI** bridge (`AZL_ENABLE_TORCH_FFI`); default `::device = "cuda"` in **data** | **Not** the native C engine; requires external Python/torch helper when enabled |
| `azl/system/hw.azl` | Hardware / capability hints | Check file for env-driven behavior |

**Gap (documented):** [DEEP_AUDIT §4](DEEP_AUDIT_QUANTUM_MEMORY_PHYSICS.md) — native tensor is pure AZL; **GPU/tensor bridge** is future work.

---

## 3. Neural / LLM (AZL surface)

| Location | Role | “Full logic”? |
|----------|------|----------------|
| `azl/neural/model_loader.azl` | Loads quantum/real/qwen paths via events; **`load_gguf_native` → hard error** | **Honest** stub for native GGUF |
| `azl/neural/*.azl` | Various model / attention scaffolding | **Per-file**; many are **event graphs**, not shipped inference |
| `docs/LLM_INFRASTRUCTURE_AUDIT.md` | Native engine proxy vs GGUF | **Source of truth** for HTTP path |

---

## 4. Memory / LHA3 / fractal

| Location | Role | See |
|----------|------|-----|
| `azl/memory/lha3_quantum_memory.azl` | LHA3 memory types, store/retrieve | [DEEP_AUDIT §1.2](DEEP_AUDIT_QUANTUM_MEMORY_PHYSICS.md) |
| `azl/memory/lha3_memory_system.azl` | LHA3 system facade | Same |
| `azl/quantum/memory/lha3_quantum_engine.azl` | Engine stats, compression ratio | Same |
| `azl/memory/fractal_memory_compression.azl` | Mandelbrot/Julia / box-counting | Real iterative math in AZL |
| `azl/runtime/memory/lha3_memory_system.azl` | Runtime integration | Audit note on try/catch |

---

## 5. Quantum processors & mathematics (selected)

| Path | Note |
|------|------|
| `azl/quantum/real_quantum_processor.azl` | **State-vector simulation** + gates (numbers in arrays); **not** a physical QPU. |
| `azl/ffi/math_engine.azl` | Pure AZL linear algebra / softmax / “quantum_gate” events | **Software** math |
| `azl/quantum/processor/p_adic_processor.azl` | p-adic arithmetic events | Audited as implemented |
| `azl/quantum/memory/quantum_entanglement_network.azl` | Protocols as **symbolic** structures | Not physical qubits |
| `azl/quantum/mathematics/*.azl` | Topology / geometry / algebra **stacks** | **Per-file** audit still open (DEEP_AUDIT §4.2) |
| `azl/quantum/processor/quantum_behavior_modeling.azl` | Very large surface | Treat as **library**; spot-check before claiming behavior |

**Tests:** `azl/testing/quantum/*`, `azl/testing/integration/test_quantum_neural_integration.azl` — run only when a runner loads them; not implied by `run_all_tests.sh` alone unless wired.

---

## 6. Placeholders vs production language

- Repo gate **`scripts/check_no_placeholders.sh`** scans `.azl` / `.rs` for `TODO|FIXME|placeholder` (case insensitive).
- **“Not full logic”** is often **absence of host binding** (GPU, GGUF) or **unexecuted** modules—not necessarily the word “placeholder.”
- Prefer **explicit errors** (e.g. `load_gguf_native`) over silent success when a capability is missing.

---

## 7. Suggested next audits (one by one)

1. Pick one file under `azl/quantum/mathematics/` → read top + `behavior` → update this doc with a **one-line verdict** (implemented / partial / scaffold).
2. Trace `AZL_DEVICE` / `AZL_HAS_GPU` from `::internal.env` to any **C** or **sysproxy** consumer (today: mostly AZL-only).
3. Prototype **one** GPU bridge design doc (no code) options: CUDA FFI vs external process vs Ollama-only.

---

## Related docs

| Doc | Use |
|-----|-----|
| [DEEP_AUDIT_QUANTUM_MEMORY_PHYSICS.md](DEEP_AUDIT_QUANTUM_MEMORY_PHYSICS.md) | Real vs symbolic quantum/memory |
| [LLM_INFRASTRUCTURE_AUDIT.md](LLM_INFRASTRUCTURE_AUDIT.md) | Native LLM HTTP honesty |
| [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md) | What actually runs on default native path |
| [PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md) | P0–P5 gaps |
