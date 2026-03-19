# AnythingLLM-related files

- **`azme_ollama_native.azl`** — **Pure AZL** Ollama client via `syscall` `http` (real TCP when sysproxy/http_client is available). Prefer this for native stacks.
- **`azme_bridge.azl`**, **`azme_anythingllm_provider.azl`**, **`azme_proxy.azl`** — **Host-shaped reference** (not pure AZL). Do not add to `scripts/run_enterprise_daemon.sh` without a full rewrite.

See `docs/INTEGRATIONS_HOST_VS_NATIVE.md`.
