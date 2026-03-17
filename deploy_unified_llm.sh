#!/bin/bash

# Unified LLM Deployment Script
# Deploys all trained models as a single, intelligent NLP system

set -e

echo "🚀 AZL Unified LLM Deployment Starting..."
echo "=========================================="

# Check if we're in the right directory
if [ ! -f "unified_llm_deployment.py" ]; then
    echo "❌ Error: Please run this script from the azl-language directory"
    exit 1
fi

# Check Python dependencies
echo "🔍 Checking Python dependencies..."
python3 -c "import torch" 2>/dev/null || {
    echo "❌ PyTorch not found. Installing..."
    pip3 install torch
}

# Check available models
echo "📊 Analyzing available trained models..."
python3 unified_llm_deployment.py --mode status

# Deploy the system
echo "🚀 Deploying Unified LLM System..."
python3 unified_llm_deployment.py --mode deploy

# Create systemd service file for production deployment
echo "🔧 Creating systemd service for production deployment..."
sudo tee /etc/systemd/system/azl-unified-llm.service > /dev/null <<EOF
[Unit]
Description=AZL Unified LLM System
After=network.target
Wants=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$(pwd)
ExecStart=/usr/bin/python3 $(pwd)/unified_llm_deployment.py --mode chat
Restart=always
RestartSec=10
Environment=PYTHONPATH=$(pwd)
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Create monitoring script
echo "📊 Creating monitoring script..."
cat > monitor_unified_llm.sh << 'EOF'
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
EOF

chmod +x monitor_unified_llm.sh

# Create quick start script
echo "🚀 Creating quick start script..."
cat > start_unified_llm.sh << 'EOF'
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
EOF

chmod +x start_unified_llm.sh

# Create production configuration
echo "⚙️ Creating production configuration..."
cat > unified_llm_config.json << 'EOF'
{
    "system": {
        "name": "AZL Unified LLM",
        "version": "1.0.0",
        "deployment_mode": "production",
        "auto_scaling": true,
        "load_balancing": true,
        "monitoring": true
    },
    "models": {
        "weights_available_data_training": {
            "enabled": true,
            "priority": 1,
            "specialization": "General language understanding and generation"
        },
        "weights_real_agi_training": {
            "enabled": true,
            "priority": 2,
            "specialization": "AGI reasoning and cognitive tasks"
        },
        "checkpoint_master_training": {
            "enabled": true,
            "priority": 3,
            "specialization": "Master language model with comprehensive training"
        },
        "production_continuous": {
            "enabled": true,
            "priority": 4,
            "specialization": "Continuous learning and adaptation"
        }
    },
    "routing": {
        "intelligent_routing": true,
        "fallback_model": "weights_available_data_training",
        "routing_cache_size": 1000
    },
    "performance": {
        "max_workers": 4,
        "response_timeout": 30,
        "memory_limit_gb": 8
    }
}
EOF

echo ""
echo "🎉 AZL Unified LLM Deployment Complete!"
echo "========================================"
echo ""
echo "📋 Available Commands:"
echo "  ./start_unified_llm.sh          - Start interactive chat"
echo "  ./monitor_unified_llm.sh        - Monitor system status"
echo "  python3 unified_llm_deployment.py --mode status    - Show system status"
echo "  python3 unified_llm_deployment.py --mode deploy    - Deploy system"
echo ""
echo "🚀 Quick Start:"
echo "  ./start_unified_llm.sh"
echo ""
echo "📊 Monitor System:"
echo "  ./monitor_unified_llm.sh"
echo ""
echo "🔧 Production Service:"
echo "  sudo systemctl enable azl-unified-llm.service"
echo "  sudo systemctl start azl-unified-llm.service"
echo ""
echo "✅ Your unified LLM system is ready for production use!"
echo "🎯 All trained models are now integrated into a single, intelligent NLP system!"
