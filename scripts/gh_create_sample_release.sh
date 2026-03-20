#!/usr/bin/env bash
# Create a GitHub Release for the current tag with sample bundle assets (dist/*).
# Used by .github/workflows/release.yml instead of a Node 20 JS action (GitHub Node 24 policy).
# Requires: gh (GitHub CLI), env GITHUB_REF, GITHUB_REPOSITORY, GH_TOKEN.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

for cmd in gh; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $cmd" >&2
    exit 2
  fi
done

if [ -z "${GITHUB_REF:-}" ]; then
  echo "ERROR: GITHUB_REF is unset" >&2
  exit 3
fi
if [ -z "${GITHUB_REPOSITORY:-}" ]; then
  echo "ERROR: GITHUB_REPOSITORY is unset" >&2
  exit 3
fi
if [ -z "${GH_TOKEN:-}" ]; then
  echo "ERROR: GH_TOKEN is unset (pass secrets.GITHUB_TOKEN as env GH_TOKEN)" >&2
  exit 3
fi

case "${GITHUB_REF}" in
  refs/tags/v*.*.*) ;;
  *)
    echo "ERROR: expected GITHUB_REF refs/tags/v*.*.* (push a version tag); got: ${GITHUB_REF}" >&2
    exit 4
    ;;
esac

TAG="${GITHUB_REF_NAME}"
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

if ! gh release create "$TAG" \
  --repo "${GITHUB_REPOSITORY}" \
  --title "$TAG" \
  --verify-tag \
  "${ASSETS[@]}"; then
  echo "ERROR: gh release create failed for tag: ${TAG}" >&2
  exit 8
fi

echo "OK: GitHub release created for ${TAG}"
