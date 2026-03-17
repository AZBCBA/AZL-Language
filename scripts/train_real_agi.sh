#!/usr/bin/env bash
# Real AGI Training Launcher
# Launches comprehensive AGI training on real-world datasets

set -euo pipefail
cd "$(dirname "$0")/.."

echo "🚀 LAUNCHING REAL AGI TRAINING"
echo "=============================="

# Check if datasets are available
DATASETS_DIR="/mnt/ssd4t/agi_datasets"
if [ ! -d "$DATASETS_DIR" ]; then
    echo "❌ Datasets not found. Run ./scripts/download_real_datasets.sh first"
    exit 1
fi

echo "📊 Dataset status:"
echo "   📁 Location: $DATASETS_DIR"
echo "   💾 Size: $(du -sh $DATASETS_DIR | cut -f1)"
echo "   📋 Config: datasets/real_world_training/dataset_config.json"

# Set environment variables
export CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-""}
export PYTHONPATH="$PWD:$PYTHONPATH"

# Training configuration
TRAINING_SCRIPT="python_helpers/train_real_agi_model.py"
LOG_FILE="logs/real_agi_training/training_$(date +%Y%m%d_%H%M%S).log"

echo "🧠 Training configuration:"
echo "   🐍 Script: $TRAINING_SCRIPT"
echo "   📝 Log: $LOG_FILE"
echo "   💻 Device: $(python3 -c 'import torch; print("CUDA" if torch.cuda.is_available() else "CPU")')"

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

echo ""
echo "🚀 Starting AGI training on real-world datasets..."
echo "   This will train on text, scientific, and code datasets"
echo "   Expected training time: 12-24 hours for full training"
echo ""

# Launch training
python3 "$TRAINING_SCRIPT" 2>&1 | tee "$LOG_FILE"

echo ""
echo "✅ Real AGI training completed!"
echo "📊 Check results in:"
echo "   📝 Log: $LOG_FILE"
echo "   💾 Models: weights/real_agi_training/"
echo "   📈 Metrics: training_reports/real_agi_training/"
