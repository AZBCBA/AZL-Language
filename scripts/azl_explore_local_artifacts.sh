#!/usr/bin/env bash
# Explore local AZL-Language artifacts before any archive/reorganize pass.
# - Lists project-root files, .azl root entries, symlinks, temp pools, external data symlinks.
# - For each basename, counts repo text references (ripgrep fixed-string), excluding .git and .azl.
# - Marks git-tracked paths where applicable.
#
# Does NOT move, delete, or archive anything.
#
# Requires: ripgrep (rg), git (optional: without git, tracked column is "unknown")
#
# Env:
#   AZL_INVENTORY_OUT   If set, write the full report to this file (directory must exist or be creatable).
#   AZL_TMP_SCAN_DIRS   Space-separated dirs to scan for names starting with azl (default: /tmp /mnt/ssd4t/tmp)
#   AZL_RG_EXTRA_GLOB   Extra rg --glob exclusions (repeatable in env not supported; edit script if needed)
#
set -euo pipefail

die() {
  echo "ERROR: $*" >&2
  exit 1
}

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR" || die "cannot cd to ROOT_DIR=$ROOT_DIR"

command -v rg >/dev/null 2>&1 || die "ripgrep (rg) is required. Install ripgrep, then re-run."

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/azl_local_layout.sh"

GIT_OK=0
if command -v git >/dev/null 2>&1 && git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_OK=1
else
  echo "WARNING: git not available or not a work tree; git_tracked column will be 'unknown'" >&2
fi

TMP_SCAN_DIRS="${AZL_TMP_SCAN_DIRS:-/tmp /mnt/ssd4t/tmp}"

REPORT_TMP="$(mktemp)"
trap 'rm -f "$REPORT_TMP"' EXIT

{
  echo "AZL local artifact exploration report"
  echo "Generated (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "ROOT_DIR: $ROOT_DIR"
  echo "AZL_VAR: $AZL_VAR"
  echo ""
  echo "Heuristic: ref_files = number of tracked/untracked SOURCE files under ROOT_DIR (except .git/.azl)"
  echo "           whose contents contain the basename as a fixed string. Dynamic paths are NOT detected."
  echo "Short basenames (<3 chars) skip ref scan (marked ref_skip)."
  echo ""
} >"$REPORT_TMP"

