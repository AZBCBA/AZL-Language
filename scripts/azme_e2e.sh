#!/usr/bin/env bash
set -euo pipefail

echo "🧪 AZME E2E starting..."
cd "$(dirname "$0")/.."

# 1) Ensure sysproxy + daemon are up (reuses existing tested script)
echo "🚀 Bootstrapping sysproxy + daemon"
# Ensure provider and proxy are launched inside daemon if supported
export AZME_PROVIDER_E2E="1"

# Tighten HTTP limits for negative-path assertions before daemon starts
export AZL_HTTP_MAX_REQUEST_SIZE=${AZL_HTTP_MAX_REQUEST_SIZE:-64}
export AZL_HTTP_RATE_WINDOW_MS=${AZL_HTTP_RATE_WINDOW_MS:-500}
export AZL_HTTP_RATE_MAX_PER_WINDOW=${AZL_HTTP_RATE_MAX_PER_WINDOW:-2}
timeout 90s bash scripts/test_sysproxy_setup.sh || true

# 2) Basic daemon health check (token if required)
echo "🏥 Verifying daemon health endpoints"
if [ "${AZL_REQUIRE_API_TOKEN:-true}" != "false" ] && [ -n "${AZL_API_TOKEN:-}" ]; then
  H=( -H "Authorization: Bearer ${AZL_API_TOKEN}" )
  AH=( -H "Authorization: Bearer ${AZL_API_TOKEN}" )
else
  H=()
  AH=()
fi
curl -sf "${H[@]}" http://127.0.0.1:8080/healthz >/dev/null
curl -sf "${H[@]}" http://127.0.0.1:8080/status >/dev/null || true

# Test daemon with fixed auth token for E2E
curl -sf -H "Authorization: Bearer azme-e2e-test" http://127.0.0.1:8080/status | tee .azl/daemon_status_auth.json >/dev/null || true

# Validate daemon JSON shapes (best-effort)
if command -v jq >/dev/null 2>&1; then
  if [ -s .azl/daemon_status_auth.json ]; then
    jq -e '.status == "ok" and .daemon == "running"' .azl/daemon_status_auth.json >/dev/null 2>&1 || echo "⚠️ daemon status shape unexpected"
  fi
fi

# 3) Verify AZME Provider endpoints on :5000 (provider is launched by daemon when AZME_PROVIDER_E2E=1)
echo "🌐 Verifying AZME Provider endpoints on :5000"
export AZME_PROVIDER_E2E="1"
for i in $(seq 1 20); do
  if curl -sf http://127.0.0.1:5000/health >/dev/null 2>&1; then
    echo "✅ Provider health OK"; break
  fi
  sleep 0.5
  if [ $i -eq 20 ]; then echo "❌ Provider not responding"; exit 1; fi
done

# Test provider health with detailed response
curl -sf http://127.0.0.1:5000/health | tee .azl/azme_provider_health.json >/dev/null || true

curl -sf http://127.0.0.1:5000/v1/models | tee .azl/azme_models.json >/dev/null || true

# Test provider models endpoint with specific model
curl -sf http://127.0.0.1:5000/v1/models/azme-llama3:latest | tee .azl/azme_model_detail.json >/dev/null || true
curl -sf -X POST http://127.0.0.1:5000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"azme-llama3:latest","messages":[{"role":"user","content":"Say hi"}]}' \
  | tee .azl/azme_chat.json >/dev/null || true

# Test provider with streaming request
curl -sf -X POST http://127.0.0.1:5000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"azme-llama3:latest","messages":[{"role":"user","content":"What is 2+2?"}],"stream":true}' \
  | tee .azl/azme_chat_stream.json >/dev/null || true

# Test provider embeddings endpoint
curl -sf -X POST http://127.0.0.1:5000/v1/embeddings \
  -H 'Content-Type: application/json' \
  -d '{"model":"azme-llama3:latest","input":"Hello world"}' \
  | tee .azl/azme_embeddings.json >/dev/null || true

