# AZL Language Server (LSP) Setup

Minimal LSP server for `.azl` files (Python stdlib only): hover, completion, push diagnostics, and **go to definition**.

## Usage

**Server command:** `python3 tools/azl_lsp.py`

The server reads JSON-RPC from stdin and writes to stdout. No other setup required.

## VSCode / Cursor

Point your LSP client at the server (or use a generic “stdio language server” extension):

```json
{
  "azl.languageServerPath": "python3",
  "azl.languageServerArgs": ["${workspaceFolder}/tools/azl_lsp.py"]
}
```

Extensions such as **Language Server Protocol** / **vscode-languageservers**-style wrappers work as long as they spawn the command above with the workspace folder as cwd (so `${workspaceFolder}` resolves).

## Capabilities

| Feature | Status |
|---------|--------|
| Hover | Basic (AZL overview) |
| Completion | AZL keywords (`component`, `emit`, `listen`, …) |
| Diagnostics | Push (`textDocument/publishDiagnostics`) — host-syntax hints (`class`, `import`, `def`) |
| **Go to definition** | `textDocument/definition` (see below) |

### Go to definition (implemented)

Heuristic, **same-line–centric** resolution (no full AST); good for large trees and `::` navigation.

| You click on | Result |
|----------------|--------|
| `::foo.bar` / `::foo.bar.baz` (e.g. after `link`, `to`, or inline) | `component ::foo.bar…` **name** range in any **open** document |
| Event string in `listen for "event.name"` | All `emit "event.name"` / `emit event.name` sites in **open** documents |
| Event string or name in `emit "event.name"` / `emit name` | All matching `listen for …` sites in **open** documents |
| Identifier for a call (e.g. `my_fn(`) | First `fn my_fn(` / `function my_fn(` definition in **open** documents |

**Limits:** Only buffers registered via `textDocument/didOpen` are searched (typical for LSP). `LocationLink` / multi-root workspace indexing are not implemented yet. Unquoted `listen for word` and `emit word` are supported on the **same line** as the keyword.

**Fixture / tests:** `azl/tests/lsp_definition_resolution.azl` — run `bash scripts/test_lsp_jump_to_def.sh`.

## Requirements

- Python 3 (stdlib only; no pip packages)

## CI

```bash
bash scripts/verify_lsp_smoke.sh
bash scripts/test_lsp_jump_to_def.sh
```

Both run from `scripts/run_all_tests.sh`. Smoke checks `initialize` + diagnostics + `definitionProvider`; jump-to-def test drives `textDocument/definition` on the fixture file.
