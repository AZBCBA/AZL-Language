#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${LLAMA_CPP_ROOT:-}" ]]; then
  echo "ERROR: export LLAMA_CPP_ROOT to the root of a llama.cpp checkout (directory containing CMakeLists.txt)." >&2
  exit 2
fi

if [[ ! -f "${LLAMA_CPP_ROOT}/CMakeLists.txt" ]]; then
  echo "ERROR: LLAMA_CPP_ROOT=${LLAMA_CPP_ROOT} is not a llama.cpp tree (missing CMakeLists.txt)." >&2
  exit 3
fi

if ! command -v cmake >/dev/null 2>&1; then
  echo "ERROR: cmake is required" >&2
  exit 4
fi

BUILD_DIR="${ROOT_DIR}/.azl/build_azl_llamacpp_engine"
export LLAMA_CPP_ROOT
cmake -S "${ROOT_DIR}/tools/cmake/azl_llamacpp_engine" -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE=Release
cmake --build "${BUILD_DIR}" -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

OUT="${ROOT_DIR}/.azl/bin/azl-native-engine"
if [[ ! -x "${OUT}" ]]; then
  echo "ERROR: expected binary missing: ${OUT}" >&2
  exit 5
fi

echo "${OUT}"