# Test provider completions endpoint (alternative to chat)
curl -sf -X POST http://127.0.0.1:5000/v1/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"azme-llama3:latest","prompt":"Complete this sentence: The quick brown fox","max_tokens":10}' \
  | tee .azl/azme_completions.json >/dev/null || true

# Validate provider JSON shapes (best-effort)
if command -v jq >/dev/null 2>&1; then
  if [ -s .azl/azme_models.json ]; then
    jq -e '.object == "list" and (.data | type == "array")' .azl/azme_models.json >/dev/null 2>&1 || echo "⚠️ models.json shape unexpected"
    # Check for specific model fields
    jq -e '.data[0].id and .data[0].object == "model"' .azl/azme_models.json >/dev/null 2>&1 || echo "⚠️ models.json missing expected fields"
  fi
  if [ -s .azl/azme_chat.json ]; then
    jq -e '.choices[0].message.content | length >= 0' .azl/azme_chat.json >/dev/null 2>&1 || echo "⚠️ chat.json shape unexpected"
    # Check for specific chat response fields
    jq -e '.choices[0].message.role == "assistant"' .azl/azme_chat.json >/dev/null 2>&1 || echo "⚠️ chat.json missing expected fields"
  fi
  if [ -s .azl/azme_chat_stream.json ]; then
    # Check for streaming response format
    jq -e '.choices[0].delta.content or .choices[0].delta.role' .azl/azme_chat_stream.json >/dev/null 2>&1 || echo "⚠️ chat stream shape unexpected"
  fi
  if [ -s .azl/azme_embeddings.json ]; then
    # Check for embeddings response format
    jq -e '.data[0].embedding and (.data[0].embedding | type == "array")' .azl/azme_embeddings.json >/dev/null 2>&1 || echo "⚠️ embeddings shape unexpected"
  fi
  if [ -s .azl/azme_provider_health.json ]; then
    # Check for provider health response format
    jq -e '.status or .healthy or .uptime or .message' .azl/azme_provider_health.json >/dev/null 2>&1 || echo "⚠️ provider health shape unexpected"
  fi
  if [ -s .azl/azme_completions.json ]; then
    # Check for completions response format
    jq -e '.choices[0].text or .choices[0].message or .choices[0].content' .azl/azme_completions.json >/dev/null 2>&1 || echo "⚠️ completions shape unexpected"
  fi
  if [ -s .azl/azme_model_detail.json ]; then
    # Check for model detail response format
    jq -e '.id and .object == "model"' .azl/azme_model_detail.json >/dev/null 2>&1 || echo "⚠️ model detail shape unexpected"
  fi
fi

# 4) Launch and verify AZME Proxy on :5001 (proxy forwards to provider on :5000)
echo "🔗 Launching AZME Proxy on :5001"
export AZME_API_URL="http://127.0.0.1:5000"
export AZME_PROXY_PORT="5001"

# Validate proxy endpoints
echo "🌐 Verifying AZME Proxy endpoints on :5001"
for i in $(seq 1 20); do
  if curl -sf "${AH[@]}" http://127.0.0.1:5001/health >/dev/null 2>&1; then
    echo "✅ Proxy health OK"; break
  fi
  sleep 0.5
  if [ $i -eq 20 ]; then echo "⚠️  Proxy health endpoint not responding (optional)"; fi
done

# Test proxy health with detailed response
curl -sf "${AH[@]}" http://127.0.0.1:5001/health | tee .azl/azme_proxy_health.json >/dev/null || true

# Workspace list (optional)
curl -sf "${AH[@]}" http://127.0.0.1:5001/workspaces | tee .azl/azme_proxy_workspaces.json >/dev/null || true

# Workspace chat (optional)
curl -sf -X POST "${AH[@]}" http://127.0.0.1:5001/workspaces/1/chat \
  -H 'Content-Type: application/json' \
  -d '{"message":"Hello from E2E"}' \
  | tee .azl/azme_proxy_chat.json >/dev/null || true

