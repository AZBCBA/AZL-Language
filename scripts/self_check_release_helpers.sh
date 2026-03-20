#!/usr/bin/env bash
# CI/local guard: syntax-check GitHub release helper scripts (incl. gh_assert_checkout_matches_tag),
# tag-policy invariants, and release/native/manifest.json (JSON + gates[] + github_release paths).
# Requires: bash, rg, jq (JSON + schema-shaped checks; no Python).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export ROOT_DIR

if ! command -v rg >/dev/null 2>&1; then
  echo "ERROR: required command not found: rg" >&2
  exit 40
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: required command not found: jq" >&2
  exit 49
fi

SCRIPTS=(
  "${ROOT_DIR}/scripts/azl_release_tag_policy.sh"
  "${ROOT_DIR}/scripts/gh_verify_remote_tag.sh"
  "${ROOT_DIR}/scripts/gh_assert_checkout_matches_tag.sh"
  "${ROOT_DIR}/scripts/gh_create_sample_release.sh"
)
for f in "${SCRIPTS[@]}"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: missing script: $f" >&2
    exit 41
  fi
  if ! bash -n "$f"; then
    echo "ERROR: bash -n failed: $f" >&2
    exit 42
  fi
done

# Direct execution of policy must be rejected (source-only contract).
set +e
policy_out="$(bash "${ROOT_DIR}/scripts/azl_release_tag_policy.sh" 2>&1)"
policy_rc=$?
set -e
if [[ "$policy_rc" -ne 2 ]]; then
  echo "ERROR: azl_release_tag_policy.sh direct run expected exit 2, got ${policy_rc}; output: ${policy_out}" >&2
  exit 43
fi
if ! echo "$policy_out" | rg -q 'source azl_release_tag_policy'; then
  echo "ERROR: direct-run message must mention sourcing azl_release_tag_policy" >&2
  exit 44
fi

# Sourced good tag must succeed.
if ! bash -c "set -euo pipefail; source '${ROOT_DIR}/scripts/azl_release_tag_policy.sh'; azl_assert_release_tag_shape_or_die v1.2.3"; then
  echo "ERROR: valid tag v1.2.3 should pass azl_assert_release_tag_shape_or_die" >&2
  exit 45
fi

# Sourced bad tag must exit with caller-chosen code.
set +e
bash -c "set -euo pipefail; source '${ROOT_DIR}/scripts/azl_release_tag_policy.sh'; azl_assert_release_tag_shape_or_die not-a-release-tag 87" 2>/dev/null
bad_rc=$?
set -e
if [[ "$bad_rc" -ne 87 ]]; then
  echo "ERROR: invalid tag assert expected exit 87, got ${bad_rc}" >&2
  exit 46
fi

# gh_verify_remote_tag: usage without args.
set +e
verify_out="$(
  GITHUB_REPOSITORY="owner/repo" GH_TOKEN="x" bash "${ROOT_DIR}/scripts/gh_verify_remote_tag.sh" 2>&1
)"
verify_rc=$?
set -e
if [[ "$verify_rc" -ne 2 ]]; then
  echo "ERROR: gh_verify_remote_tag.sh with no args expected exit 2, got ${verify_rc}" >&2
  exit 47
fi
if ! echo "$verify_out" | rg -q 'usage'; then
  echo "ERROR: gh_verify_remote_tag.sh missing usage in stderr" >&2
  exit 48
fi

MANIFEST="${ROOT_DIR}/release/native/manifest.json"
if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: manifest missing: ${MANIFEST}" >&2
  exit 50
fi
if ! jq -e . "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: manifest invalid JSON or jq parse error: ${MANIFEST}" >&2
  exit 50
fi

if ! jq -e '.gates | type == "array"' "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: manifest gates must be an array" >&2
  exit 51
fi

while IFS= read -r g; do
  if [ -z "$g" ]; then
    echo "ERROR: manifest gates[] entries must be non-empty strings" >&2
    exit 51
  fi
  path="${ROOT_DIR}/${g}"
  if [ ! -f "$path" ]; then
    echo "ERROR: manifest gates[] path missing on disk: ${g} -> ${path}" >&2
    exit 57
  fi
done < <(jq -r '.gates[]' "$MANIFEST")

if ! jq -e '.github_release | type == "object"' "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: manifest github_release must be an object" >&2
  exit 52
fi

wf="$(jq -r '.github_release.workflow // empty' "$MANIFEST")"
if [ -z "$wf" ]; then
  echo "ERROR: manifest github_release.workflow must be a non-empty string" >&2
  exit 53
fi
wf_path="${ROOT_DIR}/${wf}"
if [ ! -f "$wf_path" ]; then
  echo "ERROR: manifest github_release.workflow file missing: ${wf} -> ${wf_path}" >&2
  exit 54
fi

if ! jq -e '.github_release.scripts | type == "array"' "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: manifest github_release.scripts must be an array" >&2
  exit 55
fi

while IFS= read -r s; do
  if [ -z "$s" ]; then
    echo "ERROR: manifest github_release.scripts entries must be non-empty strings" >&2
    exit 56
  fi
  sp="${ROOT_DIR}/${s}"
  if [ ! -f "$sp" ]; then
    echo "ERROR: manifest github_release.scripts path missing: ${s} -> ${sp}" >&2
    exit 58
  fi
done < <(jq -r '.github_release.scripts[]' "$MANIFEST")

echo "OK: release helper self-check (bash -n, tag policy, gh_verify usage, native manifest)"
