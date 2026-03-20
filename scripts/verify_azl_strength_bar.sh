#!/usr/bin/env bash
# Provable "strength bar": native gates + minimal live verify + enterprise combined live verify.
# Prereqs: ripgrep (rg), jq (gate 0 manifest + gh ref encoding contract), python3, gcc — same family as check_azl_native_gates.sh.
#
# Exit codes (script-owned): 1 repo root, 2 rg, 3 jq, 4 python3, 5 gcc; 10 gates, 11 verify_native, 12 verify_enterprise.
# See docs/ERROR_SYSTEM.md § Strength bar.
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

if ! command -v jq >/dev/null 2>&1; then
  err "jq is required (gate 0 self_check_release_helpers + gh_verify_remote_tag URI encoding)"
  exit 3
fi

if ! command -v python3 >/dev/null 2>&1; then
  err "python3 is required"
  exit 4
fi

if ! command -v gcc >/dev/null 2>&1; then
  err "gcc is required (gate D builds azl-native-engine)"
  exit 5
fi

echo "[AZL_STRENGTH_BAR] step 1/3: scripts/check_azl_native_gates.sh"
set +e
bash scripts/check_azl_native_gates.sh
rc1=$?
set -e
if [ "$rc1" -ne 0 ]; then
  err "step 1 failed: native gates exited $rc1"
  exit 10
fi

echo "[AZL_STRENGTH_BAR] step 2/3: scripts/verify_native_runtime_live.sh"
set +e
bash scripts/verify_native_runtime_live.sh
rc2=$?
set -e
if [ "$rc2" -ne 0 ]; then
  err "step 2 failed: verify_native_runtime_live exited $rc2"
  exit 11
fi

chmod +x scripts/verify_enterprise_native_http_live.sh 2>/dev/null || true
echo "[AZL_STRENGTH_BAR] step 3/3: scripts/verify_enterprise_native_http_live.sh"
set +e
bash scripts/verify_enterprise_native_http_live.sh
rc3=$?
set -e
if [ "$rc3" -ne 0 ]; then
  err "step 3 failed: verify_enterprise_native_http_live exited $rc3"
  exit 12
fi

echo "[AZL_STRENGTH_BAR] ok — see docs/AZL_DOCUMENTATION_CANON.md §1.7; for release use scripts/run_full_repo_verification.sh"
exit 0
