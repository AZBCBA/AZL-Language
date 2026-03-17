#!/usr/bin/env bash
# Run AZL smoke and integration tests. Use from repo root: ./scripts/run_tests.sh
set -e
cd "$(dirname "$0")/.."
ROOT="$PWD"
PASS=0
FAIL=0
run_one() {
  local name="$1"
  local file="$2"
  if python3 azl_runner.py "$file" > /tmp/azl_test_out.txt 2>&1; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
    return 0
  else
    echo "  FAIL: $name"
    FAIL=$((FAIL + 1))
    tail -20 /tmp/azl_test_out.txt
    return 1
  fi
}
echo "Running AZL tests..."
run_one "smoke_test.azl" "smoke_test.azl"
run_one "test_hello" "azl/testing/integration/test_hello.azl"
run_one "test_arithmetic" "azl/testing/integration/test_arithmetic.azl"
echo "---"
echo "Done: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
