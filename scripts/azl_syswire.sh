#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/azl_local_layout.sh"
mkdir -p "$AZL_LOGS_DIR"

# singleton guard (co-located with wire traffic logs)
exec 9>"${AZL_LOGS_DIR}/wire.lock"
flock -n 9 || exit 0

ENGINE_OUT="$1"   # from AZL engine; lines like:  @sysproxy {"id":...}
ENGINE_IN="$2"    # back to AZL engine; we'll write: @sysproxy.response {...}

HOST="${SYSPROXY_HOST:-127.0.0.1}"
PORT="${SYSPROXY_PORT:-9099}"

mkdir -p .azl

# open a bidirectional TCP fd 3
exec 3<>"/dev/tcp/${HOST}/${PORT}"

# keep ENGINE_IN FIFO open persistently for writing on fd 4
exec 4>>"$ENGINE_IN"

# pump requests engine->sysproxy (log both to stderr and file)
(
  stdbuf -oL sed -u -n 's/.*@sysproxy[[:space:]]\{1,\}//p' "$ENGINE_OUT" \
    | stdbuf -oL tee /dev/stderr \
    | stdbuf -oL tee -a "${AZL_LOGS_DIR}/wire.requests.log" \
    >&3
) &

# pump responses sysproxy->engine (log to file)
(
  stdbuf -oL cat <&3 \
    | stdbuf -oL tee -a "${AZL_LOGS_DIR}/wire.responses.log" \
    | while IFS= read -r resp; do
        printf '@sysproxy.response %s\n' "$resp" >&4
      done
) &

# wait for both pumps to exit (service manager will restart on failure)
wait
