#!/usr/bin/env bash
# Second pass after organize: scan archived + canonical trees for patterns useful to the AZL language
# (components, listeners, error system, policy/LLM hooks). Output is a human review report — no auto-import.
#
# Requires: ripgrep (rg)
#
# Env:
#   AZL_BENEFIT_SCAN_OUT   Optional path for report (default: .azl/quarantine/language_benefit_scan_<UTC>.txt)
#
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR" || die "cannot cd to $ROOT_DIR"

command -v rg >/dev/null 2>&1 || die "ripgrep (rg) is required"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/azl_local_layout.sh"

STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
OUT="${AZL_BENEFIT_SCAN_OUT:-${AZL_QUARANTINE_DIR}/language_benefit_scan_${STAMP}.txt}"
mkdir -p "$(dirname "$OUT")"
mkdir -p "${AZL_QUARANTINE_DIR}"

RG_GLOB_AZL=(--glob '*.azl')
SCAN_PATHS=(
  "$ROOT_DIR/project"
  "$ROOT_DIR/azl"
  "$ROOT_DIR/azme"
  "$ROOT_DIR/examples"
  "$AZL_VAR/archive/repo_root"
)

{
  echo "AZL language benefit scan (human review)"
  echo "Generated (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "ROOT_DIR: $ROOT_DIR"
  echo ""
  echo "=== 1) component :: declarations (count by file) — archived + examples + azl/azme ==="
  for p in "${SCAN_PATHS[@]}"; do
    if [[ -d "$p" ]]; then
      echo "--- path: $p ---"
      rg -n --no-heading '^[[:space:]]*component[[:space:]]+::' "${RG_GLOB_AZL[@]}" "$p" 2>/dev/null | head -200 || true
      echo ""
    fi
  done

  echo "=== 2) ::error.system / policy / ollama / sysproxy (sample hits) ==="
  for p in "${SCAN_PATHS[@]}"; do
    [[ -d "$p" ]] || continue
    echo "--- path: $p ---"
    rg -n --no-heading '::error\.system|policy_infer|/api/ollama|@sysproxy|build\.daemon\.enterprise' "${RG_GLOB_AZL[@]}" "$p" 2>/dev/null | head -120 || true
    echo ""
  done

  echo "=== 3) Root *.azl (still at repo root) — quick component list ==="
  shopt -s nullglob
  for f in "$ROOT_DIR"/*.azl; do
    [[ -f "$f" ]] || continue
    echo "# $(basename "$f")"
    rg -n --no-heading '^[[:space:]]*component[[:space:]]+::' "$f" 2>/dev/null || true
  done
  echo ""

  echo "=== 4) JSON under project/repo_root/json (names only) ==="
  if [[ -d "$ROOT_DIR/project/repo_root/json" ]]; then
    find "$ROOT_DIR/project/repo_root/json" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort
  fi
  echo ""

  echo "=== How to use ==="
  echo "Promote ideas manually: copy vetted snippets into azl/ or docs/ with full contract tests."
  echo "Do not treat this scan as authoritative security or licensing review."
} >"$OUT"

ln -sf "$(basename "$OUT")" "${AZL_QUARANTINE_DIR}/language_benefit_scan_LATEST.txt" 2>/dev/null || true

echo "Wrote: $OUT"
echo "Symlink: ${AZL_QUARANTINE_DIR}/language_benefit_scan_LATEST.txt"
cat "$OUT"
