#!/bin/bash
# Performance Baseline and Monitoring Script
# Establishes performance baselines and monitors for regressions

set -e

echo "⚡ PERFORMANCE BASELINE ESTABLISHMENT"
echo "===================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Performance thresholds (in milliseconds)
BOOTSTRAP_THRESHOLD=5000
SIMPLE_COMPONENT_THRESHOLD=100
EVENT_PROCESSING_THRESHOLD=1000
MEMORY_LIMIT_MB=100

# Results storage
RESULTS_FILE="performance_results_$(date +%Y%m%d_%H%M%S).json"
BASELINE_FILE="performance_baseline.json"

echo "📊 Starting performance benchmarks..."
echo "Results will be saved to: $RESULTS_FILE"

# Initialize results JSON
echo "{" > "$RESULTS_FILE"
echo "  \"timestamp\": \"$(date -Iseconds)\"," >> "$RESULTS_FILE"
echo "  \"benchmarks\": {" >> "$RESULTS_FILE"

# Test 1: Bootstrap Performance
echo ""
echo -e "${BLUE}🚀 Test 1: Bootstrap Performance${NC}"
echo "Testing AZL runtime bootstrap time..."

cat > test_bootstrap_perf.azl << 'EOF'
component ::perf.bootstrap {
  init {
    set ::startup_time = current_timestamp()
    say "Bootstrap performance test"
  }
}
EOF

BOOTSTRAP_START=$(date +%s%3N)
timeout 30 cargo run --quiet --release -- bootstrap > /dev/null 2>&1 || echo "Bootstrap timeout"
BOOTSTRAP_END=$(date +%s%3N)
BOOTSTRAP_TIME=$((BOOTSTRAP_END - BOOTSTRAP_START))

echo "    Bootstrap time: ${BOOTSTRAP_TIME}ms"
echo "    Threshold: ${BOOTSTRAP_THRESHOLD}ms"

if [ $BOOTSTRAP_TIME -lt $BOOTSTRAP_THRESHOLD ]; then
    echo -e "    ${GREEN}✅ PASS${NC}: Bootstrap within threshold"
    BOOTSTRAP_STATUS="PASS"
else
    echo -e "    ${RED}❌ FAIL${NC}: Bootstrap too slow"
    BOOTSTRAP_STATUS="FAIL"
fi

echo "    \"bootstrap\": {" >> "$RESULTS_FILE"
echo "      \"time_ms\": $BOOTSTRAP_TIME," >> "$RESULTS_FILE"
echo "      \"threshold_ms\": $BOOTSTRAP_THRESHOLD," >> "$RESULTS_FILE"
echo "      \"status\": \"$BOOTSTRAP_STATUS\"" >> "$RESULTS_FILE"
echo "    }," >> "$RESULTS_FILE"

rm -f test_bootstrap_perf.azl

# Test 2: Simple Component Execution
echo ""
echo -e "${BLUE}⚙️ Test 2: Simple Component Execution${NC}"
echo "Testing simple component loading and execution..."

cat > test_simple_perf.azl << 'EOF'
component ::perf.simple {
  init {
    set ::value = 42
    set ::result = (::value * 2)
  }
}
EOF

SIMPLE_START=$(date +%s%3N)
timeout 10 cargo run --quiet --release -- run test_simple_perf.azl > /dev/null 2>&1 || echo "Simple test timeout"
SIMPLE_END=$(date +%s%3N)
SIMPLE_TIME=$((SIMPLE_END - SIMPLE_START))

echo "    Simple component time: ${SIMPLE_TIME}ms"
echo "    Threshold: ${SIMPLE_COMPONENT_THRESHOLD}ms"

if [ $SIMPLE_TIME -lt $SIMPLE_COMPONENT_THRESHOLD ]; then
    echo -e "    ${GREEN}✅ PASS${NC}: Simple component within threshold"
    SIMPLE_STATUS="PASS"
else
    echo -e "    ${RED}❌ FAIL${NC}: Simple component too slow"
    SIMPLE_STATUS="FAIL"
fi

echo "    \"simple_component\": {" >> "$RESULTS_FILE"
echo "      \"time_ms\": $SIMPLE_TIME," >> "$RESULTS_FILE"
echo "      \"threshold_ms\": $SIMPLE_COMPONENT_THRESHOLD," >> "$RESULTS_FILE"
echo "      \"status\": \"$SIMPLE_STATUS\"" >> "$RESULTS_FILE"
echo "    }," >> "$RESULTS_FILE"

