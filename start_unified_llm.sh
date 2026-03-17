#!/bin/bash
echo "🚀 Starting AZL Unified LLM..."
echo "================================"
echo "Available modes:"
echo "  chat     - Interactive chat mode"
echo "  status   - System status"
echo "  test     - Test with input"
echo "  deploy   - Deploy system"
echo ""
echo "Starting interactive chat mode..."
python3 unified_llm_deployment.py --mode chat
