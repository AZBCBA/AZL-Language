#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APPLY="${1:-}"

FILES=(
  "unified_llm_deployment_backup.py"
  "master_llm_demo.py"
  "unified_master_llm.py"
  "master_llm_integration.py"
  "convert_to_safetensors.py"
  "state_dict_analyzer.py"
  "vocabulary_extractor.py"
  "real_nlp_generator.py"
  "live_model_demo.py"
  "real_model_demo.py"
  "advanced_model_trainer.py"
  "master_training_orchestrator.py"
  "improved_event_training.py"
  "simple_event_training.py"
  "event_only_training.py"
  "event_seq2seq_training.py"
  "working_training.py"
)

echo "📋 Legacy host cleanup phase1 candidates:"
for f in "${FILES[@]}"; do
  if [ -f "$f" ]; then
    echo "  - $f"
  fi
done

if [ "$APPLY" != "--apply" ]; then
  echo ""
  echo "Dry run only. Re-run with --apply to remove listed files."
  exit 0
fi

echo ""
echo "🧹 Removing selected legacy host files..."
for f in "${FILES[@]}"; do
  if [ -f "$f" ]; then
    rm -f "$f"
    echo "  removed: $f"
  fi
done

echo "✅ Phase1 cleanup complete. Run validation:"
echo "  bash scripts/enforce_canonical_stack.sh"
echo "  bash scripts/check_azl_native_gates.sh"
