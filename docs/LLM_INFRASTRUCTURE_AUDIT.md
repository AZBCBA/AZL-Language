# LLM Infrastructure Audit

**Purpose:** What exists for running LLMs in AZL vs what's missing. Updated to match the **native** stack (C engine, sysproxy, pure AZL syscall path).

---

## 1. Model Loading (GGUF, ONNX, Safetensors)

| Format | Created? | Location | Notes |
|--------|----------|----------|-------|
| **GGUF** | ❌ No | — | No in-process loader. Ollama holds GGUF internally; AZL does not mmap weights. |
| **ONNX** | ❌ No | — | No ONNX runtime bridge. |
| **Safetensors** | ❌ No | — | No loader. |
| **PyTorch .pt** | ⚠️ Via FFI | `azl/ffi/torch.azl` | Spawns Python `mini_llm_train.py`; training-oriented, not production inference. |

**Honesty API:** `GET /api/llm/capabilities` on the native engine returns `gguf_in_process: false` and `error.code: ERR_NATIVE_GGUF_NOT_IMPLEMENTED` until a real loader exists.

---

## 2. Inference Paths

| Path | Created? | How it works |
|------|----------|--------------|
| **Ollama via C engine proxy** | ✅ Yes | `POST /api/ollama/generate` on `tools/azl_native_engine.c` forwards JSON body to `$OLLAMA_HOST/api/generate` (default `http://127.0.0.1:11434`) using `curl`. |
| **Ollama / HTTP from integrations** | ✅ Yes | `azme_bridge.azl`, `azme_anythingllm_provider.azl` — host-style HTTP when run outside strict native-only paths. |
| **Virtual OS → sysproxy `http_client`** | ✅ Yes | `azl/system/azl_system_interface.azl` issues `sysproxy_call("http_client", { url, method, body })` for real HTTP when sysproxy implements it. |
| **Syscall `http`** | ✅ Yes | Kernel/sysproxy path used in tests (`azl/kernel/azl_kernel.azl`, integration tests). |
| **FFI Torch** | ✅ Yes | Python subprocess for training; not inference. |
| **Quantum byte / neural scaffolding** | ⚠️ Symbolic | Not a substitute for loaded weights + forward pass. |

---

## 3. Real HTTP vs Simulated HTTP

| Component | Real HTTP? | Notes |
|-----------|------------|-------|
| `azl/stdlib/core/azl_stdlib.azl` `http_get` / `http_post` | ❌ Simulated | Backing store / stubs for non-URL keys. |
| `azl/ffi/http.azl` | ❌ Simulated | Cache layer; not a network client by itself. |
| **sysproxy** + **`http_client`** | ✅ Yes | Outbound HTTP when wired (see `azl_system_interface.azl`). |
| **C native engine** | ✅ Outbound | `curl` to Ollama from `/api/ollama/generate`. |
| **C native engine** | ✅ Inbound | Serves HTTP API (health, status, LLM proxy, capabilities). |

**Conclusion:** Native mode **can** reach Ollama through the **engine proxy** without a Python host. Pure AZL code can reach HTTP through **syscall / sysproxy** when that path is enabled.

---

## 4. What Still Needs to Be Built

### 4.1 In-process native LLM (GGUF)

1. **GGUF loader + inference** — e.g. llama.cpp (or equivalent) in C/C++; AZL invokes via FFI, syscall bridge, or a dedicated engine subcommand.
2. **Kernels** — matmul, attention; GPU optional (CUDA/cuBLAS).
3. **Tokenization** — BPE/SPM; `tokenizer_bpe32k.json` exists for training pipelines.

When implemented, update **`GET /api/llm/capabilities`** to set `gguf_in_process: true` and remove or narrow `ERR_NATIVE_GGUF_NOT_IMPLEMENTED`.

### 4.2 Optional hardening

- TLS for Ollama upstream (today: whatever `curl` + URL provide).
- Auth between AZL engine and Ollama beyond network isolation.

---

## 5. Benchmarks

- **API latency:** `scripts/benchmark_azl_vs_python.sh` (healthz / status / exec_state).
- **LLM proxy:** `scripts/benchmark_llm_ollama.sh` — compares direct Ollama vs `http://127.0.0.1:$AZL_PORT/api/ollama/generate` (requires `ollama serve` + a small model).

---

## 6. Files Reference

| File | Purpose |
|------|---------|
| `tools/azl_native_engine.c` | HTTP server, `POST /api/ollama/generate`, **`GET /api/llm/capabilities`** |
| `scripts/benchmark_llm_ollama.sh` | LLM latency benchmark through native API |
| `azl/system/azl_system_interface.azl` | `http_client` sysproxy integration |
| `azl/integrations/anythingllm/azme_bridge.azl` | Ollama client (integration / host contexts) |
| `azl/integrations/anythingllm/azme_anythingllm_provider.azl` | AnythingLLM-oriented provider |
| `azl/ffi/torch.azl` | PyTorch training via subprocess |
| `azl/neural/model_loader.azl` | Model registry / config (not GGUF bytes) |
| `azl/core/neural/neural.azl` | Neural scaffolding |
| `azl/core/types/tensor.azl` | Pure AZL tensor |
| `tokenizer_bpe32k.json` | BPE tokenizer asset |

---

## 7. Verification

- `scripts/verify_native_runtime_live.sh` — asserts `/api/llm/capabilities` returns `ok`, `ollama_http_proxy: true`, `gguf_in_process: false`, and `ERR_NATIVE_GGUF_NOT_IMPLEMENTED`.
- `scripts/check_azl_native_gates.sh` — requires the capabilities route to exist in the C source.
