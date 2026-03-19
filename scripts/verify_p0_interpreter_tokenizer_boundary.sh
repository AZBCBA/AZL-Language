#!/usr/bin/env bash
# P0 progress (gate H):
#   1) Semantic minimal tokenizer ingests the real interpreter source (same lexer as C/Python minimal).
#   2) Brace tokens { } balance on the full file token stream (structural sanity; strings are opaque tokens).
# Does not execute azl_interpreter.azl.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
export PYTHONPATH="${ROOT_DIR}/tools${PYTHONPATH:+:${PYTHONPATH}}"

python3 <<'PY'
from pathlib import Path

from azl_semantic_engine.minimal_runtime import MAX_TOKS, tokenize_source

path = Path("azl/runtime/interpreter/azl_interpreter.azl")
raw = path.read_text(encoding="utf-8")
if "component ::azl.interpreter" not in raw:
    raise SystemExit("ERROR: azl_interpreter.azl missing expected component ::azl.interpreter anchor")

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

full_toks = tokenize_source(raw)
ob = sum(1 for t in full_toks if t == "{")
cb = sum(1 for t in full_toks if t == "}")
if ob != cb:
    raise SystemExit(f"ERROR: brace token mismatch in azl_interpreter.azl: {{={ob} }}={cb}")
print(f"p0-interpreter-brace-balance-ok tokens={len(full_toks)} open_brace={ob}")
PY
