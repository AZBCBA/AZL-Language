#!/usr/bin/env bash
# Start AZL package registry server (local deployment)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

export AZL_REGISTRY_DIR="${AZL_REGISTRY_DIR:-.azl/packages}"
export AZL_REGISTRY_PORT="${AZL_REGISTRY_PORT:-8765}"
export AZL_REGISTRY_HOST="${AZL_REGISTRY_HOST:-127.0.0.1}"

mkdir -p "$AZL_REGISTRY_DIR"
echo "AZL Registry: http://${AZL_REGISTRY_HOST}:${AZL_REGISTRY_PORT} -> $(cd "$AZL_REGISTRY_DIR" && pwd)"
exec python3 tools/registry_server.py
