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
chmod +x scripts/verify_azl_use_vm_path.sh || true
bash scripts/verify_azl_use_vm_path.sh

chmod +x scripts/verify_native_bundle_excludes_host_integrations.sh 2>/dev/null || true
bash scripts/verify_native_bundle_excludes_host_integrations.sh

chmod +x scripts/build_azlpack.sh scripts/verify_azlpack_local.sh scripts/verify_lsp_smoke.sh 2>/dev/null || true
bash scripts/verify_azlpack_local.sh
bash scripts/verify_lsp_smoke.sh

echo "✅ All tests completed"
