#!/usr/bin/env bash
# Real-world language benchmark harness: Computer Language Benchmarks Game spectral-norm
# (C vs Python) via hyperfine. No silent fallback — missing tools exit with ERROR.
#
# Usage: bash scripts/benchmark_language_real_world.sh
# Env: AZL_BENCHMARK_SPECTRAL_N (default 800), AZL_BENCHMARK_HYPERFINE_RUNS (default 7),
#      AZL_BENCHMARK_HYPERFINE_WARMUP (default 2)
#
# ERROR[BENCHMARK_LANGUAGE_REAL_WORLD]: see docs/ERROR_SYSTEM.md
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/azl_local_layout.sh"

SRC_C="$ROOT_DIR/benchmarks/real_world/spectralnorm.c"
SRC_PY="$ROOT_DIR/benchmarks/real_world/spectralnorm.py"
BIN_C="${AZL_BENCHMARKS_DIR}/spectralnorm_c"
JSON_OUT="${AZL_BENCHMARKS_DIR}/benchmark_language_real_world_hyperfine.json"
VERIFY_N=100
N="${AZL_BENCHMARK_SPECTRAL_N:-800}"
RUNS="${AZL_BENCHMARK_HYPERFINE_RUNS:-7}"
WARMUP="${AZL_BENCHMARK_HYPERFINE_WARMUP:-2}"

die() {
  local c="${1:?}"; shift
  echo "ERROR[BENCHMARK_LANGUAGE_REAL_WORLD]: $*" >&2
  exit "$c"
}

if [ ! -f "Makefile" ] || [ ! -d "benchmarks/real_world" ]; then
  die 300 "must run from repository root"
fi

if ! command -v hyperfine >/dev/null 2>&1; then
  die 301 "hyperfine not found — install: https://github.com/sharkdp/hyperfine (e.g. apt install hyperfine / brew install hyperfine)"
fi

if ! command -v gcc >/dev/null 2>&1; then
  die 302 "gcc not found (required to build spectralnorm.c)"
fi

if ! command -v python3 >/dev/null 2>&1; then
  die 303 "python3 not found"
fi

if [ ! -f "$SRC_C" ] || [ ! -f "$SRC_PY" ]; then
  die 304 "missing source: $SRC_C or $SRC_PY"
fi

mkdir -p "$AZL_BENCHMARKS_DIR"

if ! gcc -O3 -std=c11 -pipe -Wall -o "$BIN_C" "$SRC_C" -lm; then
  die 305 "gcc failed to compile spectralnorm.c"
fi

chmod +x "$SRC_PY" 2>/dev/null || true

out_c="$("$BIN_C" "$VERIFY_N" 2>/dev/null | tr -d '\r')"
out_py="$(python3 "$SRC_PY" "$VERIFY_N" 2>/dev/null | tr -d '\r')"
if [ -z "$out_c" ] || [ -z "$out_py" ]; then
  die 306 "empty output from C or Python verify run (N=$VERIFY_N)"
fi
if ! python3 -c "import sys; a,b=float(sys.argv[1]),float(sys.argv[2]); sys.exit(0 if abs(a-b)<1e-6 else 1)" "$out_c" "$out_py"; then
  die 307 "C vs Python numerical mismatch at N=$VERIFY_N (c='$out_c' py='$out_py')"
fi

echo "=== Real-world language benchmark (Benchmarks Game spectral-norm) ==="
echo "Workload: https://benchmarksgame-team.pages.debian.net/benchmarksgame/performance/spectralnorm.html"
echo "Problem size N=$N | hyperfine runs=$RUNS warmup=$WARMUP"
echo "C binary: $BIN_C"
echo ""

hyperfine \
  --warmup "$WARMUP" \
  --runs "$RUNS" \
  --export-json "$JSON_OUT" \
  "$BIN_C $N" \
  "python3 $SRC_PY $N"

echo ""
echo "hyperfine JSON: $JSON_OUT"
echo "benchmark-language-real-world-ok"
exit 0