# shellcheck disable=SC2312
ref_file_count() {
  local base="$1"
  if ((${#base} < 3)); then
    echo "ref_skip"
    return 0
  fi
  local n
  n="$(rg -F -l "$base" --glob '!.git/**' --glob '!.azl/**' "$ROOT_DIR" 2>/dev/null | wc -l)"
  echo "$n" | tr -d ' '
}

git_tracked_file() {
  local rel="$1"
  if [[ "$GIT_OK" -ne 1 ]]; then
    echo "unknown"
    return 0
  fi
  if git -C "$ROOT_DIR" ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
    echo "yes"
  else
    echo "no"
  fi
}

human_size() {
  local p="$1"
  if [[ -f "$p" ]]; then
    stat -c '%s' "$p" 2>/dev/null || stat -f '%z' "$p" 2>/dev/null || echo "?"
  elif [[ -d "$p" ]]; then
    du -sb "$p" 2>/dev/null | awk '{print $1}' || echo "?"
  else
    echo "0"
  fi
}

mtime_iso() {
  local p="$1"
  stat -c '%y' "$p" 2>/dev/null | cut -c1-19 || stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%S' "$p" 2>/dev/null || echo "?"
}

{
  echo "================================================================================"
  echo "SECTION 1 — Project root: regular files (depth 1)"
  echo "================================================================================"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "basename" "bytes" "mtime" "git_tracked" "ref_files" "path"
  while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    sz="$(human_size "$f")"
    mt="$(mtime_iso "$f")"
    gt="$(git_tracked_file "$base")"
    rf="$(ref_file_count "$base")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$base" "$sz" "$mt" "$gt" "$rf" "$f"
  done < <(find "$ROOT_DIR" -mindepth 1 -maxdepth 1 -type f -print0 2>/dev/null | sort -z)
  echo ""
} >>"$REPORT_TMP"

{
  echo "================================================================================"
  echo "SECTION 2 — Project root: symlinks (depth 1)"
  echo "================================================================================"
  while IFS= read -r -d '' l; do
    base="$(basename "$l")"
    tgt="$(readlink -f "$l" 2>/dev/null || readlink "$l")"
    printf '%s -> %s\n' "$l" "$tgt"
  done < <(find "$ROOT_DIR" -mindepth 1 -maxdepth 1 -type l -print0 2>/dev/null | sort -z)
  echo ""
} >>"$REPORT_TMP"

{
  echo "================================================================================"
  echo "SECTION 3 — Project root: directories (depth 1) — names only"
  echo "================================================================================"
  find "$ROOT_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
  echo ""
} >>"$REPORT_TMP"

{
  echo "================================================================================"
  echo "SECTION 4 — .azl/ root: files + FIFOs + symlinks (not traversing subdirs)"
  echo "Stable anchors (do not auto-archive without code review):"
  echo "  engine.in engine.out daemon.err sysproxy sysproxy_tcp live_chat.env"
  echo "  native_runtime_state.json (may duplicate state/ — migrate script handles conflicts)"
  echo "================================================================================"
  printf '%s\t%s\t%s\t%s\t%s\n' "name" "type" "bytes_or_" "mtime" "ref_files"
  while IFS= read -r -d '' p; do
    base="$(basename "$p")"
    if [[ -p "$p" ]]; then
      typ="fifo"
      sz="-"
    elif [[ -L "$p" ]]; then
      typ="symlink"
      sz="$(readlink "$p")"
    elif [[ -f "$p" ]]; then
      typ="file"
      sz="$(human_size "$p")"
    else
      typ="other"
      sz="?"
    fi
    mt="$(mtime_iso "$p")"
    rf="$(ref_file_count "$base")"
    printf '%s\t%s\t%s\t%s\t%s\n' "$base" "$typ" "$sz" "$mt" "$rf"
  done < <(find "$AZL_VAR" -mindepth 1 -maxdepth 1 \( -type f -o -type l -o -type p \) -print0 2>/dev/null | sort -z)
  echo ""
} >>"$REPORT_TMP"

{
  echo "================================================================================"
  echo "SECTION 5 — .azl/ immediate subdirectories (top level only)"
  echo "================================================================================"
  find "$AZL_VAR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
  du -sh "$AZL_VAR"/* 2>/dev/null | sort -h || true
  echo ""
} >>"$REPORT_TMP"

{
  echo "================================================================================"
  echo "SECTION 6 — Temp pools: count of entries named azl* (maxdepth 1 per dir)"
  echo "Dirs: $TMP_SCAN_DIRS"
  echo "================================================================================"
  for d in $TMP_SCAN_DIRS; do
    if [[ -d "$d" ]]; then
      n="$(find "$d" -maxdepth 1 -name 'azl*' 2>/dev/null | wc -l)"
      echo "$d  count=$n"
      # newest 15 by mtime
      find "$d" -maxdepth 1 -name 'azl*' -printf '%TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null | sort -r | head -15 || true
    else
      echo "$d  (missing — skipped)"
    fi
    echo ""
  done
} >>"$REPORT_TMP"

{
  echo "================================================================================"
  echo "SECTION 7 — Suggested next pass (manual)"
  echo "================================================================================"
  echo "1) Rows with git_tracked=no AND ref_files=0 are candidates for archive/delete AFTER you confirm"
  echo "   they are not loaded by runtime, desktop apps, or external docs."
  echo "2) Large JSON / logs at repo root: prefer move to .azl/quarantine/ or reports/ after backup."
  echo "3) .azl root PIDs and stale logs: extend azl_migrate_local_workspace.sh or stop daemons, then migrate."
  echo "4) /tmp and SSD tmp azl_*: safe to bulk-delete only after you confirm no running job uses them."
  echo "5) Re-run this script after any cleanup: bash scripts/azl_explore_local_artifacts.sh"
  echo ""
} >>"$REPORT_TMP"

if [[ -n "${AZL_INVENTORY_OUT:-}" ]]; then
  out="$AZL_INVENTORY_OUT"
  mkdir -p "$(dirname "$out")"
  cp "$REPORT_TMP" "$out"
  echo "Wrote report: $out"
else
  mkdir -p "${AZL_QUARANTINE_DIR}"
  stamp="$(date -u '+%Y%m%d_%H%M%SZ')"
  out="${AZL_QUARANTINE_DIR}/local_artifact_inventory_${stamp}.txt"
  cp "$REPORT_TMP" "$out"
  echo "Wrote report: $out"
  ln -sf "$(basename "$out")" "${AZL_QUARANTINE_DIR}/local_artifact_inventory_LATEST.txt" 2>/dev/null || true
fi

cat "$REPORT_TMP"
