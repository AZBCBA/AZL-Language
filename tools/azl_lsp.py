#!/usr/bin/env python3
"""
AZL Language Server Protocol (LSP) over stdin/stdout (JSON-RPC), stdlib only.
Supports: initialize, hover, completion, push diagnostics, textDocument/definition.
"""
from __future__ import annotations

import json
import re
import sys
from typing import Any

AZL_KEYWORDS = [
    "component", "init", "behavior", "memory", "emit", "listen", "for", "then",
    "set", "let", "fn", "function", "return", "if", "else", "while", "for",
    "link", "say", "store", "from", "store", "from",
]

_DOCS: dict[str, str] = {}

RE_COMPONENT_DEF = re.compile(r"\bcomponent\s+(::[\w.]+)\s*\{")
RE_COMPONENT_REF = re.compile(r"::[\w.]+")
RE_EMIT = re.compile(r"\bemit\s+(?:\"([^\"]+)\"|'([^']+)'|(\w+))(?=\s|$)")
RE_LISTEN = re.compile(r"\blisten\s+for\s+(?:\"([^\"]+)\"|'([^']+)'|(\w+))")
RE_FN = re.compile(r"\bfn\s+(\w+)\s*\(")
RE_FUNCTION = re.compile(r"\bfunction\s+(\w+)\s*\(")


def read_message():
    header = sys.stdin.readline()
    if not header:
        return None
    m = re.match(r"Content-Length:\s*(\d+)", header)
    if not m:
        return None
    length = int(m.group(1))
    sys.stdin.readline()
    body = sys.stdin.read(length)
    return json.loads(body) if body else None


def write_message(msg):
    body = json.dumps(msg, separators=(",", ":")).encode("utf-8")
    sys.stdout.buffer.write(f"Content-Length: {len(body)}\r\n\r\n".encode("ascii"))
    sys.stdout.buffer.write(body)
    sys.stdout.buffer.flush()


def _loc(uri: str, line: int, start_col: int, end_col: int) -> dict[str, Any]:
    return {
        "uri": uri,
        "range": {
            "start": {"line": line, "character": start_col},
            "end": {"line": line, "character": end_col},
        },
    }


def scan_component_definitions(text: str, uri: str) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    lines = text.splitlines()
    for i, line in enumerate(lines):
        m = RE_COMPONENT_DEF.search(line)
        if m:
            name = m.group(1)
            sc, ec = m.span(1)
            out[name] = _loc(uri, i, sc, ec)
    return out


def _emit_event_span(m: re.Match) -> tuple[str, int, int]:
    for g in (1, 2, 3):
        if m.group(g):
            return m.group(g), m.start(g), m.end(g)
    return "", -1, -1


def scan_emit_sites(text: str, uri: str) -> list[tuple[str, dict[str, Any]]]:
    sites: list[tuple[str, dict[str, Any]]] = []
    lines = text.splitlines()
    for i, line in enumerate(lines):
        for m in RE_EMIT.finditer(line):
            ev, sc, ec = _emit_event_span(m)
            if ev:
                sites.append((ev, _loc(uri, i, sc, ec)))
    return sites


def scan_listen_sites(text: str, uri: str) -> list[tuple[str, dict[str, Any]]]:
    sites: list[tuple[str, dict[str, Any]]] = []
    lines = text.splitlines()
    for i, line in enumerate(lines):
        for m in RE_LISTEN.finditer(line):
            ev, sc, ec = _emit_event_span(m)
            if ev:
                sites.append((ev, _loc(uri, i, sc, ec)))
    return sites


def scan_fn_definitions(text: str, uri: str) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    lines = text.splitlines()
    for i, line in enumerate(lines):
        for rx in (RE_FN, RE_FUNCTION):
            for m in rx.finditer(line):
                name = m.group(1)
                sc, ec = m.span(1)
                if name not in out:
                    out[name] = _loc(uri, i, sc, ec)
    return out


def component_ref_at(line: str, col: int) -> str | None:
    for m in RE_COMPONENT_REF.finditer(line):
        if m.start() <= col < m.end():
            return m.group(0)
    return None


