# LLM Infrastructure Audit

**Purpose:** What exists for running LLMs in AZL vs what's missing. Created vs not created.

---

## 1. Model Loading (GGUF, ONNX, Safetensors)

| Format | Created? | Location | Notes |
|--------|----------|----------|-------|
| **GGUF** | ❌ No | — | No loader. Ollama uses GGUF internally; AZL does not. |
| **ONNX** | ❌ No | — | No ONNX runtime bridge. |
| **Safetensors** | ❌ No | — | No loader. |
| **PyTorch .pt** | ⚠️ Via FFI | `azl/ffi/torch.azl` | Spawns Python `mini_llm_train.py`; training only, not inference. |

**Conclusion:** No native model loading. All inference is via external services (Ollama HTTP API).

---

## 2. Inference Paths

| Path | Created? | How it works |
|------|----------|--------------|
| **Ollama HTTP** | ✅ Yes | `azme_bridge.azl`, `azme_anythingllm_provider.azl` call `http_post(ollama + "/api/generate", ...)` |
| **FFI Torch** | ✅ Yes | Spawns Python for training; no inference. |
| **Quantum byte processor** | ⚠️ Symbolic | Hardcoded response; not real LLM. |
| **Neural core** | ⚠️ Scaffolding | `load_model` stores config; no weights, no forward pass. |

**Ollama integration:** Uses `http_get`/`http_post` from host runtime. The pure AZL stdlib `http_get`/`http_post` are **simulated** (no real network). The integrations (`azme_bridge`, etc.) use JavaScript/TypeScript syntax (`class`, `http_get`) — likely run in a host that provides real HTTP.

---

## 3. Real HTTP in AZL

| Component | Real HTTP? | Notes |
|-----------|------------|-------|
| `azl/stdlib/core/azl_stdlib.azl` | ❌ No | `http_store`; localhost returns "OK: url" |
| `azl/ffi/http.azl` | ❌ No | Caches in `http_store`; no network |
| **sysproxy** | ❌ No | Sockets (listen/accept/read/write); no HTTP client |
| **C engine** | ❌ No | Serves HTTP; does not make outbound HTTP |

**Conclusion:** AZL cannot make real HTTP requests to Ollama in pure/native mode. Ollama integration exists only in host-backed runtimes (AnythingLLM, JS bridge).

---

## 4. What Needs to Be Created

### 4.1 For Native AZL → Ollama

1. **Ollama proxy in C engine** — Add `POST /api/ollama/generate` that forwards to `http://127.0.0.1:11434/api/generate` (via libcurl or `popen`+curl).
2. **Or:** Extend sysproxy with `http_client` op that performs GET/POST to a URL.

### 4.2 For Native LLM Inference (no Ollama)

1. **GGUF loader** — C or Rust library; AZL would call via FFI/sysproxy.
2. **Transformer kernels** — Matrix multiply, attention; typically CUDA/cuBLAS.
3. **Tokenization** — BPE/SPM; `tokenizer_bpe32k.json` exists for training.

---

## 5. Benchmark Implications

- **Current benchmarks** (`benchmark_azl_vs_python.sh`): Compare AZL native API vs Python API for healthz/status/exec_state. AZL wins ~10–15%.
- **LLM benchmark:** To compare AZL vs Python for LLM:
  - **Option A:** Both call Ollama (Python script + curl). Measures client overhead.
  - **Option B:** Add Ollama proxy to C engine; compare latency through AZL API vs direct curl to Ollama.

---

## 6. Files Reference

| File | Purpose |
|------|---------|
| `azl/integrations/anythingllm/azme_bridge.azl` | Ollama client (host HTTP) |
| `azl/integrations/anythingllm/azme_anythingllm_provider.azl` | Ollama provider |
| `azl/ffi/torch.azl` | PyTorch training via Python subprocess |
| `azl/core/neural/neural.azl` | Neural scaffolding, GPU policy |
| `azl/core/types/tensor.azl` | Pure AZL tensor (no GPU) |
| `tokenizer_bpe32k.json` | BPE tokenizer for training |
