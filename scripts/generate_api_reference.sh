#!/usr/bin/env bash
# Generate API reference from AZL component exports
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

OUT="${1:-docs/API_REFERENCE.md}"
mkdir -p "$(dirname "$OUT")"

{
  echo "# AZL API Reference"
  echo ""
  echo "Auto-generated from component definitions. Run \`bash scripts/generate_api_reference.sh\` to update."
  echo ""

  for f in azl/core/error_system.azl azl/core/memory/memory.azl azl/memory/lha3_quantum_memory.azl azl/quantum/memory/lha3_quantum_engine.azl azl/core/neural/neural.azl; do
    [ -f "$f" ] || continue
    comp="$(rg -o 'component\s+(::[A-Za-z0-9_.]+)' "$f" 2>/dev/null | head -1 | sed 's/component[[:space:]]*//' || true)"
    [ -n "$comp" ] || continue
    echo "## $comp"
    echo ""
    echo "**File:** \`$f\`"
    echo ""
    echo "### Events emitted"
    rg -o 'emit\s+["\"]?([A-Za-z0-9_.]+)' "$f" 2>/dev/null | sed 's/emit[[:space:]]*["\"]*//;s/["\"]*$//' | sort -u | while read -r ev; do echo "- \`$ev\`"; done
    echo ""
    echo "### Events listened"
    rg -o 'listen for ["\"]?([A-Za-z0-9_.]+)' "$f" 2>/dev/null | sed 's/listen for[[:space:]]*["\"]*//;s/["\"]*$//' | sort -u | while read -r ev; do echo "- \`$ev\`"; done
    echo ""
  done
} > "$OUT"

echo "✅ API reference written to $OUT"
