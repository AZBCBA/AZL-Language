#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== AZL native API cold vs warm benchmark =="
export AZL_STRICT=1

echo "-- Cold run --"
AZL_BENCH_REQS=${AZL_BENCH_REQS:-100} bash scripts/benchmark_native_api.sh
echo "-- Warm run --"
AZL_BENCH_REQS=${AZL_BENCH_REQS:-100} bash scripts/benchmark_native_api.sh
echo "Done"