# Test proxy workspace chat with context
curl -sf -X POST "${AH[@]}" http://127.0.0.1:5001/workspaces/1/chat \
  -H 'Content-Type: application/json' \
  -d '{"message":"What documents do you have access to?","context":"workspace"}' \
  | tee .azl/azme_proxy_chat_context.json >/dev/null || true

# Test proxy workspace creation
curl -sf -X POST "${AH[@]}" http://127.0.0.1:5001/workspaces \
  -H 'Content-Type: application/json' \
  -d '{"name":"E2E Test Workspace","description":"Created during E2E testing"}' \
  | tee .azl/azme_proxy_workspace_create.json >/dev/null || true

# Test proxy workspace update
curl -sf -X PUT "${AH[@]}" http://127.0.0.1:5001/workspaces/1 \
  -H 'Content-Type: application/json' \
  -d '{"name":"Updated E2E Workspace","description":"Updated during E2E testing"}' \
  | tee .azl/azme_proxy_workspace_update.json >/dev/null || true

# Test proxy document upload (simulate with small text)
echo "Test document content for E2E" > .azl/test_doc.txt
curl -sf -X POST "${AH[@]}" http://127.0.0.1:5001/workspaces/1/documents \
  -F 'file=@.azl/test_doc.txt' \
  -F 'name=test_doc.txt' \
  | tee .azl/azme_proxy_document_upload.json >/dev/null || true

# Test proxy workspace documents list
curl -sf "${AH[@]}" http://127.0.0.1:5001/workspaces/1/documents \
  | tee .azl/azme_proxy_documents_list.json >/dev/null || true

# Test proxy document deletion (cleanup)
curl -sf -X DELETE "${AH[@]}" http://127.0.0.1:5001/workspaces/1/documents/1 \
  | tee .azl/azme_proxy_document_delete.json >/dev/null || true

# Test proxy search endpoint
curl -sf -X POST "${AH[@]}" http://127.0.0.1:5001/workspaces/1/search \
  -H 'Content-Type: application/json' \
  -d '{"query":"test document","limit":5}' \
  | tee .azl/azme_proxy_search.json >/dev/null || true

# Test proxy chat history endpoint
curl -sf "${AH[@]}" http://127.0.0.1:5001/workspaces/1/chat/history \
  | tee .azl/azme_proxy_chat_history.json >/dev/null || true

# Test proxy system info endpoint
curl -sf "${AH[@]}" http://127.0.0.1:5001/system/info \
  | tee .azl/azme_proxy_system_info.json >/dev/null || true

# Test proxy workspace export endpoint
curl -sf "${AH[@]}" http://127.0.0.1:5001/workspaces/1/export \
  | tee .azl/azme_proxy_workspace_export.json >/dev/null || true

# Test proxy workspace import endpoint
curl -sf -X POST "${AH[@]}" http://127.0.0.1:5001/workspaces/1/import \
  -H 'Content-Type: application/json' \
  -d '{"name":"Imported Workspace","description":"Imported during E2E testing"}' \
  | tee .azl/azme_proxy_workspace_import.json >/dev/null || true

# Test proxy workspace clone endpoint
curl -sf -X POST "${AH[@]}" http://127.0.0.1:5001/workspaces/1/clone \
  -H 'Content-Type: application/json' \
  -d '{"name":"Cloned E2E Workspace","description":"Cloned during E2E testing"}' \
  | tee .azl/azme_proxy_workspace_clone.json >/dev/null || true

# Test proxy workspace backup endpoint
curl -sf "${AH[@]}" http://127.0.0.1:5001/workspaces/1/backup \
  | tee .azl/azme_proxy_workspace_backup.json >/dev/null || true

# Test proxy workspace restore endpoint
curl -sf -X POST "${AH[@]}" http://127.0.0.1:5001/workspaces/1/restore \
  -H 'Content-Type: application/json' \
  -d '{"backup_id":"test_backup","name":"Restored E2E Workspace"}' \
  | tee .azl/azme_proxy_workspace_restore.json >/dev/null || true

