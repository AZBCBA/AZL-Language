#!/bin/bash
set -eu

# Test script for sysproxy setup
echo "🧪 Testing sysproxy setup..."

# Clean slate
echo "🧹 Cleaning up..."
(pkill -f sysproxy || true) 2>/dev/null || true
(pkill -f azl_syswire || true) 2>/dev/null || true
(pkill -f run_enterprise_daemon || true) 2>/dev/null || true
rm -f .azl/{engine.in,engine.out,sysproxy.out,sysproxy.log,wire.log,daemon.out} 2>/dev/null || true
sleep 0.3

# Ensure FIFOs exist
echo "🔌 Creating FIFOs..."
mkdir -p .azl
rm -f .azl/engine.in .azl/engine.out
mkfifo .azl/engine.in .azl/engine.out
# Ensure daemon log is writable
: > .azl/daemon.out
chmod 664 .azl/daemon.out || true

# Start sysproxy
echo "🚀 Starting sysproxy..."
./.azl/sysproxy 1>.azl/sysproxy.out 2>.azl/sysproxy.log &
echo $! > .azl/sysproxy.pid
sleep 0.2

# Start the wire
echo "🔌 Starting wire..."
bash scripts/azl_syswire.sh .azl/engine.out .azl/engine.in 2>.azl/wire.log &
echo $! > .azl/syswire.pid
sleep 0.2

# Start the daemon
echo "🚀 Starting daemon..."
./scripts/run_enterprise_daemon.sh &
echo $! > .azl/daemon.pid

# Watch for requests
echo "👀 Watching for requests..."
stdbuf -oL sed -n 's/^@sysproxy /REQ: /p' .azl/daemon.out &
echo $! > .azl/watcher.pid

# Wait a bit and check status
echo "⏳ Waiting for startup..."
sleep 3

# Check if port 8080 is bound
echo "🔍 Checking port 8080..."
if ss -ltn 2>/dev/null | grep -q ":8080"; then
    echo "✅ Port 8080 is bound!"
else
    echo "⚠️  Port 8080 not bound yet"
fi

# Test health endpoint with retries
echo "🏥 Testing health endpoint..."
for i in {1..10}; do
  if curl -sSf http://127.0.0.1:8080/healthz >/dev/null 2>&1; then
    echo "✅ Health endpoint responding!"; break
  fi
  sleep 0.5
  if [ $i -eq 10 ]; then echo "⚠️  Health endpoint not responding"; fi
done

echo ""
echo "📊 Log files:"
echo "  .azl/daemon.out - Engine output"
echo "  .azl/sysproxy.log - Sysproxy logs"
echo "  .azl/wire.log - Wire logs"
echo ""
echo "🔍 To monitor:"
echo "  tail -f .azl/daemon.out | grep '@sysproxy'"
echo "  tail -f .azl/sysproxy.log"
echo "  tail -f .azl/wire.log"
echo ""
echo "🧹 To cleanup:"
echo "  pkill -f sysproxy azl_syswire run_enterprise_daemon || true"
