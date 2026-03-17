#!/usr/bin/env bash
# AZL Execute Script - Simple executor for AZL files
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <azl_file>" >&2
  exit 1
fi

AZL_FILE="$1"
if [ ! -f "$AZL_FILE" ]; then
  echo "AZL file not found: $AZL_FILE" >&2
  exit 1
fi

echo "🚀 AZL Execute Script"
echo "📁 File: $AZL_FILE"

# Create a simple test execution environment
echo "🔧 Setting up execution environment..."

# Real execution using Python AZL runner (pure AZL interpreter path)
if command -v python3 >/dev/null 2>&1; then
  echo "🧠 Executing via azl_runner.py"
  exec python3 azl_runner.py "$AZL_FILE"
fi

echo "❌ python3 not found; cannot execute AZL file"
exit 1

