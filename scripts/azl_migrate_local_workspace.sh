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

# Flat proof / latency artifacts at .azl root -> benchmarks/
for f in "${AZL_VAR}"/proof_llm_*; do
  [[ -e "$f" ]] || continue
  [[ -f "$f" ]] || continue
  base="$(basename "$f")"
  dest="${AZL_BENCHMARKS_DIR}/${base}"
  if [[ -e "$dest" ]]; then
    echo "azl_migrate_local_workspace: skip benchmarks merge conflict for ${base}" >&2
    continue
  fi
  mv "$f" "${AZL_BENCHMARKS_DIR}/"
  echo "azl_migrate_local_workspace: moved ${base} -> .azl/benchmarks/"
done

# Log files at .azl root -> logs/ (keep daemon.err at legacy path for systemd/docs)
for f in "${AZL_VAR}"/*; do
  [[ -f "$f" ]] || continue
  base="$(basename "$f")"
  case "$base" in
  *.log | *.log.[0-9]* | *.log.[0-9][0-9]* | *.log.[0-9][0-9][0-9]*) ;;
  *) continue ;;
  esac
  if [[ "$base" == "daemon.err" ]]; then
    continue
  fi
  dest="${AZL_LOGS_DIR}/${base}"
  if [[ -e "$dest" ]]; then
    echo "azl_migrate_local_workspace: skip logs merge conflict for ${base}" >&2
    continue
  fi
  mv "$f" "${AZL_LOGS_DIR}/"
  echo "azl_migrate_local_workspace: moved ${base} -> .azl/logs/"
done

# Legacy singleton lock at .azl root (wire now uses AZL_LOGS_DIR/wire.lock)
if [[ -f "${AZL_VAR}/wire.lock" ]]; then
  dest="${AZL_LOGS_DIR}/wire.lock"
  if [[ ! -e "$dest" ]]; then
    mv "${AZL_VAR}/wire.lock" "$dest"
    echo "azl_migrate_local_workspace: moved wire.lock -> .azl/logs/"
  else
    rm -f "${AZL_VAR}/wire.lock"
    echo "azl_migrate_local_workspace: removed stale .azl/wire.lock (logs/wire.lock exists)" >&2
  fi
fi

# Non-.log outputs still under .azl root -> logs/
for base in daemon.out sysproxy.out; do
  if [[ -f "${AZL_VAR}/${base}" ]]; then
    dest="${AZL_LOGS_DIR}/${base}"
    if [[ -e "$dest" ]]; then
      echo "azl_migrate_local_workspace: skip logs merge conflict for ${base}" >&2
      continue
    fi
    mv "${AZL_VAR}/${base}" "${AZL_LOGS_DIR}/"
    echo "azl_migrate_local_workspace: moved ${base} -> .azl/logs/"
  fi
done

# PID snapshots at .azl root -> run/
for base in daemon.pid sysproxy.pid syswire.pid azme_24h.pid; do
  if [[ -f "${AZL_VAR}/${base}" ]]; then
    dest="${AZL_RUN_DIR}/${base}"
    if [[ -e "$dest" ]]; then
      echo "azl_migrate_local_workspace: skip run merge conflict for ${base}" >&2
      continue
    fi
    mv "${AZL_VAR}/${base}" "${AZL_RUN_DIR}/"
    echo "azl_migrate_local_workspace: moved ${base} -> .azl/run/"
  fi
done

echo "azl_migrate_local_workspace: done."
