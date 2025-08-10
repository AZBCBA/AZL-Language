#!/usr/bin/env bash
set -euo pipefail

# singleton guard
exec 9>.azl/wire.lock
flock -n 9 || exit 0

ENGINE_OUT="$1"   # from AZL engine; lines like:  @sysproxy {"id":...}
ENGINE_IN="$2"    # back to AZL engine; we'll write: @sysproxy.response {...}

HOST="${SYSPROXY_HOST:-127.0.0.1}"
PORT="${SYSPROXY_PORT:-9099}"

# open a bidirectional TCP fd 3
exec 3<>"/dev/tcp/${HOST}/${PORT}"

# pump requests engine->sysproxy
( stdbuf -oL sed -u -n 's/.*@sysproxy[[:space:]]\{1,\}//p' "$ENGINE_OUT" | stdbuf -oL tee /dev/stderr >&3 ) &

# pump responses sysproxy->engine
( stdbuf -oL cat <&3 | while IFS= read -r resp; do
    printf '@sysproxy.response %s\n' "$resp" >> "$ENGINE_IN"
  done ) &

wait -n || true
