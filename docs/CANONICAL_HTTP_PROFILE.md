# Canonical HTTP profile (deployment choice)

Two different HTTP personalities exist in this repository. **Pick one per deployment** and document it in your runbook so benchmarks and clients hit the right routes.

## Profile A — C native engine (`tools/azl_native_engine.c`)

**When:** You want a small supervisor process that forks the runtime child and exposes a fixed API.

| Aspect | Detail |
|--------|--------|
| **Typical startup** | `scripts/start_azl_native_mode.sh` / bootstrap path that runs `azl-native-engine` |
| **Health** | `GET /healthz` → `{"ok":true,"service":"azl-native-engine",...}` |
| **LLM (Ollama)** | `POST /api/ollama/generate`, honesty: `GET /api/llm/capabilities` |
| **Chat** | **No** `POST /v1/chat` on this surface |
| **Bench** | `scripts/run_native_engine_llm_bench.sh`, `scripts/benchmark_llm_ollama.sh` |

## Profile B — Enterprise combined + `azl/system/http_server.azl`

**When:** You run the full concatenated daemon and want AZL-defined routes (chat, training hooks, etc.).

| Aspect | Detail |
|--------|--------|
| **Typical startup** | `scripts/run_enterprise_daemon.sh` (combined file + native child as wired) |
| **Health** | `GET /healthz` — shape depends on wiring; must **not** be mistaken for Profile A when benchmarking |
| **Chat** | `POST /v1/chat` (and `/chat`) with **Bearer** `AZL_API_TOKEN` |
| **LLM** | Routed inside AZL (not the same as Profile A’s `/api/ollama/generate` unless explicitly bridged) |
| **Bench** | `scripts/benchmark_enterprise_v1_chat.sh` (requires real token + route); **404 on `/v1/chat`** ⇒ you are **not** on Profile B for that port (**exit 95**, **`ERROR[AZL_ENTERPRISE_V1_CHAT_BENCH]`** — [ERROR_SYSTEM.md](ERROR_SYSTEM.md)) |

## CI

**Test and Deploy** exercises both stacks in separate jobs: native engine matrix / benchmark gate (Profile A–shaped) vs enterprise combined path inside **`run_all_tests.sh`** / **`verify_enterprise_native_http_live.sh`** (Profile B). Do not merge Profile A bench ports with Profile B daemon ports — see [LLM_INFRASTRUCTURE_AUDIT.md](LLM_INFRASTRUCTURE_AUDIT.md).

## Rules

1. **Never assume port 8080** means a specific profile — probe routes or read the process startup command.
2. **Product benchmarks:** Leg 1 (Ollama via C proxy) uses an **ephemeral** Profile A engine from `run_native_engine_llm_bench.sh`. Leg 2 needs **Profile B** with `/v1/chat` present.
3. **GGUF / GPU:** In-process weights are **not** implemented; Profile A reports that honestly via `/api/llm/capabilities` — see [LLM_INFRASTRUCTURE_AUDIT.md](LLM_INFRASTRUCTURE_AUDIT.md).

## Related docs

- [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md) — which process owns AZL semantics
- [AZL_NATIVE_RUNTIME_CONTRACT.md](AZL_NATIVE_RUNTIME_CONTRACT.md) — native HTTP/runtime contract
- [RELEASE_READY.md](../RELEASE_READY.md) — gate order before release
