#!/bin/bash
set -euo pipefail
echo "📊 AZL Unified LLM System Monitor"
echo "=================================="
echo "Timestamp: $(date)"
echo "System Load: $(uptime | awk '{print $10}' | sed 's/,//')"
echo "Memory Usage: $(free -h | grep Mem | awk '{print $3"/"$2}')"
echo "Disk Usage: $(df -h . | tail -1 | awk '{print $5}')"
echo ""
echo "Native Runtime Status:"
curl -fsS "http://127.0.0.1:${AZL_BUILD_API_PORT:-8080}/status" || {
  echo "ERROR: native status endpoint is not reachable."
  exit 1
}