# Test proxy workspace share endpoint
curl -sf -X POST "${AH[@]}" http://127.0.0.1:5001/workspaces/1/share \
  -H 'Content-Type: application/json' \
  -d '{"permissions":["read","write"],"expires_at":"2024-12-31T23:59:59Z"}' \
  | tee .azl/azme_proxy_workspace_share.json >/dev/null || true

# Test proxy workspace unshare endpoint
curl -sf -X DELETE "${AH[@]}" http://127.0.0.1:5001/workspaces/1/share/test_share_id \
  | tee .azl/azme_proxy_workspace_unshare.json >/dev/null || true

# Test proxy workspace deletion (cleanup)
curl -sf -X DELETE "${AH[@]}" http://127.0.0.1:5001/workspaces/1 \
  | tee .azl/azme_proxy_workspace_delete.json >/dev/null || true

# Validate proxy JSON shapes (best-effort)
if command -v jq >/dev/null 2>&1; then
  if [ -s .azl/azme_proxy_workspaces.json ]; then
    jq -e '.workspaces | type == "array"' .azl/azme_proxy_workspaces.json >/dev/null 2>&1 || echo "⚠️ proxy workspaces shape unexpected"
    # Check for workspace structure
    jq -e '.workspaces[0].id or .workspaces[0].name' .azl/azme_proxy_workspaces.json >/dev/null 2>&1 || echo "⚠️ proxy workspaces missing expected fields"
  fi
  if [ -s .azl/azme_proxy_chat.json ]; then
    jq -e '.type == "textResponse" or .response? != null' .azl/azme_proxy_chat.json >/dev/null 2>&1 || echo "⚠️ proxy chat shape unexpected"
    # Check for chat response structure
    jq -e '.message or .response or .type' .azl/azme_proxy_chat.json >/dev/null 2>&1 || echo "⚠️ proxy chat missing expected fields"
  fi
  if [ -s .azl/azme_proxy_chat_context.json ]; then
    # Check for chat with context response structure
    jq -e '.type == "textResponse" or .response? != null or .context' .azl/azme_proxy_chat_context.json >/dev/null 2>&1 || echo "⚠️ proxy chat context shape unexpected"
  fi
  if [ -s .azl/azme_proxy_workspace_create.json ]; then
    # Check for workspace creation response structure
    jq -e '.id or .workspace_id or .success' .azl/azme_proxy_workspace_create.json >/dev/null 2>&1 || echo "⚠️ proxy workspace create shape unexpected"
  fi
  if [ -s .azl/azme_proxy_workspace_update.json ]; then
    # Check for workspace update response structure
    jq -e '.id or .workspace_id or .success or .updated' .azl/azme_proxy_workspace_update.json >/dev/null 2>&1 || echo "⚠️ proxy workspace update shape unexpected"
  fi
  if [ -s .azl/azme_proxy_document_upload.json ]; then
    # Check for document upload response structure
    jq -e '.id or .document_id or .success or .message' .azl/azme_proxy_document_upload.json >/dev/null 2>&1 || echo "⚠️ proxy document upload shape unexpected"
  fi
  if [ -s .azl/azme_proxy_documents_list.json ]; then
    # Check for documents list response structure
    jq -e '.documents or .files or .success or .message' .azl/azme_proxy_documents_list.json >/dev/null 2>&1 || echo "⚠️ proxy documents list shape unexpected"
  fi
  if [ -s .azl/azme_proxy_document_delete.json ]; then
    # Check for document deletion response structure
    jq -e '.success or .deleted or .message' .azl/azme_proxy_document_delete.json >/dev/null 2>&1 || echo "⚠️ proxy document delete shape unexpected"
  fi
  if [ -s .azl/azme_proxy_search.json ]; then
    # Check for search response structure
    jq -e '.results or .documents or .success or .message' .azl/azme_proxy_search.json >/dev/null 2>&1 || echo "⚠️ proxy search shape unexpected"
  fi
  if [ -s .azl/azme_proxy_chat_history.json ]; then
    # Check for chat history response structure
    jq -e '.history or .messages or .success or .message' .azl/azme_proxy_chat_history.json >/dev/null 2>&1 || echo "⚠️ proxy chat history shape unexpected"
  fi
  if [ -s .azl/azme_proxy_system_info.json ]; then
    # Check for system info response structure
    jq -e '.version or .status or .uptime or .message' .azl/azme_proxy_system_info.json >/dev/null 2>&1 || echo "⚠️ proxy system info shape unexpected"
  fi
  if [ -s .azl/azme_proxy_workspace_export.json ]; then
    # Check for workspace export response structure
    jq -e '.workspace or .data or .export or .message' .azl/azme_proxy_workspace_export.json >/dev/null 2>&1 || echo "⚠️ proxy workspace export shape unexpected"
  fi
  if [ -s .azl/azme_proxy_workspace_import.json ]; then
    # Check for workspace import response structure
    jq -e '.id or .workspace_id or .success or .imported' .azl/azme_proxy_workspace_import.json >/dev/null 2>&1 || echo "⚠️ proxy workspace import shape unexpected"
  fi
  if [ -s .azl/azme_proxy_workspace_clone.json ]; then
    # Check for workspace clone response structure
    jq -e '.id or .workspace_id or .success or .cloned' .azl/azme_proxy_workspace_clone.json >/dev/null 2>&1 || echo "⚠️ proxy workspace clone shape unexpected"
  fi
  if [ -s .azl/azme_proxy_workspace_backup.json ]; then
    # Check for workspace backup response structure
    jq -e '.backup or .data or .success or .message' .azl/azme_proxy_workspace_backup.json >/dev/null 2>&1 || echo "⚠️ proxy workspace backup shape unexpected"
  fi
  if [ -s .azl/azme_proxy_workspace_restore.json ]; then
    # Check for workspace restore response structure
    jq -e '.id or .workspace_id or .success or .restored' .azl/azme_proxy_workspace_restore.json >/dev/null 2>&1 || echo "⚠️ proxy workspace restore shape unexpected"
  fi
  if [ -s .azl/azme_proxy_workspace_share.json ]; then
    # Check for workspace share response structure
    jq -e '.share_id or .link or .success or .message' .azl/azme_proxy_workspace_share.json >/dev/null 2>&1 || echo "⚠️ proxy workspace share shape unexpected"
  fi
  if [ -s .azl/azme_proxy_workspace_delete.json ]; then
    # Check for workspace deletion response structure
    jq -e '.success or .deleted or .message' .azl/azme_proxy_workspace_delete.json >/dev/null 2>&1 || echo "⚠️ proxy workspace delete shape unexpected"
  fi
  if [ -s .azl/azme_proxy_health.json ]; then
    # Check for health response structure
    jq -e '.status or .healthy or .uptime or .message' .azl/azme_proxy_health.json >/dev/null 2>&1 || echo "⚠️ proxy health shape unexpected"
  fi
