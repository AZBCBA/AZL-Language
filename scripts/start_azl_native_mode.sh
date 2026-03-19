#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "🚀 AZL NATIVE MODE START"
echo "⚡ Enforcing native-mode constraints for AZL direction"

export AZL_NATIVE_ONLY=1
export AZL_REQUIRE_API_TOKEN="${AZL_REQUIRE_API_TOKEN:-true}"
export AZL_LOCAL_MODE="${AZL_LOCAL_MODE:-0}"
export AZL_STRICT="${AZL_STRICT:-1}"
export AZL_ENABLE_LEGACY_HOST=0

# Use provided token or generate one for this session.
export AZL_API_TOKEN="${AZL_API_TOKEN:-$(openssl rand -hex 32)}"
echo "🔑 AZL_API_TOKEN set (value hidden)."

if [ -z "${AZL_NATIVE_RUNTIME_CMD:-}" ]; then
  export AZL_NATIVE_RUNTIME_CMD="bash scripts/azl_c_interpreter_runtime.sh"
fi
echo "⚙️  AZL_NATIVE_RUNTIME_CMD=${AZL_NATIVE_RUNTIME_CMD}"

if [ -z "${AZL_NATIVE_EXEC_CMD:-}" ]; then
  echo "🔧 AZL_NATIVE_EXEC_CMD not set; building native engine..."
  AZL_NATIVE_EXEC_CMD="$(bash scripts/build_azl_native_engine.sh)"
  export AZL_NATIVE_EXEC_CMD
fi
echo "⚙️  AZL_NATIVE_EXEC_CMD=${AZL_NATIVE_EXEC_CMD}"

# Stop Python 24h service if active to avoid mixed-runtime ambiguity.
if command -v systemctl >/dev/null 2>&1; then
  if systemctl --user is-active --quiet azme-24h.service; then
    echo "🛑 Stopping azme-24h.service (Python control-plane path)"
    systemctl --user stop azme-24h.service || true
  fi
fi

echo "🏢 Starting AZL enterprise daemon path (native target baseline)"
exec bash scripts/start_enterprise_daemon.sh
