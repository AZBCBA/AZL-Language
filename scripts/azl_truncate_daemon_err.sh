#!/usr/bin/env bash
# Truncate .azl/daemon.err in place to reclaim disk. Does not remove any source
# or AZL components — only the local stderr log file.
#
# Preconditions: run from repo root (or set AZL_REPO_ROOT).
# Optional: AZL_DAEMON_ERR_BACKUP_TAIL_LINES=N — if set and >0, append last N
# lines to .azl/archive/daemon_err_tail_backup.<timestamp>.txt before truncate.
set -euo pipefail

ROOT="${AZL_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
ERR_FILE="${ROOT}/.azl/daemon.err"
ARCHIVE="${ROOT}/.azl/archive"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "${ARCHIVE}"

if [[ ! -f "${ERR_FILE}" ]]; then
  echo "azl_truncate_daemon_err: no file at ${ERR_FILE} (nothing to do)" >&2
  exit 0
fi

SIZE_BYTES="$(stat -c '%s' "${ERR_FILE}" 2>/dev/null || stat -f '%z' "${ERR_FILE}")"
echo "azl_truncate_daemon_err: ${ERR_FILE} size=${SIZE_BYTES} bytes" >&2

if [[ -n "${AZL_DAEMON_ERR_BACKUP_TAIL_LINES:-}" && "${AZL_DAEMON_ERR_BACKUP_TAIL_LINES}" =~ ^[0-9]+$ && "${AZL_DAEMON_ERR_BACKUP_TAIL_LINES}" -gt 0 ]]; then
  OUT="${ARCHIVE}/daemon_err_tail_backup.${STAMP}.txt"
  tail -n "${AZL_DAEMON_ERR_BACKUP_TAIL_LINES}" "${ERR_FILE}" > "${OUT}"
  echo "azl_truncate_daemon_err: wrote tail backup ${OUT}" >&2
fi

truncate -s 0 "${ERR_FILE}"
echo "azl_truncate_daemon_err: truncated ${ERR_FILE}" >&2
