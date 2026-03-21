#!/usr/bin/env bash
# AZL0 v1 identity codec round-trip + negative cases (see docs/AZL_LITERAL_CODEC_CONTAINER_V0.md).
# Exit codes: docs/ERROR_SYSTEM.md § AZL literal codec round-trip harness.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [ ! -f "Makefile" ] || [ ! -d "azl" ]; then
  echo "ERROR[AZL_LITERAL_CODEC_ROUNDTRIP]: must run from repository root" >&2
  exit 260
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR[AZL_LITERAL_CODEC_ROUNDTRIP]: python3 not found" >&2
  exit 261
fi

export PYTHONPATH="${ROOT_DIR}/tools${PYTHONPATH:+:${PYTHONPATH}}"
exec python3 -m azl_literal_codec.roundtrip_verify
