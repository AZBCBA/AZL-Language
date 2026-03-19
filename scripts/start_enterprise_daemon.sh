#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "🚀 AZL Enterprise Daemon Startup"
echo "🎯 Canonical path: scripts/run_enterprise_daemon.sh"
echo ""

export AZL_NATIVE_ONLY="${AZL_NATIVE_ONLY:-1}"
export AZL_NATIVE_RUNTIME_CMD="${AZL_NATIVE_RUNTIME_CMD:-bash scripts/azl_c_interpreter_runtime.sh}"
export AZL_API_TOKEN="${AZL_API_TOKEN:-$(openssl rand -hex 32)}"
export AZL_BUILD_API_PORT="${AZL_BUILD_API_PORT:-8080}"
export AZL_STRICT="${AZL_STRICT:-1}"
export AZL_REQUIRE_API_TOKEN="${AZL_REQUIRE_API_TOKEN:-true}"

echo "🔑 API token configured."
echo "🌐 Port: $AZL_BUILD_API_PORT"
echo "⚙️  AZL_NATIVE_ONLY=$AZL_NATIVE_ONLY"
echo ""

exec bash scripts/run_enterprise_daemon.sh
