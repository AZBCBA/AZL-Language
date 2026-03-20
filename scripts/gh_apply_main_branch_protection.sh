#!/usr/bin/env bash
# Apply GitHub branch protection required checks for the default integration branch (main).
# Matches docs/GITHUB_BRANCH_PROTECTION.md — Test and Deploy jobs: gate-and-test + azme-e2e.
# Requires: gh (authenticated, repo admin), jq. Not for CI secrets; run locally as a maintainer.
# Usage: gh_apply_main_branch_protection.sh [--dry-run] [branch]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$ROOT_DIR"

DRY_RUN=0
BRANCH=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      echo "usage: gh_apply_main_branch_protection.sh [--dry-run] [branch]" >&2
      echo "  default branch: main" >&2
      exit 0
      ;;
    *)
      if [ -n "$BRANCH" ]; then
        echo "ERROR: unexpected extra argument: ${arg}" >&2
        exit 2
      fi
      BRANCH="$arg"
      ;;
  esac
done
if [ -z "$BRANCH" ]; then
  BRANCH=main
fi

# GitHub Actions integration — required status check source (stable for github.com).
readonly GH_ACTIONS_APP_ID=15368

for cmd in gh jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${cmd}" >&2
    exit 5
  fi
done

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh is not authenticated (run: gh auth login)" >&2
  exit 6
fi

REPO="${GITHUB_REPOSITORY:-}"
if [ -z "$REPO" ]; then
  if ! REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" || [ -z "$REPO" ]; then
    echo "ERROR: could not resolve repository (set GITHUB_REPOSITORY or run inside a gh-known repo)" >&2
    exit 3
  fi
fi

PAYLOAD="$(jq -n --argjson app "$GH_ACTIONS_APP_ID" '{
  required_status_checks: {
    strict: true,
    checks: [
      { context: "Gates and full test suite", app_id: $app },
      { context: "AZME provider E2E", app_id: $app }
    ]
  },
  enforce_admins: false,
  required_pull_request_reviews: null,
  restrictions: null,
  required_linear_history: false,
  allow_force_pushes: false,
  allow_deletions: false,
  block_creations: false,
  required_conversation_resolution: false,
  lock_branch: false,
  allow_fork_syncing: false
}')"

if [ "$DRY_RUN" -eq 1 ]; then
  printf '%s\n' "$PAYLOAD"
  exit 0
fi

TMP_ERR="$(mktemp)"
trap 'rm -f "${TMP_ERR}"' EXIT

if ! printf '%s\n' "$PAYLOAD" | gh api --method PUT \
  "repos/${REPO}/branches/${BRANCH}/protection" \
  --input - >/dev/null 2>"${TMP_ERR}"; then
  echo "ERROR: GitHub API PUT branch protection failed for ${REPO} branch=${BRANCH}" >&2
  if [ -s "${TMP_ERR}" ]; then
    cat "${TMP_ERR}" >&2
  fi
  exit 7
fi

echo "OK: branch protection applied for ${REPO} refs/heads/${BRANCH}"
