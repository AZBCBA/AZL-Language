#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# 0) Ensure services are up
/usr/local/bin/azl-ctl start all

# 1) Health checks
curl -sfm 3 http://127.0.0.1:8080/healthz >/dev/null
curl -sfm 3 http://127.0.0.1:5000/health >/dev/null
curl -sfm 3 http://127.0.0.1:5001/health >/dev/null

# 2) Provider API basic
curl -sfm 3 http://127.0.0.1:5000/v1/models | jq -e '.object=="list" and (.data|type=="array")' >/dev/null
curl -sfm 3 -X POST http://127.0.0.1:5000/v1/completions -H 'Content-Type: application/json' -d '{"prompt":"ping"}' | jq -e '.choices[0].text|length>=1' >/dev/null

# 3) Proxy API & rate limit
curl -sfm 3 http://127.0.0.1:5001/api/llm-providers | jq -e 'type=="array"' >/dev/null
codes=""; for i in 1 2 3; do codes+=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:5001/health)" "; done; echo "$codes" | grep -q '429' || (echo 'rate limit not enforced' >&2; exit 1)

# 4) Runtime metrics responds
curl -sfm 3 http://127.0.0.1:8080/metrics | grep -q '^azl_runtime_info' || (echo 'metrics missing' >&2; exit 1)

# 5) Size limit enforced (413) on provider
LARGE=$(python3 - <<'PY'
print('{'+'"x"'+':'+'"'+'a'*2048+'"'+'}')
PY
)
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:5000/v1/chat/completions -H 'Content-Type: application/json' -d "$LARGE")
[[ "$code" == "413" ]] || (echo "expected 413, got $code" >&2; exit 1)

echo 'OK'
