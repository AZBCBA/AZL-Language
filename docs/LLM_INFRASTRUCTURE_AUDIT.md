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

**Honesty API:** `GET /api/llm/capabilities` on the native engine returns `gguf_in_process: false` and `error.code: ERR_NATIVE_GGUF_NOT_IN_PROCESS` (weights are not linked inside the binary). When **`AZL_GGUF_PATH`** points at a local **`.gguf`** file, the same JSON advertises **`gguf_cli_infer: true`** and **`POST /api/llm/gguf_infer`** runs **`llama-cli`** from **llama.cpp** on that file (no Ollama). When **`AZL_LLAMA_SERVER_URL`** is set, **`llama_server_upstream_configured: true`** and **`POST /api/llm/llama_server/completion`** proxies to **`llama-server`**’s **`/completion`** (model stays loaded in the upstream process).

**AZL surface:** `::neural.model_loader` listens for **`load_gguf_native`** with a path argument; it emits structured `log_error` (`ERR_NATIVE_GGUF_NOT_IMPLEMENTED`) and **`model_load_failed`** until an in-process loader exists.

---

## 2. Inference Paths

| Path | Created? | How it works |
|------|----------|--------------|
| **Ollama via C engine proxy** | ✅ Yes | `POST /api/ollama/generate` on `tools/azl_native_engine.c` forwards JSON body to `$OLLAMA_HOST/api/generate` (default `http://127.0.0.1:11434`) using `curl`. |
| **llama.cpp llama-server via C engine proxy** | ✅ Yes | `POST /api/llm/llama_server/completion` forwards the JSON body to **`$AZL_LLAMA_SERVER_URL/completion`** with `curl` (Bearer on the engine route; upstream is usually open on localhost). |
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

When implemented, update **`GET /api/llm/capabilities`** to set `gguf_in_process: true` and remove or narrow `ERR_NATIVE_GGUF_NOT_IN_PROCESS`.

### 4.2 Optional hardening

- TLS for Ollama upstream (today: whatever `curl` + URL provide).
- Auth between AZL engine and Ollama beyond network isolation.

---

## 5. Benchmarks

- **API latency:** `scripts/benchmark_azl_vs_python.sh` (healthz / status / exec_state).
- **LLM proxy:** `scripts/benchmark_llm_ollama.sh` — compares Python → Ollama, curl → Ollama, and **C native engine** → `POST /api/ollama/generate` only when `GET /api/llm/capabilities` reports `"ollama_http_proxy":true` (avoids mistaking the enterprise HTTP stack on :8080 for the C proxy). **Env:** `LLM_BENCH_REQS`, **`LLM_BENCH_WARMUP`** (discards first N calls per client so cold-start does not skew Python), **`LLM_BENCH_NUM_PREDICT`** (Ollama `num_predict`; default 16), `LLM_BENCH_MODEL`, `LLM_BENCH_PROMPT`, `OLLAMA_HOST`.
- **Direct GGUF (no Ollama):** `scripts/run_benchmark_gguf_direct.sh` — requires **`AZL_GGUF_PATH`** (local `.gguf`) and a llama.cpp binary (default name **`llama-cli`**; set **`AZL_LLAMA_CLI`** to e.g. **`llama-completion`**). Starts **`azl-native-engine`** with the same env, then `scripts/benchmark_llm_gguf_direct.py` compares **Python subprocess** vs **`POST /api/llm/gguf_infer`** (engine forks the same binary). **`AZL_LLAMA_SIMPLE_IO=1`** is recommended for **`llama-completion`** (avoids interactive hang; subprocess-friendly). **`AZL_LLAMA_SKIP_NO_CNV=1`** only if the binary has no **`-no-cnv`**. Inference stderr is discarded server-side so stdout is the completion text (**`--log-disable` removed** — it suppressed completions on some builds).
- **llama-server (loaded model):** `scripts/run_benchmark_llama_server.sh` — starts **`llama-server -m $AZL_GGUF_PATH`** (set **`LLAMA_SERVER_BIN`** if the binary is not on `PATH`; build with **`DLLAMA_BUILD_SERVER=ON`**), waits for **`/health`**, starts **`azl-native-engine`** with **`AZL_LLAMA_SERVER_URL`**, runs **`scripts/benchmark_llm_llama_server.py`** — **Python → upstream `/completion`** vs **Python → `POST /api/llm/llama_server/completion`** (fair “serving” comparison: one loaded model upstream). Env: **`LLM_BENCH_*`**, optional **`AZL_LLAMA_SERVER_PORT`** / **`AZL_BENCH_NATIVE_PORT`**.
- **Product suite:** `scripts/run_product_benchmark_suite.sh` — runs `run_native_engine_llm_bench.sh`, then `benchmark_enterprise_v1_chat.sh` only when `AZL_API_TOKEN` is set.
- **One-shot C engine + LLM bench:** `scripts/run_native_engine_llm_bench.sh` — builds `azl-native-engine`, starts it with minimal bootstrap (`azl/tests/c_minimal_link_ping.azl`), waits for capabilities, runs `benchmark_llm_ollama.sh` with matching `AZL_BENCH_PORT` / `AZL_BENCH_TOKEN`. Requires `ollama serve` and a pulled model (e.g. `llama3.2:1b`).
- **Enterprise HTTP stack (different surface):** when the combined daemon serves `azl/system/http_server.azl`, chat is **`POST /v1/chat`** (or `/chat`) with **Bearer** auth — not **`POST /api/ollama/generate`**. **`scripts/benchmark_enterprise_v1_chat.sh`** measures latency for that route (requires running enterprise daemon + `AZL_API_TOKEN`).

---

## 6. Files Reference

| File | Purpose |
|------|---------|
| `tools/azl_native_engine.c` | HTTP server, `POST /api/ollama/generate`, **`POST /api/llm/gguf_infer`** (local `llama-cli` + `AZL_GGUF_PATH`), **`POST /api/llm/llama_server/completion`** (`curl` → `$AZL_LLAMA_SERVER_URL/completion`), **`GET /api/llm/capabilities`** |
| `scripts/benchmark_llm_ollama.sh` | LLM latency benchmark (detects C proxy via `/api/llm/capabilities`) |
| `scripts/run_native_engine_llm_bench.sh` | Start C engine + run LLM benchmark end-to-end |
| `scripts/run_benchmark_gguf_direct.sh` | Start C engine + direct `.gguf` / `llama-cli` benchmark (no Ollama) |
| `scripts/benchmark_llm_gguf_direct.py` | Python `llama-cli` vs `POST /api/llm/gguf_infer` timings |
| `scripts/run_benchmark_llama_server.sh` | `llama-server` + engine with `AZL_LLAMA_SERVER_URL` + proxy benchmark |
| `scripts/benchmark_llm_llama_server.py` | Direct `llama-server` `/completion` vs `POST /api/llm/llama_server/completion` |
| `scripts/benchmark_enterprise_v1_chat.sh` | Enterprise `POST /v1/chat` latency (daemon + token) |
| `scripts/run_product_benchmark_suite.sh` | Native LLM bench + optional enterprise chat in one run |
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

- `scripts/verify_native_runtime_live.sh` — asserts `/api/llm/capabilities` returns `ok`, `ollama_http_proxy: true`, `gguf_in_process: false`, and `ERR_NATIVE_GGUF_NOT_IN_PROCESS`.
- `scripts/check_azl_native_gates.sh` — requires the capabilities route to exist in the C source.