rm -f test_simple_perf.azl

# Test 3: Event Processing Performance
echo ""
echo -e "${BLUE}📡 Test 3: Event Processing Performance${NC}"
echo "Testing event system performance with multiple events..."

cat > test_events_perf.azl << 'EOF'
component ::perf.events {
  init {
    set ::counter = 0
  }
  
  behavior {
    set ::i = 0
    while (::i < 50) {
      emit "perf_event"
      set ::i = (::i + 1)
    }
  }
  
  listen for "perf_event" {
    set ::counter = (::counter + 1)
  }
}
EOF

EVENTS_START=$(date +%s%3N)
timeout 15 cargo run --quiet --release -- run test_events_perf.azl > /dev/null 2>&1 || echo "Events test timeout"
EVENTS_END=$(date +%s%3N)
EVENTS_TIME=$((EVENTS_END - EVENTS_START))

echo "    Event processing time: ${EVENTS_TIME}ms"
echo "    Threshold: ${EVENT_PROCESSING_THRESHOLD}ms"

if [ $EVENTS_TIME -lt $EVENT_PROCESSING_THRESHOLD ]; then
    echo -e "    ${GREEN}✅ PASS${NC}: Event processing within threshold"
    EVENTS_STATUS="PASS"
else
    echo -e "    ${RED}❌ FAIL${NC}: Event processing too slow"
    EVENTS_STATUS="FAIL"
fi

echo "    \"event_processing\": {" >> "$RESULTS_FILE"
echo "      \"time_ms\": $EVENTS_TIME," >> "$RESULTS_FILE"
echo "      \"threshold_ms\": $EVENT_PROCESSING_THRESHOLD," >> "$RESULTS_FILE"
echo "      \"status\": \"$EVENTS_STATUS\"" >> "$RESULTS_FILE"
echo "    }," >> "$RESULTS_FILE"

rm -f test_events_perf.azl

# Test 4: Memory Usage Monitoring
echo ""
echo -e "${BLUE}💾 Test 4: Memory Usage Monitoring${NC}"
echo "Testing memory usage during component execution..."

# Create a component that uses more memory
cat > test_memory_perf.azl << 'EOF'
component ::perf.memory {
  init {
    set ::large_array = []
    set ::i = 0
    while (::i < 1000) {
      set ::large_array = (::large_array + ["item_" + ::i])
      set ::i = (::i + 1)
    }
  }
}
EOF

# Monitor memory usage (simplified - in production would use more sophisticated monitoring)
MEMORY_BEFORE=$(ps -o pid,vsz,rss,comm | grep -E "(cargo|azl)" | awk '{sum += $3} END {print sum}' || echo "0")

timeout 10 cargo run --quiet --release -- run test_memory_perf.azl > /dev/null 2>&1 || echo "Memory test timeout"

MEMORY_AFTER=$(ps -o pid,vsz,rss,comm | grep -E "(cargo|azl)" | awk '{sum += $3} END {print sum}' || echo "0")
MEMORY_USED=$((MEMORY_AFTER - MEMORY_BEFORE))
MEMORY_USED_MB=$((MEMORY_USED / 1024))

echo "    Memory used: ${MEMORY_USED_MB}MB"
echo "    Memory limit: ${MEMORY_LIMIT_MB}MB"

if [ $MEMORY_USED_MB -lt $MEMORY_LIMIT_MB ]; then
    echo -e "    ${GREEN}✅ PASS${NC}: Memory usage within limit"
    MEMORY_STATUS="PASS"
else
    echo -e "    ${RED}❌ FAIL${NC}: Memory usage too high"
    MEMORY_STATUS="FAIL"
fi

echo "    \"memory_usage\": {" >> "$RESULTS_FILE"
echo "      \"used_mb\": $MEMORY_USED_MB," >> "$RESULTS_FILE"
echo "      \"limit_mb\": $MEMORY_LIMIT_MB," >> "$RESULTS_FILE"
echo "      \"status\": \"$MEMORY_STATUS\"" >> "$RESULTS_FILE"
echo "    }," >> "$RESULTS_FILE"

rm -f test_memory_perf.azl

# Test 5: Compilation Performance
echo ""
echo -e "${BLUE}🔨 Test 5: Compilation Performance${NC}"
echo "Testing Rust compilation time..."

