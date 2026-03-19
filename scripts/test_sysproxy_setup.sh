#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "🔍 test_sysproxy_setup: delegating to azme_e2e.sh"
exec bash scripts/azme_e2e.sh
