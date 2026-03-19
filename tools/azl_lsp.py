#!/usr/bin/env python3
"""
Minimal AZL Language Server Protocol (LSP) implementation.
Uses JSON-RPC over stdin/stdout. Supports: initialize, hover, completion.
"""
import json
import sys
import re

AZL_KEYWORDS = [
    "component", "init", "behavior", "memory", "emit", "listen", "for", "then",
    "set", "let", "fn", "function", "return", "if", "else", "while", "for",
    "link", "say", "store", "from", "store", "from"
]

def read_message():
    """Read one LSP message (Content-Length header + JSON body)."""
    header = sys.stdin.readline()
    if not header:
        return None
    m = re.match(r"Content-Length:\s*(\d+)", header)
    if not m:
        return None
    length = int(m.group(1))
    sys.stdin.readline()  # blank line
    body = sys.stdin.read(length)
    return json.loads(body) if body else None

def write_message(msg):
    """Write one LSP message."""
    body = json.dumps(msg).encode("utf-8")
    sys.stdout.buffer.write(f"Content-Length: {len(body)}\r\n\r\n".encode("ascii"))
    sys.stdout.buffer.write(body)
    sys.stdout.buffer.flush()

def handle_initialize(msg):
    """Respond to initialize request."""
    return {
        "jsonrpc": "2.0",
        "id": msg.get("id"),
        "result": {
            "capabilities": {
                "hoverProvider": True,
                "completionProvider": {"triggerCharacters": [".", ":", ":"]},
                "textDocumentSync": {"openClose": True, "change": 1}
            },
            "serverInfo": {"name": "azl-lsp", "version": "0.1.0"}
        }
    }

def handle_hover(msg):
    """Respond to textDocument/hover."""
    params = msg.get("params", {})
    text = params.get("textDocument", {}).get("uri", "")
    pos = params.get("position", {})
    return {
        "jsonrpc": "2.0",
        "id": msg.get("id"),
        "result": {
            "contents": {"kind": "markdown", "value": "**AZL**\n\nComponent-based, event-driven language. See docs/language/AZL_LANGUAGE_RULES.md"}
        }
    }

def handle_completion(msg):
    """Respond to textDocument/completion with AZL keywords."""
    items = [{"label": kw, "kind": 14} for kw in AZL_KEYWORDS]
    return {
        "jsonrpc": "2.0",
        "id": msg.get("id"),
        "result": {"isIncomplete": False, "items": items}
    }

def main():
    while True:
        msg = read_message()
        if not msg:
            break
        method = msg.get("method")
        if method == "initialize":
            write_message(handle_initialize(msg))
        elif method == "initialized":
            pass
        elif method == "textDocument/hover":
            write_message(handle_hover(msg))
        elif method == "textDocument/completion":
            write_message(handle_completion(msg))
        elif method and method.startswith("textDocument/"):
            pass
        elif "id" in msg and "result" not in msg:
            write_message({"jsonrpc": "2.0", "id": msg["id"], "result": None})

if __name__ == "__main__":
    main()
