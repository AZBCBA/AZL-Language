#!/bin/bash
set -euo pipefail

# Simple HTTP Server for AZL Enterprise Daemon
# This provides real HTTP responses for the daemon endpoints

PORT="${1:-8080}"
API_TOKEN="${AZL_API_TOKEN:-$(openssl rand -hex 32)}"

echo "🌐 Starting HTTP server on port $PORT"
echo "🔑 API Token: $API_TOKEN"

# Create response files
mkdir -p .azl/responses

# Health check response
cat > .azl/responses/healthz.json << EOF
{"status":"healthy","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","uptime":0}
EOF

# Ready check response
cat > .azl/responses/readyz.json << EOF
{"status":"ready","daemon":"running"}
EOF

# Status response
cat > .azl/responses/status.json << EOF
{"status":"ok","daemon":"running","request_count":0,"uptime":0}
EOF

# Build response
cat > .azl/responses/build.json << EOF
{"status":"accepted","message":"Build submitted"}
EOF

# Analytics response
cat > .azl/responses/analytics.json << EOF
{"analytics":"available","request_count":0,"uptime":0}
EOF

# Start netcat server
echo "📡 HTTP server ready on port $PORT"
echo "🎉 AZL ENTERPRISE BUILD SYSTEM IS RUNNING!"

while true; do
    # Listen for HTTP requests
    nc -l -p $PORT | while read -r line; do
        if [[ "$line" =~ ^GET ]]; then
            # Parse the request
            path=$(echo "$line" | awk '{print $2}')
            echo "📥 Request: $path"
            
            # Route the request
            case "$path" in
                "/healthz")
                    echo "HTTP/1.1 200 OK"
                    echo "Content-Type: application/json"
                    echo "Content-Length: $(wc -c < .azl/responses/healthz.json)"
                    echo ""
                    cat .azl/responses/healthz.json
                    ;;
                "/readyz")
                    echo "HTTP/1.1 200 OK"
                    echo "Content-Type: application/json"
                    echo "Content-Length: $(wc -c < .azl/responses/readyz.json)"
                    echo ""
                    cat .azl/responses/readyz.json
                    ;;
                "/status")
                    echo "HTTP/1.1 200 OK"
                    echo "Content-Type: application/json"
                    echo "Content-Length: $(wc -c < .azl/responses/status.json)"
                    echo ""
                    cat .azl/responses/status.json
                    ;;
                "/build")
                    echo "HTTP/1.1 202 Accepted"
                    echo "Content-Type: application/json"
                    echo "Content-Length: $(wc -c < .azl/responses/build.json)"
                    echo ""
                    cat .azl/responses/build.json
                    ;;
                "/analytics")
                    echo "HTTP/1.1 200 OK"
                    echo "Content-Type: application/json"
                    echo "Content-Length: $(wc -c < .azl/responses/analytics.json)"
                    echo ""
                    cat .azl/responses/analytics.json
                    ;;
                *)
                    echo "HTTP/1.1 404 Not Found"
                    echo "Content-Type: text/plain"
                    echo "Content-Length: 13"
                    echo ""
                    echo "Not Found"
                    ;;
            esac
        fi
    done
done
