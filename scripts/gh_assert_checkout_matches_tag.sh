#!/usr/bin/env bash
# After actions/checkout at a tag, assert Git HEAD equals the peeled commit for refs/tags/<tag>.
# Used by .github/workflows/release.yml (tag push + workflow_dispatch). Fails with ERROR if shallow
# clone or wrong ref (misconfigured workflow).
# Usage: bash scripts/gh_assert_checkout_matches_tag.sh <tag>
set -euo pipefail

TAG="${1-}"
if [ -z "$TAG" ]; then
  echo "ERROR: usage: gh_assert_checkout_matches_tag.sh <tag>" >&2
  exit 2
fi

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is required" >&2
  exit 5
fi

if ! want="$(git rev-parse -q --verify "refs/tags/${TAG}^{commit}" 2>/dev/null)"; then
  echo "ERROR: refs/tags/${TAG}^{commit} not found in this repository (fetch-depth / tag name?)" >&2
  exit 3
fi

have="$(git rev-parse -q HEAD)"
if [ "$want" != "$have" ]; then
  echo "ERROR: Git HEAD (${have}) does not match peeled commit for refs/tags/${TAG} (${want})" >&2
  exit 4
fi

echo "OK: checkout matches tag ${TAG} (${have})"
