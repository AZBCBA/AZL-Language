#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

export AZL_STRICT=1
echo "🧪 Running pure AZL tests via Python harness (strict mode)"

tests=(
  "azl/testing/integration/test_arithmetic.azl"
  "azl/testing/integration/test_strict_mode_div_zero.azl"
  "test_integration_final.azl"
)

fail=0
for t in "${tests[@]}"; do
  if [ -f "$t" ]; then
    echo "\n=== RUN $t ==="
    if ! python3 azl_runner.py "$t" | cat; then
      echo "❌ FAIL: $t"
      fail=1
    else
      echo "✅ PASS: $t"
    fi
  fi
done

exit $fail

