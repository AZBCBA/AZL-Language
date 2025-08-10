#!/bin/bash
# Daily Supervision Check - Automated Quality Gate Verification
# Run this script daily to verify agent progress and code quality

set -e

echo "🔍 DAILY SUPERVISION CHECK - $(date)"
echo "========================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

FAILED_CHECKS=0
TOTAL_CHECKS=0

check_result() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ PASS${NC}: $2"
    else
        echo -e "${RED}❌ FAIL${NC}: $2"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
}

echo ""
echo "🚫 QUALITY GATE 1: ZERO PLACEHOLDERS CHECK"
echo "-------------------------------------------"
PLACEHOLDER_COUNT=$(find . -name "*.azl" -o -name "*.rs" | xargs grep -i "placeholder\|todo\|fixme" 2>/dev/null | wc -l)
check_result $([ $PLACEHOLDER_COUNT -eq 0 ] && echo 0 || echo 1) "Zero placeholders (found: $PLACEHOLDER_COUNT)"

echo ""
echo "🏗️ QUALITY GATE 2: BUILD AND COMPILE CHECK"
echo "-------------------------------------------"
cargo build --quiet > /dev/null 2>&1
check_result $? "Code compiles without errors"

cargo clippy --quiet -- -D warnings > /dev/null 2>&1
check_result $? "Clippy passes without warnings"

cargo fmt --check > /dev/null 2>&1
check_result $? "Code formatting is correct"

echo ""
echo "🧪 QUALITY GATE 3: TEST SUITE CHECK"
echo "-----------------------------------"
TEST_COUNT=$(cargo test --quiet 2>&1 | grep -E "test result:" | grep -oE "[0-9]+ passed" | grep -oE "[0-9]+" || echo "0")
check_result $([ $TEST_COUNT -gt 4 ] && echo 0 || echo 1) "Minimum 5 tests exist (found: $TEST_COUNT)"

cargo test --quiet > /dev/null 2>&1
check_result $? "All tests pass"

echo ""
echo "⚡ QUALITY GATE 4: RUNTIME EXECUTION CHECK"
echo "-----------------------------------------"
# Test basic bootstrap
timeout 30 cargo run --quiet -- bootstrap > /dev/null 2>&1
check_result $? "Bootstrap executes successfully"

# Test event system functionality
cat > test_events_temp.azl << 'EOF'
component ::test.supervision {
  init {
    set ::test_var = "supervision_test"
    say "Init executed"
  }
  
  behavior {
    say "Behavior executed"
    emit "test_event"
  }
  
  listen for "test_event" {
    say "Event handler executed"
  }
}
EOF

RUNTIME_OUTPUT=$(timeout 30 AZL_STRICT=1 cargo run --quiet -- run test_events_temp.azl 2>&1 || echo "FAILED")
rm -f test_events_temp.azl

echo "$RUNTIME_OUTPUT" | grep -q "Init executed"
check_result $? "Init blocks execute"

echo "$RUNTIME_OUTPUT" | grep -q "Behavior executed"
check_result $? "Behavior blocks execute"

echo "$RUNTIME_OUTPUT" | grep -q "Event handler executed"
check_result $? "Event handlers execute"

echo ""
echo "🔒 QUALITY GATE 5: SECURITY CHECK"
echo "--------------------------------"
UNSAFE_COUNT=$(grep -r "unsafe\|transmute" src/ 2>/dev/null | wc -l)
check_result $([ $UNSAFE_COUNT -eq 0 ] && echo 0 || echo 1) "No unsafe code (found: $UNSAFE_COUNT instances)"

echo ""
echo "🚨 QUALITY GATE 6: ERROR HANDLING CHECK"
echo "--------------------------------------"
# Test division by zero handling
cat > test_errors_temp.azl << 'EOF'
component ::test.errors {
  init {
    set ::result = (1 / 0)
    say "No error thrown"
  }
}
EOF

ERROR_OUTPUT=$(timeout 10 AZL_STRICT=1 cargo run --quiet -- run test_errors_temp.azl 2>&1 || echo "ERROR_CAUGHT")
rm -f test_errors_temp.azl

echo "$ERROR_OUTPUT" | grep -q "ERROR_CAUGHT\|error\|Error"
check_result $? "Division by zero throws error"

echo ""
echo "📊 QUALITY GATE 7: DOCUMENTATION ACCURACY"
echo "----------------------------------------"
DOC_VERIFIED_COUNT=$(find docs/ -name "*.md" | xargs grep -l "\[VERIFIED\]" 2>/dev/null | wc -l)
DOC_TOTAL_COUNT=$(find docs/ -name "*.md" | wc -l)
DOC_PERCENTAGE=$(( (DOC_VERIFIED_COUNT * 100) / DOC_TOTAL_COUNT ))
check_result $([ $DOC_PERCENTAGE -gt 50 ] && echo 0 || echo 1) "Documentation >50% verified (${DOC_PERCENTAGE}%)"

echo ""
echo "=========================================="
echo "📋 SUPERVISION SUMMARY"
echo "=========================================="
echo "Total Checks: $TOTAL_CHECKS"
echo "Passed: $((TOTAL_CHECKS - FAILED_CHECKS))"
echo "Failed: $FAILED_CHECKS"

if [ $FAILED_CHECKS -eq 0 ]; then
    echo -e "${GREEN}🎉 ALL QUALITY GATES PASSED${NC}"
    exit 0
elif [ $FAILED_CHECKS -le 2 ]; then
    echo -e "${YELLOW}⚠️ MINOR ISSUES FOUND - NEEDS ATTENTION${NC}"
    exit 1
else
    echo -e "${RED}🚨 CRITICAL ISSUES FOUND - IMMEDIATE ACTION REQUIRED${NC}"
    echo ""
    echo "🚨 ESCALATION REQUIRED:"
    echo "- Notify all agents immediately"
    echo "- Stop all non-critical work"
    echo "- Focus on failing quality gates"
    exit 2
fi
