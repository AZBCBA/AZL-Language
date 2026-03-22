#!/usr/bin/env bash
# Run native AZL release checks. Use from repo root: ./scripts/run_tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Running native AZL tests..."
chmod +x \
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
  scripts/verify_quantum_crypto_demo_tier_contract.sh \
  2>/dev/null || true
bash scripts/verify_repertoire_field_surface_contract.sh
bash scripts/verify_rust_offtree_doc_contract.sh
bash scripts/verify_azl_literal_codec_container_doc_contract.sh
bash scripts/verify_azl_literal_codec_roundtrip.sh
bash scripts/verify_azl_core_engine.sh
bash scripts/enforce_canonical_stack.sh
bash scripts/check_azl_native_gates.sh
bash scripts/enforce_legacy_entrypoint_blocklist.sh
bash scripts/verify_native_runtime_live.sh
bash scripts/verify_enterprise_native_http_live.sh
bash scripts/verify_quantum_lha3_stack.sh
bash scripts/verify_azl_grammar_conformance.sh
echo "---"
echo "Done: native checks passed"
