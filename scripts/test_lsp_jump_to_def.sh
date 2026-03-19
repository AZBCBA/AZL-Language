#!/usr/bin/env bash
# LSP: textDocument/definition on azl/tests/lsp_definition_resolution.azl
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 required" >&2
  exit 50
fi

ROOT_DIR="$ROOT_DIR" python3 <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path

root = Path(os.environ["ROOT_DIR"])
lsp = root / "tools" / "azl_lsp.py"
fixture = root / "azl" / "tests" / "lsp_definition_resolution.azl"
if not fixture.is_file():
    sys.stderr.write(f"missing fixture {fixture}\n")
    sys.exit(60)

text = fixture.read_text(encoding="utf-8")
lines = text.splitlines()
uri = fixture.resolve().as_uri()


def frame(obj: dict) -> bytes:
    body = json.dumps(obj, separators=(",", ":")).encode("utf-8")
    return b"Content-Length: %d\r\n\r\n" % (len(body),) + body


def read_one(stream):
    line = stream.readline()
    if not line:
        return None
    if not line.startswith(b"Content-Length:"):
        sys.stderr.buffer.write(b"bad header: " + line + b"\n")
        sys.exit(61)
    n = int(line.decode().split(":", 1)[1].strip())
    stream.readline()
    payload = stream.read(n)
    if not payload:
        return None
    return json.loads(payload.decode())


def def_request(rid: int, line: int, character: int) -> dict:
    return {
        "jsonrpc": "2.0",
        "id": rid,
        "method": "textDocument/definition",
        "params": {
            "textDocument": {"uri": uri},
            "position": {"line": line, "character": character},
        },
    }


proc = subprocess.Popen(
    [sys.executable, str(lsp)],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)


def send(obj):
    proc.stdin.write(frame(obj))
    proc.stdin.flush()


send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"capabilities": {}}})
r1 = read_one(proc.stdout)
cap = (r1 or {}).get("result", {}).get("capabilities", {})
if not cap.get("definitionProvider"):
    sys.stderr.write("initialize: missing definitionProvider\n")
    sys.exit(62)

send(
    {
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": {
            "textDocument": {
                "uri": uri,
                "languageId": "azl",
                "version": 1,
                "text": text,
            }
        },
    }
)
diag = read_one(proc.stdout)
if not diag or diag.get("method") != "textDocument/publishDiagnostics":
    sys.stderr.write("expected diagnostics after didOpen\n")
    sys.exit(63)


def norm_locs(result):
    if result is None:
        return []
    if isinstance(result, list):
        return result
    return [result]


def assert_component_ref():
    row = next(i for i, L in enumerate(lines) if "link ::lsp.def.target" in L)
    col = lines[row].index("::")
    send(def_request(2, row, col))
    r = read_one(proc.stdout)
    res = (r or {}).get("result")
    locs = norm_locs(res)
    if len(locs) != 1:
        sys.stderr.write(f"component ref: want 1 loc, got {locs!r}\n")
        sys.exit(64)
    ln = locs[0]["range"]["start"]["line"]
    if ln != 3:
        sys.stderr.write(f"component ref: want definition line 3, got {ln}\n")
        sys.exit(65)
    if locs[0]["uri"] != uri:
        sys.stderr.write("component ref: uri mismatch\n")
        sys.exit(66)


def assert_listen_to_emits():
    row = next(i for i, L in enumerate(lines) if 'listen for "lsp.def.event"' in L)
    col = lines[row].index("lsp.def.event")
    send(def_request(3, row, col))
    r = read_one(proc.stdout)
    res = (r or {}).get("result")
    locs = norm_locs(res)
    lines_found = sorted({x["range"]["start"]["line"] for x in locs})
    if lines_found != [17, 21]:
        sys.stderr.write(f"listen->emit: want lines [17,21], got {lines_found!r} full={locs!r}\n")
        sys.exit(67)


def assert_emit_to_listen():
    row = next(i for i, L in enumerate(lines) if L.strip() == 'emit "lsp.def.event"' and i < 19)
    col = lines[row].index("lsp.def.event")
    send(def_request(4, row, col))
    r = read_one(proc.stdout)
    res = (r or {}).get("result")
    locs = norm_locs(res)
    lines_found = [x["range"]["start"]["line"] for x in locs]
    if 8 not in lines_found:
        sys.stderr.write(f"emit->listen: want line 8 in {lines_found!r}\n")
        sys.exit(68)


def assert_fn_call():
    row = next(i for i, L in enumerate(lines) if "lsp_def_fun(" in L and "fn " not in L)
    col = lines[row].index("lsp_def_fun")
    send(def_request(5, row, col))
    r = read_one(proc.stdout)
    res = (r or {}).get("result")
    locs = norm_locs(res)
    if len(locs) != 1 or locs[0]["range"]["start"]["line"] != 26:
        sys.stderr.write(f"fn call: want line 26, got {locs!r}\n")
        sys.exit(69)


assert_component_ref()
assert_listen_to_emits()
assert_emit_to_listen()
assert_fn_call()

send({"jsonrpc": "2.0", "id": 6, "method": "shutdown"})
read_one(proc.stdout)
send({"jsonrpc": "2.0", "method": "exit"})
proc.stdin.close()
proc.wait(timeout=5)
err = proc.stderr.read()
if err:
    sys.stderr.buffer.write(err)
print("lsp-jump-to-def-ok")
PY
