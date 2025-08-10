#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "🔎 Pre-deploy check: running full strict AZL tests"
chmod +x scripts/run_all_tests.sh || true
./scripts/run_all_tests.sh
echo "✅ Pre-deploy check passed"


