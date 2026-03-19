#!/usr/bin/env bash
# Provable "strength bar": native gates + live runtime /api/llm/capabilities probe.
# Prereqs: ripgrep (rg), python3, gcc — same as scripts/check_azl_native_gates.sh.
#
# This does NOT replace scripts/run_full_repo_verification.sh
# (no enforce_canonical_stack, enforce_legacy_entrypoint_blocklist, run_all_tests).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

err() {
  echo "ERROR[AZL_STRENGTH_BAR]: $*" >&2
}

if [ ! -f "scripts/check_azl_native_gates.sh" ]; then
  err "must run from repo root (missing scripts/check_azl_native_gates.sh)"
  exit 1
fi

if ! command -v rg >/dev/null 2>&1; then
  err "ripgrep (rg) is required (native gates depend on it)"
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  err "python3 is required"
  exit 3
fi

if ! command -v gcc >/dev/null 2>&1; then
  err "gcc is required (gate D builds azl-native-engine)"
  exit 4
fi

echo "[AZL_STRENGTH_BAR] step 1/2: scripts/check_azl_native_gates.sh"
set +e
bash scripts/check_azl_native_gates.sh
rc1=$?
set -e
if [ "$rc1" -ne 0 ]; then
  err "step 1 failed: native gates exited $rc1"
  exit 10
fi

echo "[AZL_STRENGTH_BAR] step 2/2: scripts/verify_native_runtime_live.sh"
set +e
bash scripts/verify_native_runtime_live.sh
rc2=$?
set -e
if [ "$rc2" -ne 0 ]; then
  err "step 2 failed: verify_native_runtime_live exited $rc2"
  exit 11
fi

echo "[AZL_STRENGTH_BAR] ok — see docs/AZL_DOCUMENTATION_CANON.md §1.7; for release use scripts/run_full_repo_verification.sh"
exit 0
