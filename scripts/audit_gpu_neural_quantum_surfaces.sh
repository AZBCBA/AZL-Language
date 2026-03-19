#!/usr/bin/env bash
# Lists AZL surfaces related to GPU, neural, memory/LHA3, quantum — for inventory doc maintenance.
# Does not fail the tree; prints counts and paths. See docs/AZL_GPU_NEURAL_QUANTUM_INVENTORY.md
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "=== AZL capability surface audit (GPU / neural / quantum / memory) ==="
echo "Root: $ROOT_DIR"
echo ""

count_dir() {
  local d="$1"
  local label="$2"
  if [ -d "$d" ]; then
    local n
    n="$(find "$d" -type f -name '*.azl' 2>/dev/null | wc -l)"
    echo "$label: $n .azl files under $d"
  else
    echo "$label: (missing) $d"
  fi
}

count_dir "azl/quantum" "quantum/"
count_dir "azl/neural" "neural/"
count_dir "azl/memory" "memory/"
count_dir "azl/orchestrator" "orchestrator/"
count_dir "azl/quantum/mathematics" "quantum/mathematics/"
echo ""

echo "--- quantum/mathematics/*.azl (line counts) ---"
if [ -d azl/quantum/mathematics ]; then
  wc -l azl/quantum/mathematics/*.azl 2>/dev/null | sort -n || true
fi
echo ""

echo "--- rg: GPU | CUDA | VRAM | cuda (azl/*.azl) ---"
if command -v rg >/dev/null 2>&1; then
  _n="$(rg -l '\bGPU\b|\bCUDA\b|\bVRAM\b|\bcuda\b' azl --glob '*.azl' 2>/dev/null | wc -l)"
  echo "files with match: ${_n// /}"
  rg -l '\bGPU\b|\bCUDA\b|\bVRAM\b|\bcuda\b' azl --glob '*.azl' 2>/dev/null | head -40 || true
  echo "(truncated at 40; use rg yourself for full list)"
else
  echo "rg not installed; skip pattern listing"
fi
echo ""

echo "--- Key single files (existence) ---"
for f in \
  azl/core/types/tensor.azl \
  azl/neural/model_loader.azl \
  azl/quantum/real_quantum_processor.azl \
  azl/ffi/math_engine.azl \
  azl/memory/lha3_quantum_memory.azl \
  azl/quantum/memory/lha3_quantum_engine.azl \
  azl/ffi/torch.azl; do
  if [ -f "$f" ]; then
    echo "  ok  $f"
  else
    echo "  MISSING $f"
  fi
done
echo ""
echo "audit-gpu-neural-quantum-surfaces-ok"
