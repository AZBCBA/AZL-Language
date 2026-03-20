#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

GGUF="${AZL_GGUF_PATH:-}"
if [ -z "$GGUF" ] || [ ! -f "$GGUF" ]; then
  echo "ERROR: set AZL_GGUF_PATH to an existing .gguf file" >&2
  exit 91
fi

if [ -z "${LLAMA_CPP_ROOT:-}" ] || [ ! -f "${LLAMA_CPP_ROOT}/CMakeLists.txt" ]; then
  echo "ERROR: set LLAMA_CPP_ROOT to a local llama.cpp checkout" >&2
  exit 92
fi

pick_free_port() {
  python3 - <<'PY'
import socket
for port in range(18230, 18330):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.bind(("127.0.0.1", port))
        print(port)
        break
    except OSError:
        pass
    finally:
        s.close()
PY
}

PORT="${AZL_BENCH_NATIVE_PORT:-${AZL_BUILD_API_PORT:-}}"
if [ -z "$PORT" ]; then PORT="$(pick_free_port)"; fi
if [ -z "$PORT" ]; then
  echo "ERROR: no free TCP port"
  exit 11
fi

if [ -z "${AZL_API_TOKEN:-}" ]; then
  export AZL_API_TOKEN="bench_policy_$(openssl rand -hex 12)"
fi
export AZL_BUILD_API_PORT="$PORT"
export AZL_NATIVE_RUNTIME_CMD="$(bash scripts/azl_resolve_native_runtime_cmd.sh)"
export AZL_BENCH_GGUF_URL="http://127.0.0.1:${PORT}"
export AZL_BENCH_TOKEN="$AZL_API_TOKEN"
export LLM_BENCH_REQS="${LLM_BENCH_REQS:-10}"
export LLM_BENCH_WARMUP="${LLM_BENCH_WARMUP:-2}"
export LLM_BENCH_NUM_PREDICT="${LLM_BENCH_NUM_PREDICT:-24}"

SP_STARTED=0
WIRE_PID=""
cleanup() {
  if [ -n "${ENGINE_PID:-}" ] && kill -0 "$ENGINE_PID" 2>/dev/null; then
    kill -TERM "$ENGINE_PID" 2>/dev/null || true
    sleep 0.4
    kill -KILL "$ENGINE_PID" 2>/dev/null || true
    wait "$ENGINE_PID" 2>/dev/null || true
  fi
  if [ -n "${WIRE_PID:-}" ] && kill -0 "$WIRE_PID" 2>/dev/null; then
    kill -TERM "$WIRE_PID" 2>/dev/null || true
  fi
  if [ "$SP_STARTED" = "1" ] && [ -f .azl/sysproxy_policy_bench.pid ]; then
    kill "$(cat .azl/sysproxy_policy_bench.pid)" 2>/dev/null || true
    rm -f .azl/sysproxy_policy_bench.pid
  fi
}
trap cleanup EXIT

ok=1
if command -v timeout >/dev/null 2>&1; then
  timeout 1 bash -lc 'exec 5<>/dev/tcp/127.0.0.1/9099; exec 5>&-' >/dev/null 2>&1 && ok=0 || ok=1
else
  { exec 5<>/dev/tcp/127.0.0.1/9099; ok=$?; exec 5>&-; } 2>/dev/null || ok=1
fi
if [ "${ok}" != "0" ]; then
  mkdir -p .azl
  rm -f .azl/engine.out .azl/engine.in
  mkfifo .azl/engine.out .azl/engine.in || true
  if [ ! -x .azl/sysproxy ]; then gcc -O2 -Wall -o .azl/sysproxy tools/sysproxy.c; fi
  SYSPROXY_TCP=127.0.0.1:9099 SYSFIFO_IN=.azl/engine.in SYSFIFO_IN_KEEP=1 .azl/sysproxy 2>.azl/sysproxy_policy_bench.log &
  echo $! > .azl/sysproxy_policy_bench.pid
  SP_STARTED=1
  sleep 0.35
  bash scripts/azl_syswire.sh .azl/engine.out .azl/engine.in >>.azl/wire_policy_bench.log 2>&1 &
  WIRE_PID=$!
  sleep 0.35
fi

mkdir -p .azl/tmp
bash scripts/build_azl_native_engine_with_llamacpp.sh >/tmp/azl_policy_build.log
bash scripts/build_enterprise_combined.sh .azl/tmp/policy_bench_enterprise_combined.azl >/tmp/azl_policy_combined.log
bash scripts/build_azl_bootstrap_bundle.sh .azl/tmp/policy_bench_enterprise_combined.azl "::build.daemon.enterprise" --out .azl/tmp/policy_bench_enterprise.bundle.azl >/tmp/azl_policy_bundle.log

echo "[policy-bench] starting engine on 127.0.0.1:${PORT}"
./.azl/bin/azl-native-engine .azl/tmp/policy_bench_enterprise.bundle.azl >>.azl/native_policy_bench_engine.log 2>&1 &
ENGINE_PID=$!

ready=0
for _ in $(seq 1 200); do
  if curl -fsS -H "Authorization: Bearer ${AZL_API_TOKEN}" --max-time 2 "http://127.0.0.1:${PORT}/readyz" 2>/dev/null | rg -q '"status":"ready"'; then
    ready=1
    break
  fi
  sleep 0.3
done
if [ "$ready" != "1" ]; then
  echo "ERROR: engine did not become ready (see .azl/native_policy_bench_engine.log)" >&2
  exit 12
fi

curl -fsS -H "Authorization: Bearer ${AZL_API_TOKEN}" "http://127.0.0.1:${PORT}/api/llm/capabilities" > .azl/benchmark_policy_capabilities.json
OUT=".azl/benchmark_policy_vs_direct_$(date +%Y%m%d_%H%M%S).txt"
python3 scripts/benchmark_llm_policy_vs_direct.py > "$OUT"
echo "$OUT"

