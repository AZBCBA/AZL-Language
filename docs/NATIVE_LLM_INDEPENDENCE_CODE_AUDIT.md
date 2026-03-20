# Native LLM independence — code-derived audit

This document lists **gaps and facts** inferred from the repository **source**, not from marketing copy. Goal: AZL’s native stack can run **real GGUF weights** without **Ollama** and without **Python in the inference path**, while staying honest about what is optional vs default.

## 1. What “independent” means here

- **Inference path**: Loading a `.gguf` and running a forward pass inside **one native process** (C/C++ via **llama.cpp** linked into `azl-native-engine`). No `ollama` daemon, no `llama-cli` child process, no Python interpreter for that request.
- **Still external**: Upstream **llama.cpp** is a third-party C/C++ library (same as linking OpenSSL or zlib). It is **not** vendored in this repo; you point **`LLAMA_CPP_ROOT`** at a local checkout when building.

## 2. Evidence from code (current)

| Location | Behavior |
|----------|----------|
| `tools/azl_native_engine.c` `handle_gguf_infer` | **Default build**: `fork` + `execlp` **`llama-cli`** — separate process. **Optional build** (`AZL_WITH_LLAMACPP`): calls **`azl_llamacpp_gguf_infer`** (in-process). Set **`AZL_GGUF_USE_CLI=1`** to force the fork path when the llama.cpp binary is linked. |
| `tools/azl_native_engine.c` `POST /api/ollama/generate` | **`curl`** to **`$OLLAMA_HOST`** — optional integration, not required for GGUF. |
| `tools/azl_native_engine.c` `handle_llama_server_completion_proxy` | **`curl`** to **`$AZL_LLAMA_SERVER_URL`** — optional; model lives in another process. |
| `tools/azl_native_engine.c` `GET /api/llm/capabilities` | **`gguf_in_process`**: `false` unless built with **`scripts/build_azl_native_engine_with_llamacpp.sh`**, then `true` + **`gguf_embedded_llamacpp: true`** and **`error: null`**. |
| `scripts/build_azl_native_engine.sh` | **gcc** only — **no** llama.cpp; this remains the **default CI/gate** build. |
| `scripts/build_azl_native_engine_with_llamacpp.sh` | **CMake** links **`llama`** into **`.azl/bin/azl-native-engine`**. |
| `tools/azl_gguf_infer_llamacpp.cpp` | Greedy sampling loop (llama.cpp API); caches **`llama_model`** per **`AZL_GGUF_PATH`**; **`AZL_LLAMA_NGL`** → **`n_gpu_layers`**. |
| `azl/neural/model_loader.azl` `load_gguf_native` | AZL-layer event still **does not** mmap weights; it documents the **HTTP/native** path instead of claiming in-process AZL bytecode. |

## 3. Remaining gaps (realistic)

1. **AZL bytecode `load_gguf_native`**: Still no direct neural forward in pure `.azl`; orchestration goes through the **native engine** HTTP API (or future syscall bridge).
2. **Tokenizer / formats**: Only **GGUF via llama.cpp** is wired; no ONNX/safetensors path in-tree.
3. **Concurrency**: Embedded path assumes the engine’s **single-threaded** accept loop; a multi-worker server would need locking around the model cache.
4. **Ollama/llama-server proxies**: Still present for benchmarks and migrations; they are **not** used when you only call **`POST /api/llm/gguf_infer`** with an embedded build.

## 4. Build (in-process GGUF)

```bash
export LLAMA_CPP_ROOT=/path/to/llama.cpp
./scripts/build_azl_native_engine_with_llamacpp.sh
export AZL_GGUF_PATH=/path/to/model.gguf
# run engine as you already do for native mode
```

Optional: **`AZL_GGUF_USE_CLI=1`** — use **`llama-cli`** subprocess even if the binary was built with llama.cpp.

---

*Last updated to match the tree at the time of the embedded-llama.cpp integration.*
