#!/usr/bin/env bash
# Systematic AZL test runner (strict mode)
# - Runs all tests under azl/testing/** and selected root tests
# - Uses the Python AZL runner as execution harness
# - Summarizes pass/fail/skip counts without placeholders or mocks
set -euo pipefail
cd "$(dirname "$0")/.."

export AZL_STRICT=1

# Collect tests
mapfile -t TEST_FILES < <(find azl/testing -type f -name '*.azl' -print | sort)
# Include top-level tests that match pattern
if [ -f test_integration_final.azl ]; then
  TEST_FILES+=("test_integration_final.azl")
fi

TOTAL=${#TEST_FILES[@]}
RAN=0
PASSED=0
FAILED=0
SKIPPED=0

printf "\n🧪 Running %d AZL tests (strict mode)\n" "$TOTAL"

for t in "${TEST_FILES[@]}"; do
  echo -e "\n=== RUN $t ==="
  OUT_FILE="/tmp/azl_test_$(basename "$t" .azl)_$$.log"
  # Run via Python harness; capture output
  if ! /usr/bin/env python3 azl_runner.py "$t" >"$OUT_FILE" 2>&1; then
    # Harness error: mark as failed
    echo "❌ Harness failed for $t"
    FAILED=$((FAILED+1))
    continue
  fi
  # Decide outcome
  if grep -q "No components found in file" "$OUT_FILE"; then
    echo "⏭️  Skipped (no components): $t"
    SKIPPED=$((SKIPPED+1))
    continue
  fi
  RAN=$((RAN+1))
  if grep -q "TESTS_FAIL" "$OUT_FILE"; then
    echo "❌ FAIL: $t"
    FAILED=$((FAILED+1))
  elif grep -q "✅ AZL Integration Test Complete!" "$OUT_FILE"; then
    echo "✅ PASS: $t"
    PASSED=$((PASSED+1))
  else
    echo "❌ FAIL (no completion marker): $t"
    FAILED=$((FAILED+1))
  fi
  # Stream test log
  cat "$OUT_FILE"
  rm -f "$OUT_FILE"
done

echo "\n======================================"
echo "📊 Summary"
echo "  Total discovered: $TOTAL"
echo "  Ran:             $RAN"
echo "  Passed:          $PASSED"
echo "  Failed:          $FAILED"
echo "  Skipped:         $SKIPPED"

# Non-zero exit on failures
[ "$FAILED" -eq 0 ] || exit 1


