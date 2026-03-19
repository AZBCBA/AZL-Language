#!/usr/bin/env python3
"""
Semantic runtime spine host: runs the Python AZL subset engine (parity with
tools/azl_interpreter_minimal.c) on AZL_COMBINED_PATH + AZL_ENTRY.

Full AZL-in-AZL self-host (azl/runtime/interpreter/azl_interpreter.azl as source)
remains a widening track; this host is the production integration point for
native mode when AZL_RUNTIME_SPINE=azl_interpreter|semantic.

P0 widening: `azl/tests/p0_semantic_interpreter_slice.azl` is parity-gated vs C
(gate F3 in check_azl_native_gates.sh). Run: `bash scripts/run_semantic_interpreter_slice.sh`.

Exit codes:
  71 — ERR_AZL_COMBINED_PATH_INVALID
  72 — ERR_AZL_ENTRY_MISSING
  73 — ERR_AZL_BOOTSTRAP_BUNDLE_INVALID (set but not a file)
  2–4 — engine I/O / tokenize (see azl_semantic_engine.minimal_runtime)
  5 — expression / if parse error (minimal contract)
"""

from __future__ import annotations

import os
import sys


def main() -> int:
    combined = (os.environ.get("AZL_COMBINED_PATH") or "").strip()
    entry = (os.environ.get("AZL_ENTRY") or "").strip()
    bundle = (os.environ.get("AZL_BOOTSTRAP_BUNDLE") or "").strip()

    if not combined or not os.path.isfile(combined):
        print(
            "azl_runtime_spine_host: ERR_AZL_COMBINED_PATH_INVALID "
            "(AZL_COMBINED_PATH must name an existing file)",
            file=sys.stderr,
        )
        return 71
    if not entry:
        print(
            "azl_runtime_spine_host: ERR_AZL_ENTRY_MISSING (AZL_ENTRY is required)",
            file=sys.stderr,
        )
        return 72

    if bundle and not os.path.isfile(bundle):
        print(
            "azl_runtime_spine_host: ERR_AZL_BOOTSTRAP_BUNDLE_INVALID "
            f"(not a file: {bundle})",
            file=sys.stderr,
        )
        return 73

    tools_dir = os.path.dirname(os.path.abspath(__file__))
    if tools_dir not in sys.path:
        sys.path.insert(0, tools_dir)

    from azl_semantic_engine.minimal_runtime import run_file

    daemon = "AZL_INTERPRETER_DAEMON" in os.environ
    return run_file(combined, entry, daemon=daemon)


if __name__ == "__main__":
    raise SystemExit(main())
