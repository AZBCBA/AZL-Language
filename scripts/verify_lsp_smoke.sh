#!/usr/bin/env bash
# LSP smoke: initialize + textDocument/didOpen → expect textDocument/publishDiagnostics
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
lsp = os.path.join(root, "tools", "azl_lsp.py")


def frame(obj: dict) -> bytes:
    body = json.dumps(obj, separators=(",", ":")).encode("utf-8")
    return b"Content-Length: %d\r\n\r\n" % (len(body),) + body


def read_one(stream):
    line = stream.readline()
    if not line:
        return None
    if not line.startswith(b"Content-Length:"):
        sys.stderr.buffer.write(b"bad header: " + line + b"\n")
        sys.exit(51)
    n = int(line.decode().split(":", 1)[1].strip())
    stream.readline()
    payload = stream.read(n)
    if not payload:
        return None
    return json.loads(payload.decode())


proc = subprocess.Popen(
    [sys.executable, lsp],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)

def send(obj):
    proc.stdin.write(frame(obj))
    proc.stdin.flush()

send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"capabilities": {}}})
r1 = read_one(proc.stdout)
if not r1 or "result" not in r1 or "capabilities" not in r1["result"]:
    sys.stderr.write("bad initialize: " + json.dumps(r1 or {}) + "\n")
    sys.exit(52)
cap = r1["result"]["capabilities"]
if not cap.get("hoverProvider"):
    sys.stderr.write("missing hoverProvider\n")
    sys.exit(53)

uri = "file:///tmp/azl_lsp_smoke.azl"
bad = "class Broken {}\nimport os\ndef foo():\n  pass\n"
send(
    {
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": {
            "textDocument": {
                "uri": uri,
                "languageId": "azl",
                "version": 1,
                "text": bad,
            }
        },
    }
)

r2 = read_one(proc.stdout)
if not r2:
    sys.stderr.write("no diagnostics message\n")
    sys.exit(54)
if r2.get("method") != "textDocument/publishDiagnostics":
    sys.stderr.write("expected publishDiagnostics, got: " + json.dumps(r2) + "\n")
    sys.exit(55)
params = r2.get("params") or {}
if params.get("uri") != uri:
    sys.stderr.write("diagnostic uri mismatch\n")
    sys.exit(56)
diags = params.get("diagnostics") or []
if len(diags) < 2:
    sys.stderr.write("expected multiple diagnostics, got: " + json.dumps(diags) + "\n")
    sys.exit(57)
codes = {d.get("code") for d in diags}
need = {"AZL_HOST_CLASS", "AZL_HOST_IMPORT", "AZL_HOST_DEF"}
if not need.issubset(codes):
    sys.stderr.write("missing expected codes; have " + str(codes) + "\n")
    sys.exit(58)

send({"jsonrpc": "2.0", "id": 2, "method": "shutdown"})
read_one(proc.stdout)
send({"jsonrpc": "2.0", "method": "exit"})
proc.stdin.close()
proc.wait(timeout=5)
err = proc.stderr.read()
if err:
    sys.stderr.buffer.write(err)
print("lsp-smoke-ok")
PY
)"

echo "$OUT"
if ! echo "$OUT" | rg -q "lsp-smoke-ok"; then
  echo "ERROR: LSP smoke failed" >&2
  exit 55
fi
