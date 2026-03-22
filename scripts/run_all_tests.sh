#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "🧪 Running strict AZL test suite..."
chmod +x \
  scripts/run_tests.sh \
  scripts/self_check_release_helpers.sh \
  scripts/enforce_canonical_stack.sh \
  scripts/check_azl_native_gates.sh \
  scripts/enforce_legacy_entrypoint_blocklist.sh \
  scripts/verify_native_runtime_live.sh \
  scripts/verify_enterprise_native_http_live.sh \
  scripts/verify_quantum_lha3_stack.sh \
  scripts/verify_azl_grammar_conformance.sh \
  scripts/azl_teardown_verify_native_stack.sh \
  scripts/verify_repertoire_field_surface_contract.sh \
  scripts/verify_rust_offtree_doc_contract.sh \
  scripts/verify_azl_literal_codec_container_doc_contract.sh \
  scripts/verify_azl_literal_codec_roundtrip.sh \
  scripts/verify_azl_core_engine.sh \
  scripts/build_azl_core_engine.sh \
  2>/dev/null || true
./scripts/run_tests.sh

# Native release slice (enforce + gates + blocklist + minimal/enterprise HTTP + qlha3 + grammar) is owned by scripts/run_tests.sh.

chmod +x scripts/test_azl_use_vm_path.sh scripts/check_azl_vm_tree_parity.py 2>/dev/null || true
bash scripts/test_azl_use_vm_path.sh

chmod +x scripts/verify_native_bundle_excludes_host_integrations.sh 2>/dev/null || true
bash scripts/verify_native_bundle_excludes_host_integrations.sh

chmod +x scripts/build_azlpack.sh scripts/verify_azlpack_local.sh scripts/verify_lsp_smoke.sh scripts/test_lsp_jump_to_def.sh 2>/dev/null || true
bash scripts/verify_azlpack_local.sh
bash scripts/verify_lsp_smoke.sh
bash scripts/test_lsp_jump_to_def.sh

echo "✅ All tests completed"
