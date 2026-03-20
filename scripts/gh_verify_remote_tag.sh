#!/usr/bin/env bash
# Verify refs/tags/<tag> exists on the GitHub remote (REST). Used by release workflow_dispatch
# before checkout so a typo fails with ERROR instead of an opaque checkout failure.
# Requires: gh, python3, GH_TOKEN, GITHUB_REPOSITORY, argv1 = tag (e.g. v1.2.3).
set -euo pipefail

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

# Align with scripts/gh_create_sample_release.sh
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
  echo "ERROR: tag must match vMAJOR.MINOR.PATCH[-prerelease][+build]; got: ${TAG}" >&2
  exit 6
fi

FULL_REF="refs/tags/${TAG}"
ENC="$(
  REF="$FULL_REF" python3 -c "import os, urllib.parse; print(urllib.parse.quote(os.environ['REF'], safe=''))"
)"

export GH_TOKEN
# --fail: non-2xx → non-zero exit (e.g. 404 missing ref)
if ! gh api --fail "repos/${GITHUB_REPOSITORY}/git/ref/${ENC}" >/dev/null 2>&1; then
  echo "ERROR: tag not found on remote: ${TAG} (expected git ref ${FULL_REF})" >&2
  exit 7
fi

echo "OK: remote tag exists: ${TAG}"
