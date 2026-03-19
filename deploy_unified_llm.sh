#!/usr/bin/env bash
set -euo pipefail

echo "AZL deploy path is native-only."
echo "Running canonical native release gates..."
bash scripts/enforce_canonical_stack.sh
bash scripts/check_azl_native_gates.sh
bash scripts/enforce_legacy_entrypoint_blocklist.sh
bash scripts/verify_native_runtime_live.sh
echo "Native release gates passed."
