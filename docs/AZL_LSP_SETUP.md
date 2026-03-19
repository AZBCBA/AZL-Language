# AZL Language Server (LSP) Setup

Minimal LSP server for `.azl` files. Provides hover, completion, and **push diagnostics** after `textDocument/didOpen` / `didChange` (heuristic host-syntax hints: `class`, `import`, `def`).

## Usage

**Server command:** `python3 tools/azl_lsp.py`

The server reads JSON-RPC from stdin and writes to stdout. No other setup required.

## VSCode / Cursor

Create `.vscode/settings.json`:

```json
{
  "azl.languageServerPath": "python3",
  "azl.languageServerArgs": ["tools/azl_lsp.py"]
}
```

Or use a generic extension that allows custom LSP server paths.

## Capabilities

| Feature | Status |
|---------|--------|
| Hover | Basic (AZL info) |
| Completion | AZL keywords (component, emit, listen, etc.) |
| Diagnostics | Push via `textDocument/publishDiagnostics` (heuristic) |
| Go to definition | Planned |

## Requirements

- Python 3 (stdlib only; no pip packages)

## CI smoke

```bash
bash scripts/verify_lsp_smoke.sh
```

Sends `initialize`, then `textDocument/didOpen` with host-shaped sample text, and asserts `textDocument/publishDiagnostics` with expected diagnostic codes. Run from `scripts/run_all_tests.sh`.
