# AZL Operations Runbook

## Overview
This runbook documents how to run the enterprise daemon and validate host integrations via the sysproxy bridge using only the pure AZL engine.

**sysproxy ops (subset):** socket **`listen` / `accept` / `read` / `write` / `close`**, **`keepalive`**, **`http_client`**, **`getenv`** (reads the **sysproxy process** environment via libc `getenv`; AZL uses it through **`::azl.system_interface.host_getenv`** and exec-bridge seeding of **`::internal`**).

## Quick Start (Local)
- Build sysproxy:
  - `gcc -O2 -Wall -o .azl/sysproxy tools/sysproxy.c`
- Run full integration test harness:
  - `bash scripts/test_sysproxy_setup.sh`
- Verify:
  - `curl http://127.0.0.1:8080/healthz`
  - `curl http://127.0.0.1:8080/readyz`
  - `curl http://127.0.0.1:8080/status`
  - `tail -f .azl/logs/daemon.out | grep '@sysproxy'`

## Native Smoke Tests
- **Exit codes (no silent failures):** live verify and release helper scripts document **`ERROR:`** + numeric exits in [docs/ERROR_SYSTEM.md](docs/ERROR_SYSTEM.md) § *Shell helpers* — e.g. **`verify_native_runtime_live.sh`** **69–77**, **`verify_enterprise_native_http_live.sh`** **80–88**, **`self_check_release_helpers.sh`** **40–58**.
- **`bash scripts/run_full_repo_verification.sh`** — `RELEASE_READY.md` order + `run_all_tests.sh` + optional LLM benches (`RUN_OPTIONAL_BENCHES=0` to skip benches)
- `./scripts/run_tests.sh` — runs canonical native checks
- `./scripts/run_all_tests.sh` — runs strict native suite + benchmark gates
- `bash scripts/benchmark_native_api.sh` — native API latency benchmark
- **LLM / chat (optional, needs running backends):**
  - `bash scripts/run_product_benchmark_suite.sh` — native LLM bench + enterprise `/v1/chat` if `AZL_API_TOKEN` is set
  - `bash scripts/run_native_engine_llm_bench.sh` — C `azl-native-engine` + Ollama (`ollama serve` + model)
  - `bash scripts/benchmark_llm_ollama.sh` — Python vs curl vs C Ollama proxy (detects proxy via `GET /api/llm/capabilities`)
  - **`bash scripts/run_proof_llm_python_vs_azl.sh`** — **1000×** identical requests: Python → Ollama vs client → **`azl-native-engine`** `POST /api/ollama/generate` → Ollama; writes **`.azl/benchmarks/proof_llm_python_vs_azl_*.md`** (mean/p95 **AZL/Python** ratios). Override count: `PROOF_REQS=500 …`.
  - **`bash scripts/run_proof_llm_enterprise_bundle.sh`** — same proof as above, but the **child runtime** loads the **full enterprise concatenated .azl** (same component list as **`run_enterprise_daemon.sh`**: quantum, LHA3, neural, AZME, …). Stops other daemons if they hold **`.azl/engine.out` / `9099`**. Default **`PROOF_REQS=200`** (set **`PROOF_REQS=1000`** for a full run). Report includes an explicit **Scope** section (native C Ollama proxy vs `/v1/chat`).
  - **`bash scripts/build_enterprise_combined.sh <out.azl>`** — writes the enterprise combined file only (for inspection or custom bundles).
  - `AZL_API_TOKEN=… bash scripts/benchmark_enterprise_v1_chat.sh` — enterprise `POST /v1/chat` (daemon on `AZL_ENTERPRISE_PORT`, default 8080)
- **Native GGUF + GPU (llama.cpp):** on the **`azl-native-engine` process**, set **`AZL_GGUF_PATH`** and either **`AZL_LLAMA_NGL`** or **`AZL_LLM_GPU_LAYERS`** (integer layer offload count). Same vars apply to the default **`llama-cli`** subprocess path (**`-ngl`**) and the optional in-process build (**`n_gpu_layers`**). Training/orchestration flags like **`AZL_HAS_GPU`** / **`device: cuda`** in `.azl` are a **separate** track (Torch / policy) until a syscall unifies them — see **`docs/AZL_GPU_NEURAL_QUANTUM_INVENTORY.md` §2.1**.

## CI
- Main CI (`.github/workflows/ci.yml`):
  - Fails on any placeholders/TODO/FIXME in `.azl`
  - Fails on any stale v2 references
  - Runs native gate and live runtime verification
- Nightly sysproxy E2E (`.github/workflows/nightly.yml`):
  - Builds sysproxy, runs `scripts/test_sysproxy_setup.sh`, uploads logs

## Troubleshooting
- Permission denied on `.azl/logs/daemon.out`:
  - Ensure file exists and writable: `: > .azl/logs/daemon.out && chmod 664 .azl/logs/daemon.out`
- Port conflict on 8080:
  - Set `AZL_BUILD_API_PORT` before running daemon: `AZL_BUILD_API_PORT=8090 bash scripts/run_enterprise_daemon.sh`
- No sysproxy responses:
  - Check wire logs: `tail -f .azl/logs/wire.log`
  - Check sysproxy logs: `tail -f .azl/logs/sysproxy.log`

## Notes
- Torch FFI is disabled by default; calls log `ffi_disabled` and proceed.
- The language is unified under a single interpreter and parser (`::parser.core`).
