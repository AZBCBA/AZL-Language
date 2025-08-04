#!/bin/bash

echo "🚀 AZME + AnythingLLM Integration Setup"
echo "========================================"

# Check if AZME API is running
echo "1. Checking AZME API status..."
if curl -s http://localhost:8000/health > /dev/null; then
    echo "   ✅ AZME API is running on http://localhost:8000"
else
    echo "   ❌ AZME API is not running"
    echo "   Starting AZME API..."
    cd /mnt/ssd4t/AZME
    source azme_gpu_env/bin/activate
    python azme_anythingllm_api.py &
    sleep 10
fi

# Check if AnythingLLM is running
echo "2. Checking AnythingLLM status..."
if pgrep -f "anythingllm-desktop" > /dev/null; then
    echo "   ✅ AnythingLLM is running"
else
    echo "   ❌ AnythingLLM is not running"
    echo "   Starting AnythingLLM..."
    cd /home/abdulrahman-alzalameh/AnythingLLMDesktop/anythingllm-desktop
    ./anythingllm-desktop --no-sandbox &
    sleep 10
fi

echo ""
echo "📋 Integration Instructions:"
echo "============================"
echo ""
echo "1. Open AnythingLLM in your browser (it should open automatically)"
echo ""
echo "2. Add AZME as a Custom LLM Provider:"
echo "   - Go to Settings > LLM Providers"
echo "   - Click 'Add Custom Provider'"
echo "   - Use these settings:"
echo "     * Name: AZME Quantum AI"
echo "     * API Base: http://localhost:8000"
echo "     * API Key: (leave empty)"
echo "     * Model: AZME-Qwen-72B"
echo ""
echo "3. Create a workspace:"
echo "   - Click 'New Workspace'"
echo "   - Select 'AZME Quantum AI' as the LLM provider"
echo "   - Upload your documents"
echo "   - Start chatting with AZME!"
echo ""
echo "4. Test the integration:"
echo "   - Ask questions about your documents"
echo "   - AZME will process through quantum systems and LHA3 memory"
echo "   - You'll get responses enhanced by the full AZME pipeline"
echo ""
echo "🔧 Troubleshooting:"
echo "=================="
echo ""
echo "If AnythingLLM doesn't open automatically:"
echo "  - Check if it's running: ps aux | grep anythingllm"
echo "  - Restart it: cd /home/abdulrahman-alzalameh/AnythingLLMDesktop/anythingllm-desktop && ./anythingllm-desktop --no-sandbox"
echo ""
echo "If AZME API isn't responding:"
echo "  - Check status: curl http://localhost:8000/health"
echo "  - Restart AZME: cd /mnt/ssd4t/AZME && source azme_gpu_env/bin/activate && python azme_anythingllm_api.py"
echo ""
echo "✅ Setup complete! AZME is ready to use with AnythingLLM!" 