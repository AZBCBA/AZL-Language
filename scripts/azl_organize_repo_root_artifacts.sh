#!/usr/bin/env bash
# Move artifact-class files from the repository root into structured folders:
#   - Tracked files: git mv -> project/repo_root/{logs,txt,json,pid}/ (keeps history)
#   - Untracked (and ignored) files: mv -> .azl/archive/repo_root/... (gitignored)
#
# Never moves protected product paths (README, azl.build.json, training configs referenced by docs, etc.).
#
# Env:
#   AZL_ORGANIZE_APPLY=1           Required to perform any filesystem/git change (default: dry-run).
#   AZL_ORGANIZE_GIT_MV_TRACKED=1  Also reorganize tracked artifact files via git mv to project/repo_root/.
#   AZL_ORGANIZE_MOVE_UNTRACKED=1  Move untracked/ignored artifacts to .azl/archive/repo_root/ (default on when APPLY=1).
#   AZL_ORGANIZE_FIX_HTTP_COLON=1  git mv the mistaken root directory "http:" -> project/miscreated_http_colon_path
#   AZL_ORGANIZE_LARGE_EXPORTS=1   Also git mv lha3_memory_export.json (large) to project/repo_root/json/
#
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR" || die "cannot cd to $ROOT_DIR"

command -v git >/dev/null 2>&1 || die "git is required"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/azl_local_layout.sh"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git work tree"

APPLY="${AZL_ORGANIZE_APPLY:-0}"
DO_GIT="${AZL_ORGANIZE_GIT_MV_TRACKED:-0}"
DO_UNTRACKED="${AZL_ORGANIZE_MOVE_UNTRACKED:-1}"
FIX_HTTP="${AZL_ORGANIZE_FIX_HTTP_COLON:-0}"
LARGE="${AZL_ORGANIZE_LARGE_EXPORTS:-0}"

DEST_GIT="$ROOT_DIR/project/repo_root"
DEST_LOCAL_LOGS="$AZL_VAR/archive/repo_root/logs"
DEST_LOCAL_TXT="$AZL_VAR/archive/repo_root/txt"
DEST_LOCAL_JSON="$AZL_VAR/archive/repo_root/json"
DEST_LOCAL_PID="$AZL_VAR/archive/repo_root/pid"

MANIFEST="$AZL_VAR/archive/repo_root/ORGANIZE_MANIFEST_$(date -u '+%Y%m%dT%H%M%SZ').log"
mkdir -p "$DEST_GIT/logs" "$DEST_GIT/txt" "$DEST_GIT/json" "$DEST_GIT/pid" \
  "$DEST_LOCAL_LOGS" "$DEST_LOCAL_TXT" "$DEST_LOCAL_JSON" "$DEST_LOCAL_PID" \
  "$(dirname "$MANIFEST")"

is_tracked() {
  git ls-files --error-unmatch "$1" >/dev/null 2>&1
}

is_protected_base() {
  case "$1" in
  README.md | CHANGELOG.md | LICENSE | SECURITY.md | CODE_OF_CONDUCT.md | OPERATIONS.md | RELEASE_READY.md | \
  GITHUB_PUBLISH.md | \
  Dockerfile | Makefile | .gitignore | .gitattributes | .dockerignore | \
  azl.build.json | azl.native.json | requirements.txt | \
  sample_dataset.jsonl | \
  azl_bootstrap.azl | smoke_test.azl | train_real_models.azl | runtime_boot.azl | build_azl.azl | \
  build.sh | deploy_unified_llm.sh | launch_azme_complete.sh | monitor_unified_llm.sh | \
  run_azl_daemon.sh | run_pure_azl.sh | run_background_training.sh | start_unified_llm.sh)
    return 0
    ;;
  esac
  return 1
}

log_manifest() {
  echo "$*" >>"$MANIFEST"
}

move_one() {
  local src="$1" dest_dir="$2" mode="$3"
  local base dest
  base="$(basename "$src")"
  dest="$dest_dir/$base"
  [[ -e "$src" ]] || return 0
  if [[ -e "$dest" ]]; then
    die "refusing overwrite: destination exists: $dest (resolve manually)"
  fi
  log_manifest "$mode	$src	$dest"
  if [[ "$APPLY" != "1" ]]; then
    echo "[dry-run] $mode $src -> $dest"
    return 0
  fi
  mkdir -p "$dest_dir"
  case "$mode" in
  git_mv)
    git mv "$src" "$dest" || die "git mv failed: $src"
    ;;
  mv)
    mv "$src" "$dest" || die "mv failed: $src"
    ;;
  *)
    die "unknown mode $mode"
    ;;
  esac
  echo "[done] $mode $src -> $dest"
}

