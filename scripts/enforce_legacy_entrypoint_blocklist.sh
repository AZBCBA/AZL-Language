#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "[blocklist] verifying native-only guard coverage"

if ! rg -q "blocked by AZL_NATIVE_ONLY=1" scripts/azl; then
  echo "ERROR: scripts/azl does not block legacy run path under AZL_NATIVE_ONLY=1"
  exit 81
fi

set +e
AZL_NATIVE_ONLY=1 bash scripts/azl run smoke_test.azl >/tmp/azl_block_runner.out 2>&1
runner_rc=$?
set -e

if [ "$runner_rc" -ne 64 ]; then
  echo "ERROR: scripts/azl run returned ${runner_rc}, expected 64"
  exit 84
fi

echo "[blocklist] legacy entrypoint blocklist passed"
