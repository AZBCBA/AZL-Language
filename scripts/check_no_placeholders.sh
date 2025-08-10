#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "🔍 Checking for placeholders in code (TODO|FIXME|placeholder)"

PATTERN='(TODO|FIXME|placeholder)'
EXIT=0

# Only scan code files: .azl and .rs
while IFS= read -r -d '' f; do
  if grep -E -n -i "$PATTERN" "$f" >/dev/null; then
    echo "❌ Placeholder-like token found in $f" >&2
    grep -E -n -i "$PATTERN" "$f" >&2 || true
    EXIT=1
  fi
done < <(find . -type f \( -name '*.azl' -o -name '*.rs' \) -print0)

if [ "$EXIT" -ne 0 ]; then
  echo "❌ Placeholder check failed" >&2
  exit 1
fi

echo "✅ No placeholders found in code"

