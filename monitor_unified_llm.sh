#!/bin/bash
echo "📊 AZL Unified LLM System Monitor"
echo "=================================="
echo "Timestamp: $(date)"
echo "System Load: $(uptime | awk '{print $10}' | sed 's/,//')"
echo "Memory Usage: $(free -h | grep Mem | awk '{print $3"/"$2}')"
echo "Disk Usage: $(df -h . | tail -1 | awk '{print $5}')"
echo ""
echo "Model Status:"
python3 unified_llm_deployment.py --mode status
