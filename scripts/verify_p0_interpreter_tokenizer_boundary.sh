#!/usr/bin/env bash
# P0 progress: prove the semantic minimal tokenizer can ingest a large prefix of the
# real AZL interpreter source (same lexer as C/Python minimal contract path).
# Does not execute azl_interpreter.azl — only tokenization (toward full P0 load).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
export PYTHONPATH="${ROOT_DIR}/tools${PYTHONPATH:+:${PYTHONPATH}}"

python3 <<'PY'
from pathlib import Path

from azl_semantic_engine.minimal_runtime import MAX_TOKS, tokenize_source

path = Path("azl/runtime/interpreter/azl_interpreter.azl")
raw = path.read_text(encoding="utf-8")
# Large enough to stress lexer; avoid reading entire multi‑MB file in gate.
chunk = raw[:800_000]
toks = tokenize_source(chunk)
if len(toks) < 800:
    raise SystemExit(f"ERROR: expected many tokens from interpreter prefix, got {len(toks)}")
if len(toks) >= MAX_TOKS - 500:
    raise SystemExit(
        f"ERROR: interpreter prefix already nears MAX_TOKS ({len(toks)}); "
        "raise limits in minimal_runtime.py if the gate becomes too tight."
    )
print(f"p0-interpreter-tokenizer-boundary-ok tokens={len(toks)} chunk_chars={len(chunk)}")
PY
