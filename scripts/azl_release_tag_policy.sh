#!/usr/bin/env bash
# Shared SemVer-style release tag pattern for GitHub releases. Source from release helper scripts.
# Do not execute directly.
if [[ -n "${BASH_VERSION:-}" && "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "ERROR: source azl_release_tag_policy.sh from release scripts; do not execute directly" >&2
  exit 2
fi

# Exported for callers that need documentation or tests (read-only).
AZL_RELEASE_TAG_REGEX='^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'

# Usage: azl_assert_release_tag_shape_or_die "<tag>" [exit_code]
# Default exit_code is 5 (matches gh_create_sample_release.sh).
azl_assert_release_tag_shape_or_die() {
  local tag="$1"
  local exit_code="${2:-5}"
  if [[ ! "$tag" =~ $AZL_RELEASE_TAG_REGEX ]]; then
    echo "ERROR: tag name must match vMAJOR.MINOR.PATCH[-prerelease][+build] (e.g. v1.0.0, v1.0.0-rc.1); got: ${tag}" >&2
    exit "$exit_code"
  fi
}
