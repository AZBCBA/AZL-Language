# Integrations: host-shaped vs native AZL

Some files under `azl/integrations/` are **legacy / host-shaped** (JavaScript-like syntax: `class`, `function`, `let`, `http_get` as free functions). They are **not** valid input for the pure AZL parser and must **not** appear in the **native enterprise combined bundle** (`scripts/run_enterprise_daemon.sh`).

## Native-safe (pure AZL grammar)

| Area | Path | Notes |
|------|------|--------|
| AnythingLLM **native** bridge | `azl/integrations/anythingllm/azme_ollama_native.azl` | Ollama JSON via `syscall` `http` → sysproxy `http_client` for real URLs |
| Other integration trees | `azl/integrations/ai/*.azl`, `external_data_sources.azl`, etc. | Mostly host-shaped; treat as **reference only** until rewritten |

## Host-only / reference (do not merge into native bundle)

| Path | Why |
|------|-----|
| `azl/integrations/anythingllm/azme_bridge.azl` | JS-style `http_get` / `http_post` |
| `azl/integrations/anythingllm/azme_anythingllm_provider.azl` | Host patterns |
| `azl/integrations/anythingllm/azme_proxy.azl` | `function`, `let`, free functions |
| `azl/integrations/anythingllm_integration.azl` | `class` |
| `azl/integrations/anythingllm/setup_azme_integration.sh` | Machine-specific paths; helper only |

## Enforcement

- `scripts/verify_native_bundle_excludes_host_integrations.sh` — fails if `run_enterprise_daemon.sh` lists the blocked paths.
- Grammar checks on the **combined** runtime file (`verify_azl_grammar_conformance.sh`) catch `class` / `import … from` / etc.

## Ollama from native AZL

1. **C engine:** `POST /api/ollama/generate` (see `docs/LLM_INFRASTRUCTURE_AUDIT.md`).
2. **Pure AZL + sysproxy:** `emit syscall` with `type: "http"` and an `http://` or `https://` URL (see `azl/system/azl_system_interface.azl`).
3. **Component:** `::integrations.anythingllm.ollama_native` — event `integrations.anythingllm.ollama_post_json` with `event.data.json` body string for `POST …/api/generate`.
