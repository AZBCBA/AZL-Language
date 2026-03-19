#!/usr/bin/env bash
# One JSON-RPC round-trip: initialize → expect capabilities from tools/azl_lsp.py
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 required for LSP smoke" >&2
  exit 50
fi

OUT="$(
  ROOT_DIR="$ROOT_DIR" python3 <<'PY'
import json
import os
import subprocess
import sys

root = os.environ["ROOT_DIR"]
proc = subprocess.Popen(
    [sys.executable, os.path.join(root, "tools", "azl_lsp.py")],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
msg = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"capabilities": {}}}
body = json.dumps(msg).encode("utf-8")
header = b"Content-Length: %d\r\n\r\n" % (len(body),)
proc.stdin.write(header + body)
proc.stdin.close()
line = proc.stdout.readline()
if not line.startswith(b"Content-Length:"):
    sys.stderr.buffer.write(b"bad header: " + line + b"\n")
    sys.exit(51)
n = int(line.decode().split(":", 1)[1].strip())
proc.stdout.readline()
payload = proc.stdout.read(n)
err = proc.stderr.read()
proc.wait()
if proc.returncode not in (0, None):
    if err:
        sys.stderr.buffer.write(err)
if not payload:
    sys.stderr.write("empty LSP response\n")
    sys.exit(52)
data = json.loads(payload.decode())
if "result" not in data or "capabilities" not in data["result"]:
    sys.stderr.write("bad initialize result: " + json.dumps(data) + "\n")
    sys.exit(53)
cap = data["result"]["capabilities"]
if not cap.get("hoverProvider"):
    sys.stderr.write("missing hoverProvider\n")
    sys.exit(54)
print("lsp-smoke-ok")
PY
)"

echo "$OUT"
if ! echo "$OUT" | rg -q "lsp-smoke-ok"; then
  echo "ERROR: LSP smoke failed" >&2
  exit 55
fi