# --- Root regular files ---
shopt -s nullglob
for src in "$ROOT_DIR"/*; do
  [[ -f "$src" ]] || continue
  base="$(basename "$src")"
  if is_protected_base "$base"; then
    continue
  fi

  if [[ "$base" == "lha3_memory_export.json" ]]; then
    [[ "$LARGE" == "1" ]] || continue
    if is_tracked "$base"; then
      [[ "$DO_GIT" == "1" ]] || { echo "[skip lha3_memory_export.json, set AZL_ORGANIZE_GIT_MV_TRACKED=1]"; continue; }
      move_one "$base" "$DEST_GIT/json" git_mv
    else
      [[ "$DO_UNTRACKED" == "1" ]] || continue
      move_one "$base" "$DEST_LOCAL_JSON" mv
    fi
    continue
  fi

  if [[ "$base" == *.log ]] || [[ "$base" == nohup.out ]]; then
    if is_tracked "$base"; then
      [[ "$DO_GIT" == "1" ]] || { echo "[skip tracked log, set AZL_ORGANIZE_GIT_MV_TRACKED=1] $base"; continue; }
      move_one "$base" "$DEST_GIT/logs" git_mv
    else
      [[ "$DO_UNTRACKED" == "1" ]] || continue
      move_one "$base" "$DEST_LOCAL_LOGS" mv
    fi
    continue
  fi

  if [[ "$base" == *.pid ]]; then
    if is_tracked "$base"; then
      [[ "$DO_GIT" == "1" ]] || { echo "[skip tracked pid, set AZL_ORGANIZE_GIT_MV_TRACKED=1] $base"; continue; }
      move_one "$base" "$DEST_GIT/pid" git_mv
    else
      [[ "$DO_UNTRACKED" == "1" ]] || continue
      move_one "$base" "$DEST_LOCAL_PID" mv
    fi
    continue
  fi

  case "$base" in
  test_output.txt | output.txt | test_results.txt | \
  full_azl_run.txt | full_debug.txt | full_training_log.txt | \
  debug_content.txt | debug_orchestrator.txt | \
  training_log.txt | working_training_log.txt | master_llm_final_report.txt)
    if is_tracked "$base"; then
      [[ "$DO_GIT" == "1" ]] || { echo "[skip tracked txt, set AZL_ORGANIZE_GIT_MV_TRACKED=1] $base"; continue; }
      move_one "$base" "$DEST_GIT/txt" git_mv
    else
      [[ "$DO_UNTRACKED" == "1" ]] || continue
      move_one "$base" "$DEST_LOCAL_TXT" mv
    fi
    continue
    ;;
  esac

  case "$base" in
  azl_azme_demo_results.json | model_evaluation_results.json | real_proof_matrix.json | \
  quantum_output.json | quantum_proof.json | relu_output.json | relu_proof.json)
    if is_tracked "$base"; then
      [[ "$DO_GIT" == "1" ]] || { echo "[skip tracked json, set AZL_ORGANIZE_GIT_MV_TRACKED=1] $base"; continue; }
      move_one "$base" "$DEST_GIT/json" git_mv
    else
      [[ "$DO_UNTRACKED" == "1" ]] || continue
      move_one "$base" "$DEST_LOCAL_JSON" mv
    fi
    continue
    ;;
  esac
done

# --- Mistaken http: directory ---
if [[ -d "$ROOT_DIR/http:" ]]; then
  dest_http="$ROOT_DIR/project/miscreated_http_colon_path"
  if [[ "$FIX_HTTP" == "1" ]]; then
    if [[ -e "$dest_http" ]]; then
      die "refusing http: fix: $dest_http already exists"
    fi
    log_manifest "git_mv_dir	http:	project/miscreated_http_colon_path"
    if [[ "$APPLY" != "1" ]]; then
      echo "[dry-run] git mv http: -> project/miscreated_http_colon_path"
    else
      mkdir -p "$ROOT_DIR/project"
      git mv "http:" "$dest_http" || die "git mv http: failed"
      echo "[done] git mv http: -> project/miscreated_http_colon_path"
    fi
  else
    warn "directory ./http: exists (malformed URL path). Re-run with AZL_ORGANIZE_FIX_HTTP_COLON=1 AZL_ORGANIZE_APPLY=1 to git mv it under project/."
  fi
fi

if [[ "$APPLY" != "1" ]]; then
  echo ""
  echo "Dry-run only. To apply: AZL_ORGANIZE_APPLY=1 ..."
  echo "Manifest would be: $MANIFEST"
else
  echo "Manifest: $MANIFEST"
fi