COMPILE_START=$(date +%s%3N)
cargo build --release --quiet > /dev/null 2>&1
COMPILE_END=$(date +%s%3N)
COMPILE_TIME=$((COMPILE_END - COMPILE_START))

echo "    Compilation time: ${COMPILE_TIME}ms"

echo "    \"compilation\": {" >> "$RESULTS_FILE"
echo "      \"time_ms\": $COMPILE_TIME," >> "$RESULTS_FILE"
echo "      \"status\": \"MEASURED\"" >> "$RESULTS_FILE"
echo "    }" >> "$RESULTS_FILE"

# Close JSON structure
echo "  }," >> "$RESULTS_FILE"

# Overall assessment
TOTAL_TESTS=4
PASSED_TESTS=0
[ "$BOOTSTRAP_STATUS" = "PASS" ] && PASSED_TESTS=$((PASSED_TESTS + 1))
[ "$SIMPLE_STATUS" = "PASS" ] && PASSED_TESTS=$((PASSED_TESTS + 1))
[ "$EVENTS_STATUS" = "PASS" ] && PASSED_TESTS=$((PASSED_TESTS + 1))
[ "$MEMORY_STATUS" = "PASS" ] && PASSED_TESTS=$((PASSED_TESTS + 1))

PASS_PERCENTAGE=$((PASSED_TESTS * 100 / TOTAL_TESTS))

echo "  \"summary\": {" >> "$RESULTS_FILE"
echo "    \"total_tests\": $TOTAL_TESTS," >> "$RESULTS_FILE"
echo "    \"passed_tests\": $PASSED_TESTS," >> "$RESULTS_FILE"
echo "    \"pass_percentage\": $PASS_PERCENTAGE," >> "$RESULTS_FILE"
echo "    \"overall_status\": \"$([ $PASS_PERCENTAGE -ge 75 ] && echo "ACCEPTABLE" || echo "NEEDS_IMPROVEMENT")\"" >> "$RESULTS_FILE"
echo "  }" >> "$RESULTS_FILE"
echo "}" >> "$RESULTS_FILE"

echo ""
echo "===================================="
echo "📊 PERFORMANCE SUMMARY"
echo "===================================="
echo "Total Tests: $TOTAL_TESTS"
echo "Passed Tests: $PASSED_TESTS"
echo "Pass Rate: $PASS_PERCENTAGE%"

if [ $PASS_PERCENTAGE -ge 75 ]; then
    echo -e "Overall Status: ${GREEN}✅ ACCEPTABLE${NC}"
    OVERALL_EXIT=0
elif [ $PASS_PERCENTAGE -ge 50 ]; then
    echo -e "Overall Status: ${YELLOW}⚠️ NEEDS IMPROVEMENT${NC}"
    OVERALL_EXIT=1
else
    echo -e "Overall Status: ${RED}❌ CRITICAL PERFORMANCE ISSUES${NC}"
    OVERALL_EXIT=2
fi

echo ""
echo "📈 Performance Recommendations:"
if [ "$BOOTSTRAP_STATUS" != "PASS" ]; then
    echo "  - Optimize bootstrap process (current: ${BOOTSTRAP_TIME}ms, target: <${BOOTSTRAP_THRESHOLD}ms)"
fi
if [ "$SIMPLE_STATUS" != "PASS" ]; then
    echo "  - Optimize component parsing and execution (current: ${SIMPLE_TIME}ms, target: <${SIMPLE_COMPONENT_THRESHOLD}ms)"
fi
if [ "$EVENTS_STATUS" != "PASS" ]; then
    echo "  - Optimize event processing system (current: ${EVENTS_TIME}ms, target: <${EVENT_PROCESSING_THRESHOLD}ms)"
fi
if [ "$MEMORY_STATUS" != "PASS" ]; then
    echo "  - Optimize memory usage (current: ${MEMORY_USED_MB}MB, target: <${MEMORY_LIMIT_MB}MB)"
fi

# Save as baseline if this is the first run or if performance improved
if [ ! -f "$BASELINE_FILE" ] || [ $PASS_PERCENTAGE -gt 75 ]; then
    cp "$RESULTS_FILE" "$BASELINE_FILE"
    echo ""
    echo "💾 Performance baseline updated"
fi

echo ""
echo "📁 Results saved to: $RESULTS_FILE"
echo "📁 Baseline file: $BASELINE_FILE"

exit $OVERALL_EXIT
