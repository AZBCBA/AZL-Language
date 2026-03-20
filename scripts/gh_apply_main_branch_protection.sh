#!/usr/bin/env bash
# Apply or verify GitHub branch protection required checks (default branch main).
# Required contexts come from release/ci/required_github_status_checks.json (single source of truth).
# Excludes deploy-staging via that file — skipped on pull_request if required.
# Requires: jq always; gh + auth for --verify and apply (not for --dry-run).
# Usage: gh_apply_main_branch_protection.sh [--dry-run | --verify] [branch]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$ROOT_DIR"

CONFIG="${ROOT_DIR}/release/ci/required_github_status_checks.json"

expand_contexts_jq='[ .workflow_assertions[]
  | if (.matrix_job // false) then
      (.matrix_variant_names // [])[] as $n
      | (.name_template // "") | gsub("%s"; $n)
    else
      .exact_name // empty
    end
  | select(length > 0)
]'

load_config_or_die() {
  if [ ! -f "$CONFIG" ]; then
    echo "ERROR: config missing: ${CONFIG}" >&2
    exit 4
  fi
  if ! jq -e . "$CONFIG" >/dev/null 2>&1; then
    echo "ERROR: config is not valid JSON: ${CONFIG}" >&2
    exit 4
  fi
  if ! jq -e '.workflow_assertions | type == "array" and length > 0' "$CONFIG" >/dev/null 2>&1; then
    echo "ERROR: config.workflow_assertions must be a non-empty array" >&2
    exit 4
  fi
  GH_ACTIONS_APP_ID="$(jq -r '.github_actions_app_id // empty' "$CONFIG")"
  if [ -z "$GH_ACTIONS_APP_ID" ] || [ "$GH_ACTIONS_APP_ID" = "null" ]; then
    echo "ERROR: config.github_actions_app_id must be set" >&2
    exit 4
  fi
  EXPECTED_CONTEXTS_JSON="$(jq -c "$expand_contexts_jq" "$CONFIG")" || {
    echo "ERROR: failed to derive required contexts from ${CONFIG}" >&2
    exit 4
  }
}

DRY_RUN=0
VERIFY=0
BRANCH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --verify) VERIFY=1 ;;
    -h|--help)
      echo "usage: gh_apply_main_branch_protection.sh [--dry-run | --verify] [branch]" >&2
      echo "  default branch: from release/ci/required_github_status_checks.json (branch_default) or main" >&2
      echo "  contexts: release/ci/required_github_status_checks.json" >&2
      echo "  --dry-run   print JSON body only (jq only; no gh)" >&2
      echo "  --verify    GET protection and compare (needs gh auth + admin read)" >&2
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

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: required command not found: jq" >&2
  exit 5
fi

load_config_or_die

if [ -z "$BRANCH" ]; then
  BRANCH="$(jq -r '.branch_default // "main"' "$CONFIG")"
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

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: required command not found: gh" >&2
  exit 5
fi

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

  echo "OK: branch protection matches ${CONFIG} for ${REPO} refs/heads/${BRANCH}"
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

echo "OK: branch protection applied for ${REPO} refs/heads/${BRANCH} (from ${CONFIG})"
