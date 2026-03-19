# AZL Language Server (LSP) Setup

Minimal LSP server for `.azl` files. Provides hover and completion.

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
| Diagnostics | Planned |
| Go to definition | Planned |

## Requirements

- Python 3 (stdlib only; no pip packages)

## CI smoke

```bash
bash scripts/verify_lsp_smoke.sh
```

Sends one `initialize` request and asserts `hoverProvider` in the response. Run from `scripts/run_all_tests.sh`.
