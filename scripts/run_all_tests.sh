#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "🧪 Running strict AZL test suite..."
chmod +x scripts/run_tests.sh || true
./scripts/run_tests.sh

echo "🧪 Running mandatory native gate checks..."
chmod +x scripts/check_azl_native_gates.sh || true
chmod +x scripts/verify_native_runtime_live.sh || true
chmod +x scripts/enforce_legacy_entrypoint_blocklist.sh || true
bash scripts/check_azl_native_gates.sh
bash scripts/enforce_legacy_entrypoint_blocklist.sh
bash scripts/verify_native_runtime_live.sh
bash scripts/verify_quantum_lha3_stack.sh
bash scripts/verify_azl_grammar_conformance.sh

echo "✅ All tests completed"
