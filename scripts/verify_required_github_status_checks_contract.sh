#!/usr/bin/env bash
# Ensures release/ci/required_github_status_checks.json matches .github/workflows/test-and-deploy.yml
# job ids and display names (branch-protection + PR template contract). No GitHub API or admin token.
# Requires: bash, jq, awk, grep.
# Exit: 0 OK; 11 missing jq; 12 bad config; 13 missing workflow; 14 name/job mismatch; 15 matrix; 16 forbidden context.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONFIG="${ROOT_DIR}/release/ci/required_github_status_checks.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: required command not found: jq" >&2
  exit 11
fi

if [ ! -f "$CONFIG" ]; then
  echo "ERROR: config missing: ${CONFIG}" >&2
  exit 12
fi

if ! jq -e . "$CONFIG" >/dev/null 2>&1; then
  echo "ERROR: config is not valid JSON: ${CONFIG}" >&2
  exit 12
fi

WF_REL="$(jq -r '.workflow_file // empty' "$CONFIG")"
if [ -z "$WF_REL" ]; then
  echo "ERROR: config.workflow_file must be a non-empty string" >&2
  exit 12
fi
WF="${ROOT_DIR}/${WF_REL}"
if [ ! -f "$WF" ]; then
  echo "ERROR: workflow file missing: ${WF}" >&2
  exit 13
fi

if ! jq -e '.workflow_assertions | type == "array" and length > 0' "$CONFIG" >/dev/null 2>&1; then
  echo "ERROR: config.workflow_assertions must be a non-empty array" >&2
  exit 12
fi

derived="$(
  jq -c '
    [ .workflow_assertions[]
      | if (.matrix_job // false) then
          (.matrix_variant_names // [])[] as $n
          | (.name_template // "") | gsub("%s"; $n)
        else
          .exact_name // empty
        end
      | select(length > 0)
    ]
    | sort
  ' "$CONFIG"
)"

if [ "$derived" = "[]" ] || [ -z "$derived" ]; then
  echo "ERROR: derived required_contexts list is empty" >&2
  exit 17
fi

while IFS= read -r forbidden; do
  [ -z "$forbidden" ] && continue
  if jq -e --argjson d "$derived" --arg f "$forbidden" '($d | index($f)) != null' >/dev/null 2>&1; then
    echo "ERROR: forbidden context appears in derived required list: ${forbidden}" >&2
    exit 16
  fi
done < <(jq -r '.must_not_require_name_substrings[]? // empty' "$CONFIG")

# --- Workflow structure checks (job block + name line + matrix variants) ---
extract_job_block() {
  local wf="$1" job="$2"
  awk -v jb="$job" '
    $0 ~ "^  " jb ":" { p=1; print; next }
    p && $0 ~ /^  [a-zA-Z0-9_-]+:/ { exit }
    p { print }
  ' "$wf"
}

while IFS= read -r row; do
  job_id="$(echo "$row" | jq -r '.job_id')"
  if [ -z "$job_id" ] || [ "$job_id" = "null" ]; then
    echo "ERROR: workflow_assertions entry missing job_id" >&2
    exit 12
  fi
  block="$(extract_job_block "$WF" "$job_id")"
  if [ -z "$block" ]; then
    echo "ERROR: job block not found in ${WF_REL}: ${job_id}" >&2
    exit 14
  fi

  is_matrix="$(echo "$row" | jq -r '.matrix_job // false')"

  if [ "$is_matrix" = "true" ]; then
    if ! printf '%s\n' "$block" | grep -Fq 'name: Native engine (${{ matrix.name }})' 2>/dev/null; then
      echo "ERROR: job ${job_id}: expected workflow line: name: Native engine (\${{ matrix.name }})" >&2
      printf '%s\n' "$block" | head -20 >&2
      exit 14
    fi
    while IFS= read -r vn; do
      [ -z "$vn" ] && continue
      if ! printf '%s\n' "$block" | grep -Fq -- "- name: ${vn}" 2>/dev/null; then
        echo "ERROR: job ${job_id}: matrix variant not found under include: ${vn}" >&2
        exit 15
      fi
    done < <(echo "$row" | jq -r '.matrix_variant_names[]? // empty')
  else
    ename="$(echo "$row" | jq -r '.exact_name // ""')"
    if [ -z "$ename" ]; then
      echo "ERROR: job ${job_id}: exact_name required for non-matrix job" >&2
      exit 12
    fi
    if ! printf '%s\n' "$block" | grep -Fq "name: ${ename}" 2>/dev/null; then
      echo "ERROR: job ${job_id}: missing name line: name: ${ename}" >&2
      printf '%s\n' "$block" | head -25 >&2
      exit 14
    fi
  fi
done < <(jq -c '.workflow_assertions[]' "$CONFIG")

while IFS= read -r nid; do
  [ -z "$nid" ] && continue
  if ! awk -v jb="$nid" '$0 ~ "^  " jb ":" { found=1 } END { exit found ? 0 : 1 }' "$WF"; then
    echo "ERROR: must_not_require_job_ids lists ${nid} but job not found (unexpected)" >&2
    exit 12
  fi
  b="$(extract_job_block "$WF" "$nid")"
  if printf '%s\n' "$b" | grep -Fq 'name: Deploy staging' 2>/dev/null; then
    :
  else
    echo "ERROR: deploy-staging job should remain named Deploy staging for contract docs" >&2
    exit 14
  fi
done < <(jq -r '.must_not_require_job_ids[]? // empty' "$CONFIG")

cnt="$(echo "$derived" | jq -r 'length')"
echo "OK: required GitHub status checks contract matches ${WF_REL} (${cnt} contexts)"
exit 0
