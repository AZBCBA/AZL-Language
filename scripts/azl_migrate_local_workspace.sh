#!/usr/bin/env bash
# One-time (idempotent) move of local artifacts into .azl/ subfolders.
# Safe for disconnected components: only moves known filename patterns; does not delete sources.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/azl_local_layout.sh"

shopt -s nullglob

# Root-level quarantine/ (gitignored) -> .azl/quarantine/
if [[ -d "${ROOT_DIR}/quarantine" ]]; then
  for f in "${ROOT_DIR}/quarantine"/*; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    if [[ -e "${AZL_QUARANTINE_DIR}/${base}" ]]; then
      echo "azl_migrate_local_workspace: skip (exists in quarantine): ${base}" >&2
      continue
    fi
    mv "$f" "${AZL_QUARANTINE_DIR}/"
    echo "azl_migrate_local_workspace: moved quarantine/${base} -> .azl/quarantine/"
  done
  rmdir "${ROOT_DIR}/quarantine" 2>/dev/null || true
fi

# Flat benchmark outputs under .azl/ -> .azl/benchmarks/
for f in "${AZL_VAR}"/benchmark_*; do
  [[ -f "$f" ]] || continue
  mv "$f" "${AZL_BENCHMARKS_DIR}/"
  echo "azl_migrate_local_workspace: moved $(basename "$f") -> .azl/benchmarks/"
done

for f in "${AZL_VAR}"/policy_stress*; do
  [[ -f "$f" ]] || continue
  mv "$f" "${AZL_BENCHMARKS_DIR}/"
  echo "azl_migrate_local_workspace: moved $(basename "$f") -> .azl/benchmarks/"
done

[[ -f "${AZL_VAR}/llm_python_summary.txt" ]] && mv "${AZL_VAR}/llm_python_summary.txt" "${AZL_BENCHMARKS_DIR}/" && echo "azl_migrate_local_workspace: moved llm_python_summary.txt -> .azl/benchmarks/"

# State JSONL / JSON at .azl/ root -> .azl/state/
for name in native_engine_runs.jsonl policy_infer_audit.jsonl native_runtime_state.json; do
  if [[ -f "${AZL_VAR}/${name}" ]]; then
    dest="${AZL_STATE_DIR}/${name}"
    if [[ -f "$dest" ]]; then
      echo "azl_migrate_local_workspace: skip state merge conflict for ${name} (destination exists)" >&2
      continue
    fi
    mv "${AZL_VAR}/${name}" "${AZL_STATE_DIR}/"
    echo "azl_migrate_local_workspace: moved ${name} -> .azl/state/"
  fi
done

# Optional: large rebuilt bundle
if [[ -f "${AZL_VAR}/enterprise_combined_rebuilt.azl" ]]; then
  dest="${AZL_BUNDLES_DIR}/enterprise_combined_rebuilt.azl"
  if [[ ! -f "$dest" ]]; then
    mv "${AZL_VAR}/enterprise_combined_rebuilt.azl" "$dest"
    echo "azl_migrate_local_workspace: moved enterprise_combined_rebuilt.azl -> .azl/bundles/"
  fi
fi

echo "azl_migrate_local_workspace: done."