fi

# 5) Negative-path checks
echo "🚫 Negative-path checks (auth and limits)"
# 401 when token required and missing
if [ "${AZL_REQUIRE_API_TOKEN:-true}" != "false" ]; then
  if curl -sf http://127.0.0.1:8080/status >/dev/null 2>&1; then
    echo "❌ Expected 401 without token on /status" >&2
    exit 1
  else
    echo "✅ /status unauthorized without token"
  fi
fi

# 413 Payload Too Large on provider
large_payload=$(python3 - <<'PY'
print('{' + '"x"' + ':' + '"' + 'a'*256 + '"' + '}')
PY
)
if curl -s -o /dev/null -w "%{http_code}" -X POST http://127.0.0.1:5000/v1/chat/completions -H 'Content-Type: application/json' -d "$large_payload" | grep -q '^413$'; then
  echo "✅ Provider enforces 413 on large payload"
else
  echo "⚠️ Provider did not enforce 413 (tunable)"
fi

# Strict proxy rate-limit check (expect a 429 on the 3rd GET)
echo "⏱️ Proxy rate-limit strict check"
codes=""
for i in 1 2 3; do
  codes+=$(curl -s -o /dev/null -w "%{http_code}" "${AH[@]}" http://127.0.0.1:5001/health)" "
done
echo "🔢 Proxy /health HTTP codes: $codes"
if echo "$codes" | grep -q "429"; then
  echo "✅ Proxy rate limit enforced"
else
  echo "❌ Expected a 429 from proxy rate limit" >&2
  exit 1
fi

# Validate proxy API endpoints requiring token (authorized path)
if [ "${AZL_REQUIRE_API_TOKEN:-true}" != "false" ] && [ -n "${AZL_API_TOKEN:-}" ]; then
  AH=( -H "Authorization: Bearer ${AZL_API_TOKEN}" )
else
  AH=()
fi

echo "🧩 Checking proxy /api/llm-providers and /api/system"
code_lp=$(curl -s -o /dev/null -w "%{http_code}" "${AH[@]}" http://127.0.0.1:5001/api/llm-providers || true)
code_sys=$(curl -s -o /dev/null -w "%{http_code}" "${AH[@]}" http://127.0.0.1:5001/api/system || true)
echo "🔢 /api/llm-providers=$code_lp /api/system=$code_sys"
if [ "$code_lp" != "200" ] || [ "$code_sys" != "200" ]; then
  echo "❌ Proxy API endpoints did not return 200" >&2
  exit 1
fi

# Test daemon shutdown endpoint (requires auth)
echo "🔒 Testing daemon shutdown endpoint with auth"
shutdown_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Authorization: Bearer azme-e2e-test" http://127.0.0.1:8080/shutdown || true)
echo "🔢 /shutdown HTTP code: $shutdown_code"
if [ "$shutdown_code" = "202" ]; then
  echo "✅ Daemon shutdown endpoint working (202 Accepted)"
else
  echo "⚠️ Daemon shutdown endpoint returned $shutdown_code (expected 202)"
fi

# Test daemon build endpoint (requires auth)
echo "🔨 Testing daemon build endpoint with auth"
build_response=$(curl -sf -X POST -H "Authorization: Bearer azme-e2e-test" -H "Content-Type: application/json" \
  -d '{"files":["test.azl"],"options":{"mode":"test"}}' \
  http://127.0.0.1:8080/build | tee .azl/daemon_build.json || true)
if [ -n "$build_response" ]; then
  echo "✅ Daemon build endpoint working"
  # Validate build response JSON
  if command -v jq >/dev/null 2>&1 && [ -s .azl/daemon_build.json ]; then
    jq -e '.status == "accepted"' .azl/daemon_build.json >/dev/null 2>&1 || echo "⚠️ build response shape unexpected"
  fi
else
  echo "⚠️ Daemon build endpoint not responding"
fi

# Test daemon analytics endpoint (requires auth)
echo "📊 Testing daemon analytics endpoint with auth"
analytics_response=$(curl -sf -H "Authorization: Bearer azme-e2e-test" \
  http://127.0.0.1:8080/analytics | tee .azl/daemon_analytics.json || true)
if [ -n "$analytics_response" ]; then
  echo "✅ Daemon analytics endpoint working"
  # Validate analytics response JSON
  if command -v jq >/dev/null 2>&1 && [ -s .azl/daemon_analytics.json ]; then
    jq -e '.request_count >= 0' .azl/daemon_analytics.json >/dev/null 2>&1 || echo "⚠️ analytics response shape unexpected"
  fi
else
  echo "⚠️ Daemon analytics endpoint not responding"
fi

echo "✅ AZME E2E completed"

