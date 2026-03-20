#!/usr/bin/env bash
# Create a GitHub Release for the current tag with sample bundle assets (dist/*).
# Used by .github/workflows/release.yml instead of a Node 20 JS action (GitHub Node 24 policy).
# Requires: gh (GitHub CLI), GITHUB_REPOSITORY, GH_TOKEN, and either:
#   - Tag push CI: GITHUB_REF=refs/tags/v*.*.* (default), or
#   - workflow_dispatch / local: AZL_RELEASE_TAG=vX.Y.Z… (GITHUB_REF may be refs/heads/*).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=azl_release_tag_policy.sh
source "${SCRIPT_DIR}/azl_release_tag_policy.sh"

for cmd in gh; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $cmd" >&2
    exit 2
  fi
done

if [ -z "${GITHUB_REPOSITORY:-}" ]; then
  echo "ERROR: GITHUB_REPOSITORY is unset" >&2
  exit 3
fi
if [ -z "${GH_TOKEN:-}" ]; then
  echo "ERROR: GH_TOKEN is unset (pass secrets.GITHUB_TOKEN as env GH_TOKEN)" >&2
  exit 3
fi

if [ -n "${AZL_RELEASE_TAG:-}" ]; then
  TAG="${AZL_RELEASE_TAG}"
else
  if [ -z "${GITHUB_REF:-}" ]; then
    echo "ERROR: GITHUB_REF is unset and AZL_RELEASE_TAG is unset" >&2
    exit 3
  fi
  case "${GITHUB_REF}" in
    refs/tags/v*.*.*) ;;
    *)
      echo "ERROR: expected GITHUB_REF refs/tags/v*.*.* (push a version tag) or set AZL_RELEASE_TAG (e.g. workflow_dispatch); got: ${GITHUB_REF}" >&2
      exit 4
      ;;
  esac
  TAG="${GITHUB_REF_NAME}"
fi

# vMAJOR.MINOR.PATCH with optional SemVer prerelease (-alpha.1) and/or build (+gabc)
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
  echo "ERROR: tag name must match vMAJOR.MINOR.PATCH[-prerelease][+build] (e.g. v1.0.0, v1.0.0-rc.1); got: ${TAG}" >&2
  exit 5
fi

ASSETS=(
  "${ROOT_DIR}/dist/smoke_test.azl"
  "${ROOT_DIR}/dist/test_canonical_azl.azl"
  "${ROOT_DIR}/dist/README.md"
  "${ROOT_DIR}/dist/OPERATIONS.md"
)
for f in "${ASSETS[@]}"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: release asset missing: $f" >&2
    exit 6
  fi
done

export GH_TOKEN

if gh release view "$TAG" --repo "${GITHUB_REPOSITORY}" >/dev/null 2>&1; then
  echo "ERROR: GitHub release already exists for tag: ${TAG}" >&2
  exit 7
fi

GH_CREATE_ERR="$(mktemp)"
trap 'rm -f "${GH_CREATE_ERR}"' EXIT
if ! gh release create "$TAG" \
  --repo "${GITHUB_REPOSITORY}" \
  --title "$TAG" \
  --verify-tag \
  "${ASSETS[@]}" 2>"${GH_CREATE_ERR}"; then
  echo "ERROR: gh release create failed for tag: ${TAG}" >&2
  if [ -s "${GH_CREATE_ERR}" ]; then
    echo "ERROR: gh stderr:" >&2
    cat "${GH_CREATE_ERR}" >&2
  fi
  exit 8
fi

echo "OK: GitHub release created for ${TAG}"
