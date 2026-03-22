#!/usr/bin/env python3
"""
Semantic runtime spine host: runs the Python AZL subset engine (parity with
tools/azl_interpreter_minimal.c) on AZL_COMBINED_PATH + AZL_ENTRY.

Full AZL-in-AZL self-host (azl/runtime/interpreter/azl_interpreter.azl as source)
remains a widening track; this host is the production integration point for
native mode when AZL_RUNTIME_SPINE=azl_interpreter|semantic.

P0 widening: `azl/tests/p0_semantic_interpreter_slice.azl` is parity-gated vs C
(gate F3 in check_azl_native_gates.sh). Run: `bash scripts/run_semantic_interpreter_slice.sh`.

P0.1b (release): `scripts/verify_azl_interpreter_semantic_spine_smoke.sh` concatenates
`azl/tests/stubs/azl_security_for_interpreter_spine.azl` + `azl/runtime/interpreter/azl_interpreter.azl`,
sets AZL_COMBINED_PATH and AZL_ENTRY=azl.interpreter, and asserts clean `init` (see docs/ERROR_SYSTEM.md).

P0.1c (release): `scripts/verify_azl_interpreter_semantic_spine_behavior_smoke.sh` adds
`azl/tests/harness/azl_interpreter_semantic_spine_behavior_entry.azl`, uses AZL_ENTRY=azl.spine.behavior.entry,
and asserts seven interpret passes + execute_complete + >=4 in-file (cache hit) lines (two duplicate-code pairs) + multi-line embedded say depth + duplicate AZL_S6_ONLY literal pass (ERROR_SYSTEM.md exits 548–561).

Exit codes:
  71 — ERR_AZL_COMBINED_PATH_INVALID
  72 — ERR_AZL_ENTRY_MISSING
  73 — ERR_AZL_BOOTSTRAP_BUNDLE_INVALID (set but not a file)
  74 — ERR_USAGE (unknown CLI arguments)
  2–4 — engine I/O / tokenize (see azl_semantic_engine.minimal_runtime)
  5 — expression / if parse error (minimal contract)

CLI:
  --semantic-owner — print one stdout line ``AZL_SEMANTIC_OWNER=minimal_runtime_python`` and exit 0.
    Used by ``scripts/verify_semantic_spine_owner_contract.sh`` (native gate G2). Tier B P0.1: the
    semantic spine must not silently become C minimal as execution owner.
"""

from __future__ import annotations

import os
import sys

_SEMANTIC_OWNER_LINE = "AZL_SEMANTIC_OWNER=minimal_runtime_python"


def main() -> int:
    if len(sys.argv) > 1:
        if sys.argv[1] == "--semantic-owner":
            if len(sys.argv) != 2:
                print(
                    "azl_runtime_spine_host: ERR_USAGE --semantic-owner accepts no further arguments",
                    file=sys.stderr,
                )
                return 74
            print(_SEMANTIC_OWNER_LINE, flush=True)
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
