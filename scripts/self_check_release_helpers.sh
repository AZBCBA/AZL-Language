#!/usr/bin/env bash
# CI/local guard: syntax-check GitHub release helper scripts and assert tag-policy invariants.
# Requires: bash, rg (same as native gates).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v rg >/dev/null 2>&1; then
  echo "ERROR: required command not found: rg" >&2
  exit 40
fi

SCRIPTS=(
  "${ROOT_DIR}/scripts/azl_release_tag_policy.sh"
  "${ROOT_DIR}/scripts/gh_verify_remote_tag.sh"
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

echo "OK: release helper self-check (bash -n, tag policy, gh_verify usage)"
