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
echo "🔧 Setting up native execution environment..."
export AZL_TARGET_FILE="$AZL_FILE"
echo "🧠 Executing via canonical native runtime"
exec bash scripts/start_azl_native_mode.sh