def emit_event_at(line: str, col: int) -> str | None:
    for m in RE_EMIT.finditer(line):
        ev, sc, ec = _emit_event_span(m)
        if ev and sc <= col < ec:
            return ev
    return None


def listen_event_at(line: str, col: int) -> str | None:
    for m in RE_LISTEN.finditer(line):
        ev, sc, ec = _emit_event_span(m)
        if ev and sc <= col < ec:
            return ev
    return None


def identifier_at(line: str, col: int) -> str | None:
    if not line:
        return None
    if col < 0:
        col = 0
    if col >= len(line):
        col = len(line) - 1
    if not (line[col].isalnum() or line[col] == "_"):
        if col > 0 and (line[col - 1].isalnum() or line[col - 1] == "_"):
            col -= 1
        else:
            return None
    left = col
    while left > 0 and (line[left - 1].isalnum() or line[left - 1] == "_"):
        left -= 1
    right = col + 1
    while right < len(line) and (line[right].isalnum() or line[right] == "_"):
        right += 1
    word = line[left:right]
    return word if word else None


def find_component_definition(name: str) -> dict[str, Any] | None:
    for uri in sorted(_DOCS.keys()):
        cmap = scan_component_definitions(_DOCS[uri], uri)
        if name in cmap:
            return cmap[name]
    return None


def collect_emits_for_event(event: str) -> list[dict[str, Any]]:
    locs: list[dict[str, Any]] = []
    for uri in sorted(_DOCS.keys()):
        for ev, loc in scan_emit_sites(_DOCS[uri], uri):
            if ev == event:
                locs.append(loc)
    locs.sort(key=lambda x: (x["uri"], x["range"]["start"]["line"], x["range"]["start"]["character"]))
    return locs


def collect_listens_for_event(event: str) -> list[dict[str, Any]]:
    locs: list[dict[str, Any]] = []
    for uri in sorted(_DOCS.keys()):
        for ev, loc in scan_listen_sites(_DOCS[uri], uri):
            if ev == event:
                locs.append(loc)
    locs.sort(key=lambda x: (x["uri"], x["range"]["start"]["line"], x["range"]["start"]["character"]))
    return locs


def collect_fn_definition(name: str) -> dict[str, Any] | None:
    for uri in sorted(_DOCS.keys()):
        fmap = scan_fn_definitions(_DOCS[uri], uri)
        if name in fmap:
            return fmap[name]
    return None


def resolve_definition(uri: str, text: str, line: int, col: int) -> list[dict[str, Any]] | None:
    lines = text.splitlines()
    if line < 0 or line >= len(lines):
        return None
    ln = lines[line]

    cref = component_ref_at(ln, col)
    if cref:
        loc = find_component_definition(cref)
        return [loc] if loc else None

    ev_emit = emit_event_at(ln, col)
    if ev_emit:
        locs = collect_listens_for_event(ev_emit)
        return locs if locs else None

    ev_listen = listen_event_at(ln, col)
    if ev_listen:
        locs = collect_emits_for_event(ev_listen)
        return locs if locs else None

    ident = identifier_at(ln, col)
    if ident:
        floc = collect_fn_definition(ident)
        if floc:
            return [floc]

    return None


def compute_diagnostics(text: str) -> list:
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
                "definitionProvider": True,
                "textDocumentSync": {"openClose": True, "change": 1},
            },
            "serverInfo": {"name": "azl-lsp", "version": "0.3.0"},
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


def handle_definition(msg):
    params = msg.get("params", {})
    td = params.get("textDocument", {})
    uri = td.get("uri", "")
    pos = params.get("position", {})
    line = int(pos.get("line", 0))
    col = int(pos.get("character", 0))
    text = _DOCS.get(uri, "")
    locs = resolve_definition(uri, text, line, col)
    result: list[dict[str, Any]] | None = locs
    if locs is not None and len(locs) == 1:
        result = locs[0]
    return {"jsonrpc": "2.0", "id": msg.get("id"), "result": result}


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
            elif method == "textDocument/definition":
                write_message(handle_definition(msg))
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
