#!/usr/bin/env bash
# Systematic AZL examples runner (native mode)
# - Discovers example files under azl/examples and examples
# - For each file, boots native runtime with AZL_TARGET_FILE set
# - Classifies as PASS/FAIL by native gate success
set -euo pipefail
cd "$(dirname "$0")/.."

export AZL_STRICT=${AZL_STRICT:-1}

# Collect example files
mapfile -t EX_FILES < <( { \
  [ -d azl/examples ] && find azl/examples -type f -name '*.azl' -print; \
  [ -d examples ] && find examples -type f -name '*.azl' -print; \
} | sort )

TOTAL=${#EX_FILES[@]}
RAN=0
PASSED=0
FAILED=0
SKIPPED=0

printf "\n📚 Running %d AZL examples (strict mode)\n" "$TOTAL"

for f in "${EX_FILES[@]}"; do
  echo -e "\n=== RUN $f ==="
  OUT_FILE="/tmp/azl_example_$(basename "$f" .azl)_$$.log"
  if AZL_TARGET_FILE="$f" bash scripts/start_azl_native_mode.sh >"$OUT_FILE" 2>&1; then
    :
  else
    echo "❌ FAIL: $f"
    FAILED=$((FAILED+1))
    continue
  fi

  RAN=$((RAN+1))

  if [ -s "$OUT_FILE" ]; then
    echo "--- output ---"
    cat "$OUT_FILE"
    echo "--------------"
  fi

  echo "✅ PASS: $f"
  PASSED=$((PASSED+1))
done

echo -e "\n📊 Examples summary: ran=$RAN pass=$PASSED fail=$FAILED skip=$SKIPPED total=$TOTAL"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0


