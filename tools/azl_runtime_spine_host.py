#!/usr/bin/env python3
"""
Load combined AZL (AZL_COMBINED_PATH + AZL_ENTRY) and run the Python minimal spine engine.

Interpreter meaning is in ``azl/runtime/interpreter/azl_interpreter.azl``; this process only boots that text
through ``azl_semantic_engine.minimal_runtime`` (C parity via ``tools/azl_interpreter_minimal.c``). It does not
define interpreter semantics — only host I/O and the bootstrap bridge.

Smoke: ``scripts/verify_azl_interpreter_semantic_spine_smoke.sh`` (init); ``…_behavior_smoke.sh`` (deeper interpret
harness). Interpreter slice gate: ``azl/tests/p0_semantic_interpreter_slice.azl`` (F3). Gate G2: ``--semantic-owner`` prints two fixed lines (order is contract): (1) ``AZL_SEMANTIC_SPEC_OWNER`` =
intended AZL semantic spec file path; (2) ``AZL_SPINE_EXEC_OWNER=minimal_runtime_python`` = transitional spine
exec surface (not “Python defines AZL”; default enterprise child can still be C minimal).

Exit codes:
  71 — ERR_AZL_COMBINED_PATH_INVALID
  72 — ERR_AZL_ENTRY_MISSING
  73 — ERR_AZL_BOOTSTRAP_BUNDLE_INVALID (set but not a file)
  74 — ERR_USAGE (unknown CLI arguments)
  2–4 — engine I/O / tokenize (see azl_semantic_engine.minimal_runtime)
  5 — expression / if parse error (minimal contract)
"""

from __future__ import annotations

import os
import sys

# G2 probe: spec anchor (intended meaning-owner .azl) then spine exec carrier (transitional Python minimal_runtime).
_SEMANTIC_PROBE_LINE_SPEC = (
    "AZL_SEMANTIC_SPEC_OWNER=azl/runtime/interpreter/azl_interpreter.azl"
)
_SEMANTIC_PROBE_LINE_SPINE_EXEC = "AZL_SPINE_EXEC_OWNER=minimal_runtime_python"


def main() -> int:
    if len(sys.argv) > 1:
        if sys.argv[1] == "--semantic-owner":
            if len(sys.argv) != 2:
                print(
                    "azl_runtime_spine_host: ERR_USAGE --semantic-owner accepts no further arguments",
                    file=sys.stderr,
                )
                return 74
            print(_SEMANTIC_PROBE_LINE_SPEC, flush=True)
            print(_SEMANTIC_PROBE_LINE_SPINE_EXEC, flush=True)
            return 0
        print(
            "azl_runtime_spine_host: ERR_USAGE unknown arguments (use --semantic-owner only)",
            file=sys.stderr,
        )
        return 74

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
