#!/usr/bin/env bash
# Verify refs/tags/<tag> exists on the GitHub remote (REST). Used by release workflow_dispatch
# before checkout so a typo fails with ERROR instead of an opaque checkout failure.
# Requires: gh, python3, GH_TOKEN, GITHUB_REPOSITORY, argv1 = tag (e.g. v1.2.3).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=azl_release_tag_policy.sh
source "${SCRIPT_DIR}/azl_release_tag_policy.sh"

TAG="${1-}"
if [ -z "$TAG" ]; then
  echo "ERROR: usage: gh_verify_remote_tag.sh <tag>" >&2
  exit 2
fi
if [ -z "${GITHUB_REPOSITORY:-}" ]; then
  echo "ERROR: GITHUB_REPOSITORY is unset" >&2
  exit 3
fi
if [ -z "${GH_TOKEN:-}" ]; then
  echo "ERROR: GH_TOKEN is unset" >&2
  exit 4
fi

for cmd in gh python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $cmd" >&2
    exit 5
  fi
done

azl_assert_release_tag_shape_or_die "$TAG" 6

FULL_REF="refs/tags/${TAG}"
ENC="$(
  REF="$FULL_REF" python3 -c "import os, urllib.parse; print(urllib.parse.quote(os.environ['REF'], safe=''))"
)"

export GH_TOKEN
GH_ERR="$(mktemp)"
trap 'rm -f "${GH_ERR}"' EXIT
# Non-2xx → non-zero exit (e.g. 404 missing ref). Do not use curl's --fail; gh versions differ.
if ! gh api "repos/${GITHUB_REPOSITORY}/git/ref/${ENC}" >/dev/null 2>"${GH_ERR}"; then
  echo "ERROR: tag not found on remote: ${TAG} (expected git ref ${FULL_REF})" >&2
  if [ -s "${GH_ERR}" ]; then
    echo "ERROR: gh api stderr:" >&2
    cat "${GH_ERR}" >&2
  fi
  exit 7
fi

echo "OK: remote tag exists: ${TAG}"
