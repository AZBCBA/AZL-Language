#!/usr/bin/env bash
# Full enterprise AZL **sources** (quantum, LHA3, neural, AZME, …) are concatenated and loaded by the
# child runtime (same list as run_enterprise_daemon.sh). Native engine still serves HTTP; Ollama is
# reached via POST /api/ollama/generate (C forwarder). This answers: "Does loading the fat bundle change
# proxy latency vs minimal bundle?"
#
# Requires: Ollama up; no other process using .azl/engine.out + .azl/engine.in + sysproxy :9099 (stop
# enterprise daemon first if needed).
#
# Env: PROOF_REQS (default 200), PROOF_WARMUP, LLM_BENCH_*, AZL_BUILD_API_PORT / AZL_BENCH_NATIVE_PORT,
#      AZL_API_TOKEN, AZL_RUNTIME_SPINE, OLLAMA_HOST
#
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! curl -sf --max-time 3 http://127.0.0.1:11434/api/tags >/dev/null; then
  echo "ERROR: Ollama not reachable at http://127.0.0.1:11434" >&2
  exit 91
fi

pick_free_port() {
  python3 - <<'PY'
import socket
for port in range(18100, 18190):
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

SP_STARTED=0
WIRE_PID=""
cleanup() {
  if [ -n "${ENGINE_PID:-}" ] && kill -0 "$ENGINE_PID" 2>/dev/null; then
    kill -TERM "$ENGINE_PID" 2>/dev/null || true
    sleep 0.5
    kill -KILL "$ENGINE_PID" 2>/dev/null || true
    wait "$ENGINE_PID" 2>/dev/null || true
  fi
  if [ -n "$WIRE_PID" ] && kill -0 "$WIRE_PID" 2>/dev/null; then
    kill -TERM "$WIRE_PID" 2>/dev/null || true
  fi
  if [ "$SP_STARTED" = "1" ] && [ -f .azl/sysproxy_proof.pid ]; then
    kill "$(cat .azl/sysproxy_proof.pid)" 2>/dev/null || true
    rm -f .azl/sysproxy_proof.pid
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
  if [ ! -x .azl/sysproxy ]; then
    gcc -O2 -Wall -o .azl/sysproxy tools/sysproxy.c
  fi
  SYSPROXY_TCP=127.0.0.1:9099 SYSFIFO_IN=.azl/engine.in SYSFIFO_IN_KEEP=1 .azl/sysproxy 2>.azl/sysproxy_proof.log &
  echo $! > .azl/sysproxy_proof.pid
  SP_STARTED=1
  sleep 0.35
fi

mkdir -p .azl/cache .azl/tmp
rm -f .azl/wire.lock 2>/dev/null || true
rm -f .azl/engine.out .azl/engine.in
mkfifo .azl/engine.out .azl/engine.in 2>/dev/null || true

bash scripts/azl_syswire.sh .azl/engine.out .azl/engine.in >>.azl/wire_proof.log 2>&1 &
WIRE_PID=$!
sleep 0.35

COMBINED=".azl/tmp/enterprise_combined_proof.azl"
bash scripts/build_enterprise_combined.sh "$COMBINED"

BUNDLE=".azl/tmp/enterprise_proof.bundle.azl"
bash scripts/build_azl_bootstrap_bundle.sh "$COMBINED" "::build.daemon.enterprise" --out "$BUNDLE"

BIN="$(bash scripts/build_azl_native_engine.sh)"
PORT="${AZL_BENCH_NATIVE_PORT:-${AZL_BUILD_API_PORT:-}}"
if [ -z "$PORT" ]; then
  PORT="$(pick_free_port)"
fi
if [ -z "$PORT" ]; then
  echo "ERROR: no free TCP port" >&2
  exit 11
fi

if [ -z "${AZL_API_TOKEN:-}" ]; then
  export AZL_API_TOKEN="proof_ent_$(openssl rand -hex 16)"
fi
export AZL_BUILD_API_PORT="$PORT"
export AZL_WIRE_MANAGED=1
export AZL_NATIVE_RUNTIME_CMD="$(bash scripts/azl_resolve_native_runtime_cmd.sh)"

export PROOF_REPORT_TITLE="LLM proof with enterprise AZL bundle loaded (runtime) + native HTTP proxy"
export PROOF_REPORT_DISCLAIMER="This run loads the **same concatenated enterprise .azl** as \`run_enterprise_daemon.sh\` (neural, **LHA3**, **quantum**, AZME, training orchestrators, etc.) into the **child runtime** (\`AZL_NATIVE_RUNTIME_CMD\`). The timed HTTP calls use \`POST /api/ollama/generate\`, which is handled in **tools/azl_native_engine.c** (curl to Ollama)—not by AZL \`http_server.azl\` \`/v1/chat\`. So: you are measuring **proxy latency while the fat AZL program is loaded and running**, not “AZL interpreted every token of the LLM response.” That is still the honest production split today."

echo "[proof-enterprise] combined=$(wc -c < "$COMBINED") bytes spine=${AZL_RUNTIME_SPINE:-c_minimal} port=$PORT"
echo "[proof-enterprise] starting engine (log: .azl/native_enterprise_proof_engine.log)"
"$BIN" "$BUNDLE" >>.azl/native_enterprise_proof_engine.log 2>&1 &
ENGINE_PID=$!

ready=0
for i in $(seq 1 400); do
  if curl -fsS --max-time 2 "http://127.0.0.1:${PORT}/readyz" 2>/dev/null | grep -q '"status":"ready"'; then
    ready=1
    break
  fi
  sleep 0.5
done
if [ "$ready" != "1" ]; then
  echo "ERROR: /readyz did not become ready (see .azl/native_enterprise_proof_engine.log tail below)" >&2
  tail -40 .azl/native_enterprise_proof_engine.log >&2 || true
  exit 12
fi

if ! curl -fsS --max-time 2 "http://127.0.0.1:${PORT}/api/llm/capabilities" 2>/dev/null | grep -q '"ollama_http_proxy":true'; then
  echo "ERROR: engine missing ollama proxy on this port" >&2
  exit 13
fi

export AZL_BASE_URL="http://127.0.0.1:${PORT}"
export PROOF_REQS="${PROOF_REQS:-200}"
export PROOF_WARMUP="${PROOF_WARMUP:-5}"

echo "[proof-enterprise] PROOF_REQS=$PROOF_REQS — for 1000× set PROOF_REQS=1000"
python3 scripts/proof_llm_python_vs_azl.py
echo "[proof-enterprise] done"
