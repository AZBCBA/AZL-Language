#!/bin/bash

# Background Training Script
# Runs continuous real training in the background

echo "🚀 Starting Background Real Training System"

# Create weights directory if it doesn't exist
mkdir -p weights/continuous_training

# Run the continuous training system via native runtime
echo "📊 Starting continuous training..."
bash scripts/start_azl_native_mode.sh > logs/real_training.log 2>&1 &

# Get the process ID
TRAINING_PID=$!

echo "✅ Training started with PID: $TRAINING_PID"
echo "📝 Logs are being written to: logs/real_training.log"
echo "💾 Weights will be saved to: weights/continuous_training/"

# Save the PID to a file for later reference
echo $TRAINING_PID > training.pid

echo "🎯 Training is now running in the background"
echo "📊 To check status: tail -f logs/real_training.log"
echo "🛑 To stop training: kill $TRAINING_PID"
echo "📁 To check weights: ls -la weights/continuous_training/"
