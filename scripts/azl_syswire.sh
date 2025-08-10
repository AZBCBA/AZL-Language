#!/usr/bin/env bash
set -euo pipefail

# singleton guard
exec 9>.azl/wire.lock
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
    | stdbuf -oL tee -a .azl/wire.requests.log \
    > /proc/self/fd/3
) &

# pump responses sysproxy->engine (log to file)
(
  stdbuf -oL cat <&3 \
    | stdbuf -oL tee -a .azl/wire.responses.log \
    | while IFS= read -r resp; do
        printf '@sysproxy.response %s\n' "$resp" >&4
      done
) &

# wait for both pumps to exit (service manager will restart on failure)
wait
