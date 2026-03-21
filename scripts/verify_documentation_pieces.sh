#!/usr/bin/env bash
# Execute runnable "pieces" from release/doc_verification_pieces.json to prove docs are not lying
# about commands and files. promoted=true pieces are installed into make verify (run_full_repo_verification).
#
# Usage:
#   bash scripts/verify_documentation_pieces.sh              # all pieces
#   bash scripts/verify_documentation_pieces.sh --promoted-only
#   bash scripts/verify_documentation_pieces.sh --list
#
# ERROR[DOC_VERIFICATION_PIECES]: see docs/ERROR_SYSTEM.md
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
MANIFEST_REL="release/doc_verification_pieces.json"

usage() {
  echo "usage: bash scripts/verify_documentation_pieces.sh [--promoted-only|--list]" >&2
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ ! -f "Makefile" ] || [ ! -d "scripts" ]; then
  echo "ERROR[DOC_VERIFICATION_PIECES]: must run from repository root (Makefile/scripts missing)" >&2
  exit 101
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR[DOC_VERIFICATION_PIECES]: jq not found (required to read manifest)" >&2
  exit 102
fi

if [ ! -f "$MANIFEST_REL" ]; then
  echo "ERROR[DOC_VERIFICATION_PIECES]: manifest missing: $MANIFEST_REL" >&2
  exit 103
fi

if ! jq -e 'type == "object" and (.pieces | type == "array")' "$MANIFEST_REL" >/dev/null 2>&1; then
  echo "ERROR[DOC_VERIFICATION_PIECES]: invalid manifest JSON or missing .pieces array: $MANIFEST_REL" >&2
  exit 103
fi

PROMOTED_ONLY=0
LIST_ONLY=0
if [ "${1:-}" = "--promoted-only" ]; then
  PROMOTED_ONLY=1
elif [ "${1:-}" = "--list" ]; then
  LIST_ONLY=1
elif [ -n "${1:-}" ]; then
  echo "ERROR[DOC_VERIFICATION_PIECES]: unknown argument: $1" >&2
  usage
  exit 104
fi

# Duplicate id check
dup="$(jq -r '.pieces[].id' "$MANIFEST_REL" | sort | uniq -d)"
if [ -n "$dup" ]; then
  echo "ERROR[DOC_VERIFICATION_PIECES]: duplicate piece id(s):" >&2
  echo "$dup" >&2
  exit 107
fi

if [ "$LIST_ONLY" = 1 ]; then
  echo "Documentation verification pieces ($MANIFEST_REL):"
  jq -r '.pieces[] | "[\((.promoted==true) | if . then "promoted" else "optional" end)] \(.id) — \(.doc)"' "$MANIFEST_REL"
  exit 0
fi

if [ "$PROMOTED_ONLY" = 1 ]; then
  count="$(jq '[.pieces[] | select(.promoted == true)] | length' "$MANIFEST_REL")"
  stream() { jq -c '.pieces[] | select(.promoted == true)' "$MANIFEST_REL"; }
else
  count="$(jq '.pieces | length' "$MANIFEST_REL")"
  stream() { jq -c '.pieces[]' "$MANIFEST_REL"; }
fi

idx=0
while IFS= read -r line; do
  id="$(echo "$line" | jq -r '.id')"
  doc="$(echo "$line" | jq -r '.doc')"
  shell_cmd="$(echo "$line" | jq -r '.shell')"
  desc="$(echo "$line" | jq -r '.description // ""')"
  promoted="$(echo "$line" | jq -r '.promoted // false')"

  if [ -z "$id" ] || [ "$id" = "null" ]; then
    echo "ERROR[DOC_VERIFICATION_PIECES]: piece missing id" >&2
    exit 109
  fi
  if [ -z "$doc" ] || [ "$doc" = "null" ]; then
    echo "ERROR[DOC_VERIFICATION_PIECES]: piece $id missing doc" >&2
    exit 109
  fi
  if [ -z "$shell_cmd" ] || [ "$shell_cmd" = "null" ]; then
    echo "ERROR[DOC_VERIFICATION_PIECES]: piece $id missing shell" >&2
    exit 109
  fi

  if [ ! -f "$doc" ]; then
    echo "ERROR[DOC_VERIFICATION_PIECES]: piece $id cites missing doc path: $doc" >&2
    exit 105
  fi

  idx=$((idx + 1))
  tag="[$idx/$count]"
  if [ "$PROMOTED_ONLY" = 1 ]; then
    echo "$tag DOC_PIECE (promoted) $id — $desc"
  else
    echo "$tag DOC_PIECE $id (promoted=$promoted) — $desc"
  fi

  if ! bash -c "set -euo pipefail; cd \"$ROOT_DIR\"; $shell_cmd"; then
    echo "ERROR[DOC_VERIFICATION_PIECES]: piece failed id=$id doc=$doc shell=$shell_cmd" >&2
    exit 106
  fi
done < <(stream)

echo "doc-verification-pieces-ok (${count} ran)"
exit 0
