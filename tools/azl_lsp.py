#!/usr/bin/env python3
"""
AZL Language Server Protocol (LSP) over stdin/stdout (JSON-RPC).
Supports: initialize, hover, completion, push diagnostics (didOpen/didChange).
"""
import json
import re
import sys

AZL_KEYWORDS = [
    "component", "init", "behavior", "memory", "emit", "listen", "for", "then",
    "set", "let", "fn", "function", "return", "if", "else", "while", "for",
    "link", "say", "store", "from", "store", "from",
]

# Open documents: uri -> full text
_DOCS: dict[str, str] = {}


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
    body = json.dumps(msg, separators=(",", ":")).encode("utf-8")
    sys.stdout.buffer.write(f"Content-Length: {len(body)}\r\n\r\n".encode("ascii"))
    sys.stdout.buffer.write(body)
    sys.stdout.buffer.flush()


def compute_diagnostics(text: str) -> list:
    """Heuristic AZL vs host-language hints (not a full parser)."""
    out: list = []
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if re.search(r"\bclass\s+[A-Za-z_]", line):
            c = line.find("class")
            c = c if c >= 0 else 0
            out.append(
                {
                    "range": {
                        "start": {"line": i, "character": c},
                        "end": {"line": i, "character": len(line)},
                    },
                    "severity": 2,
                    "code": "AZL_HOST_CLASS",
                    "source": "azl-lsp",
                    "message": "Host-style `class` is not AZL; use `component ::name { ... }`.",
                }
            )
        if re.search(r"^\s*import\s+\w", line):
            col = re.search(r"\bimport\b", line)
            sc = col.start() if col else 0
            out.append(
                {
                    "range": {
                        "start": {"line": i, "character": sc},
                        "end": {"line": i, "character": len(line)},
                    },
                    "severity": 2,
                    "code": "AZL_HOST_IMPORT",
                    "source": "azl-lsp",
                    "message": "Python-style `import` is not AZL; use `load_component` / event wiring.",
                }
            )
        if re.search(r"^\s*def\s+[a-zA-Z_]", line):
            col = re.search(r"\bdef\b", line)
            sc = col.start() if col else 0
            out.append(
                {
                    "range": {
                        "start": {"line": i, "character": sc},
                        "end": {"line": i, "character": len(line)},
                    },
                    "severity": 2,
                    "code": "AZL_HOST_DEF",
                    "source": "azl-lsp",
                    "message": "Python-style `def` is not AZL; use `fn` / `listen` / `behavior` blocks.",
                }
            )
    return out


def publish_diagnostics(uri: str, diagnostics: list) -> dict:
    return {
        "jsonrpc": "2.0",
        "method": "textDocument/publishDiagnostics",
        "params": {"uri": uri, "diagnostics": diagnostics},
    }


def handle_initialize(msg):
    return {
        "jsonrpc": "2.0",
        "id": msg.get("id"),
        "result": {
            "capabilities": {
                "hoverProvider": True,
                "completionProvider": {"triggerCharacters": [".", ":", ":"]},
                "textDocumentSync": {"openClose": True, "change": 1},
            },
            "serverInfo": {"name": "azl-lsp", "version": "0.2.0"},
        },
    }


def handle_hover(msg):
    return {
        "jsonrpc": "2.0",
        "id": msg.get("id"),
        "result": {
            "contents": {
                "kind": "markdown",
                "value": "**AZL**\n\nComponent-based, event-driven language. See docs/language/AZL_LANGUAGE_RULES.md",
            }
        },
    }


def handle_completion(msg):
    items = [{"label": kw, "kind": 14} for kw in AZL_KEYWORDS]
    return {
        "jsonrpc": "2.0",
        "id": msg.get("id"),
        "result": {"isIncomplete": False, "items": items},
    }


def handle_notification(msg):
    method = msg.get("method")
    if method == "initialized":
        return
    if method == "exit":
        return
    if method == "textDocument/didOpen":
        td = msg.get("params", {}).get("textDocument", {})
        uri = td.get("uri", "")
        text = td.get("text", "")
        _DOCS[uri] = text
        write_message(publish_diagnostics(uri, compute_diagnostics(text)))
        return
    if method == "textDocument/didChange":
        params = msg.get("params", {})
        uri = params.get("textDocument", {}).get("uri", "")
        changes = params.get("contentChanges", [])
        if not changes:
            return
        last = changes[-1]
        if "text" in last:
            text = last["text"]
            _DOCS[uri] = text
            write_message(publish_diagnostics(uri, compute_diagnostics(text)))
        return
    if method == "textDocument/didClose":
        uri = msg.get("params", {}).get("textDocument", {}).get("uri", "")
        _DOCS.pop(uri, None)
        write_message(publish_diagnostics(uri, []))
        return


def main():
    while True:
        msg = read_message()
        if msg is None:
            break
        if "method" in msg and "id" in msg:
            method = msg["method"]
            if method == "initialize":
                write_message(handle_initialize(msg))
            elif method == "shutdown":
                write_message({"jsonrpc": "2.0", "id": msg["id"], "result": None})
            elif method == "textDocument/hover":
                write_message(handle_hover(msg))
            elif method == "textDocument/completion":
                write_message(handle_completion(msg))
            else:
                write_message({"jsonrpc": "2.0", "id": msg["id"], "result": None})
        elif "method" in msg:
            if msg["method"] == "exit":
                break
            handle_notification(msg)
        elif "id" in msg:
            write_message({"jsonrpc": "2.0", "id": msg["id"], "result": None})


if __name__ == "__main__":
    main()
