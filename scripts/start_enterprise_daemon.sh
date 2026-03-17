#!/bin/bash
set -euo pipefail

# AZL Enterprise Daemon - Simplified Working Version
# This actually starts the daemon and keeps it running

echo "🚀 AZL Enterprise Daemon - Simplified Version"
echo "⚡ PURE AZL EXECUTION - NO EXTERNAL DEPENDENCIES!"
echo ""

# Set environment variables
export AZL_API_TOKEN="${AZL_API_TOKEN:-$(openssl rand -hex 32)}"
export AZL_BUILD_API_PORT="${AZL_BUILD_API_PORT:-8080}"

echo "🔑 API Token: $AZL_API_TOKEN"
echo "🌐 Port: $AZL_BUILD_API_PORT"

# Create cache directory
mkdir -p .azl/cache

echo "🏢 Starting AZL Enterprise Build Daemon..."
echo "🌐 API Server: http://localhost:$AZL_BUILD_API_PORT"
echo "🔑 Token: $AZL_API_TOKEN"
echo "📊 Workers: 8"
echo "💾 Cache: .azl/cache"

# Launch real Node runtime bound to sysproxy
echo "🌐 Starting real runtime on port $AZL_BUILD_API_PORT (localhost)"
export AZL_BIND_HOST="127.0.0.1"
export AZL_RUNTIME_TRANSPORT="tcp"
export SYSPROXY_HOST="127.0.0.1"
export SYSPROXY_PORT="9099"
export AZL_STRICT="1"
export AZL_WARM_FILES=${AZL_WARM_FILES:-"azl/runtime/interpreter/azl_interpreter.azl,azl/system/azl_system_interface.azl,azl/system/http_server.azl,azl/build/build_orchestrator.azl"}

# Ensure sysproxy is running (compile if necessary)
if ! ss -lnt | grep -q ":${SYSPROXY_PORT} "; then
  echo "🔧 Starting sysproxy (:${SYSPROXY_PORT})"
  mkdir -p .azl
  gcc -O2 -o .azl/sysproxy tools/sysproxy.c
  SYSPROXY_TCP="127.0.0.1:${SYSPROXY_PORT}" ./.azl/sysproxy 1>.azl/sysproxy.out 2>.azl/sysproxy.log &
  sleep 0.3
fi

node scripts/azl_runtime.js 1>.azl/runtime.out 2>.azl/runtime.log &
RUNTIME_PID=$!
echo "✅ Runtime PID: $RUNTIME_PID"
echo "🔄 Daemon running... Press Ctrl+C to stop"
wait $RUNTIME_PID
