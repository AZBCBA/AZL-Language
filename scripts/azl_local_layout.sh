#!/usr/bin/env bash
# Canonical local workspace paths under .azl/ (gitignored). Source from repo scripts
# after setting ROOT_DIR to the repository root:
#   ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
#   # shellcheck disable=SC1091
#   source "$ROOT_DIR/scripts/azl_local_layout.sh"
#
# Override any path with env before sourcing, e.g. AZL_BENCHMARKS_DIR=/tmp/azl-bench
# Intentionally no `set -e`: safe to source from strict scripts.

if [[ -z "${ROOT_DIR:-}" ]]; then
  echo "azl_local_layout.sh: set ROOT_DIR to the repository root before sourcing" >&2
  return 1 2>/dev/null || exit 1
fi

export AZL_VAR="${AZL_VAR:-$ROOT_DIR/.azl}"
export AZL_BENCHMARKS_DIR="${AZL_BENCHMARKS_DIR:-$AZL_VAR/benchmarks}"
export AZL_LOGS_DIR="${AZL_LOGS_DIR:-$AZL_VAR/logs}"
export AZL_STATE_DIR="${AZL_STATE_DIR:-$AZL_VAR/state}"
export AZL_RUN_DIR="${AZL_RUN_DIR:-$AZL_VAR/run}"
export AZL_BUNDLES_DIR="${AZL_BUNDLES_DIR:-$AZL_VAR/bundles}"
export AZL_QUARANTINE_DIR="${AZL_QUARANTINE_DIR:-$AZL_VAR/quarantine}"

mkdir -p \
  "$AZL_VAR" \
  "$AZL_BENCHMARKS_DIR" \
  "$AZL_LOGS_DIR" \
  "$AZL_STATE_DIR" \
  "$AZL_RUN_DIR" \
  "$AZL_BUNDLES_DIR" \
  "$AZL_QUARANTINE_DIR" \
  "$AZL_VAR/tmp" \
  "$AZL_VAR/archive" \
  "$AZL_VAR/bin" \
  "$AZL_VAR/cache" \
  "$AZL_VAR/chat_sessions" 2>/dev/null || true
