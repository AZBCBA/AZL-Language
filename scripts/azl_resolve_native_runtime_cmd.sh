#!/usr/bin/env bash
# Print the default AZL_NATIVE_RUNTIME_CMD for the current AZL_RUNTIME_SPINE value.
# Single source of truth for: start_azl_native_mode, run_enterprise_daemon, start_enterprise_daemon.
# Does not read AZL_NATIVE_RUNTIME_CMD (callers merge: only use output when unset).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

case "${AZL_RUNTIME_SPINE:-c_minimal}" in
  azl_interpreter|semantic)
    printf '%s\n' "bash scripts/azl_azl_interpreter_runtime.sh"
    ;;
  c_minimal|""|*)
    printf '%s\n' "bash scripts/azl_c_interpreter_runtime.sh"
    ;;
esac
