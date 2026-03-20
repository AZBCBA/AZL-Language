#!/usr/bin/env bash
# Apply or verify GitHub branch protection required checks for the integration branch (default main).
# Eight contexts: gates, AZME, native engine matrix ×3, benchmarks, lcov, Docker (test-and-deploy.yml).
# Excludes "Deploy staging" (skipped on pull_request — would block PRs if required).
# Requires: gh (authenticated, repo admin for PUT), jq. Maintainer only; not for Actions.
# Usage: gh_apply_main_branch_protection.sh [--dry-run | --verify] [branch]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$ROOT_DIR"

# GitHub Actions integration — required status check source (stable for github.com).
readonly GH_ACTIONS_APP_ID=15368

# Job `name:` values from test-and-deploy.yml (matrix expands to three Native engine checks).
# Do not add "Deploy staging" — that job is if: push to main only; skipped on PRs.
readonly EXPECTED_CONTEXTS_JSON='[
  "Gates and full test suite",
  "AZME provider E2E",
  "Native engine (release-O2)",
  "Native engine (debug-O0)",
  "Native engine (size-Os)",
  "Benchmarks and regression gate",
  "Native engine coverage (GCC / lcov)",
  "Docker image (build; push to GHCR on main)"
]'

DRY_RUN=0
VERIFY=0
BRANCH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --verify) VERIFY=1 ;;
    -h|--help)
      echo "usage: gh_apply_main_branch_protection.sh [--dry-run | --verify] [branch]" >&2
      echo "  default branch: main" >&2
      echo "  --dry-run   print JSON body only (no API write)" >&2
      echo "  --verify    GET protection and fail on drift vs expected checks (no API write)" >&2
      exit 0
      ;;
    *)
      if [ -n "$BRANCH" ]; then
        echo "ERROR: unexpected extra argument: ${1}" >&2
        exit 2
      fi
      BRANCH="$1"
      ;;
  esac
  shift
done

if [ "$DRY_RUN" -eq 1 ] && [ "$VERIFY" -eq 1 ]; then
  echo "ERROR: use only one of --dry-run or --verify" >&2
  exit 2
fi

if [ -z "$BRANCH" ]; then
  BRANCH=main
fi

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

build_payload() {
  jq -n --argjson app "$GH_ACTIONS_APP_ID" --argjson contexts "$(echo "${EXPECTED_CONTEXTS_JSON}" | jq -c '.')" '
    ($contexts | map({context: ., app_id: $app})) as $checks |
    {
      required_status_checks: {
        strict: true,
        checks: $checks
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
    }
  '
}

PAYLOAD="$(build_payload)"

if [ "$DRY_RUN" -eq 1 ]; then
  printf '%s\n' "$PAYLOAD"
  exit 0
fi

TMP_ERR="$(mktemp)"
TMP_GET="$(mktemp)"
trap 'rm -f "${TMP_ERR}" "${TMP_GET}"' EXIT

if [ "$VERIFY" -eq 1 ]; then
  gh_rc=0
  gh api "repos/${REPO}/branches/${BRANCH}/protection" >"${TMP_GET}" 2>"${TMP_ERR}" || gh_rc=$?
  if [ "$gh_rc" -ne 0 ]; then
    if grep -E -q 'Branch not protected|Not Found|HTTP 404|status.:404' "${TMP_ERR}" 2>/dev/null; then
      echo "ERROR: branch is not protected (GET failed): ${REPO} refs/heads/${BRANCH}" >&2
      cat "${TMP_ERR}" >&2
      exit 8
    fi
    echo "ERROR: GitHub API GET branch protection failed for ${REPO} branch=${BRANCH}" >&2
    [ -s "${TMP_ERR}" ] && cat "${TMP_ERR}" >&2
    exit 10
  fi

  if ! jq -e . "${TMP_GET}" >/dev/null 2>&1; then
    echo "ERROR: protection response is not valid JSON" >&2
    exit 10
  fi

  strict="$(jq -r '.required_status_checks.strict // false' "${TMP_GET}")"
  if [ "${strict}" != "true" ]; then
    echo "ERROR: required_status_checks.strict is not true (got: ${strict})" >&2
    exit 9
  fi

  actual="$(
    jq -c '
      .required_status_checks
      | if (.checks | type == "array") and (.checks | length > 0) then
          [.checks[].context]
        else
          (.contexts // [])
        end
      | sort
    ' "${TMP_GET}"
  )"

  expected="$(echo "${EXPECTED_CONTEXTS_JSON}" | jq -c 'sort')"

  if [ "${actual}" != "${expected}" ]; then
    echo "ERROR: required status checks drift for ${REPO} refs/heads/${BRANCH}" >&2
    echo "expected (sorted): ${expected}" >&2
    echo "actual (sorted):   ${actual}" >&2
    exit 9
  fi

  echo "OK: branch protection matches expected checks for ${REPO} refs/heads/${BRANCH}"
  exit 0
fi

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
