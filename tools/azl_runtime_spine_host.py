#!/usr/bin/env python3
"""
Semantic runtime spine host (integration shell).

The decided semantic core is azl/runtime/interpreter/azl_interpreter.azl — implemented in AZL.
Executing it requires an engine that runs AZL with full language semantics. The default
enterprise child remains tools/azl_interpreter_minimal.c (narrow subset).

This process is the stable hook for AZL_RUNTIME_SPINE=azl_interpreter|semantic. Until a
self-hosting or embedded executor ships in-tree, we exit with ERR_AZL_SEMANTIC_HOST_UNIMPLEMENTED
so deployments never confuse C minimal with the full interpreter.

Exit codes:
  71 — ERR_AZL_COMBINED_PATH_INVALID
  72 — ERR_AZL_ENTRY_MISSING
  78 — ERR_AZL_SEMANTIC_HOST_UNIMPLEMENTED
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

    print(
        "azl_runtime_spine_host: ERR_AZL_SEMANTIC_HOST_UNIMPLEMENTED",
        file=sys.stderr,
    )
    print(
        "  Full semantics live in azl/runtime/interpreter/azl_interpreter.azl (AZL-in-AZL).",
        file=sys.stderr,
    )
    print(
        "  This repository does not yet ship an in-tree executor that runs that source as code.",
        file=sys.stderr,
    )
    print(
        "  Default spine: unset AZL_RUNTIME_SPINE or AZL_RUNTIME_SPINE=c_minimal "
        "(see scripts/azl_resolve_native_runtime_cmd.sh).",
        file=sys.stderr,
    )
    print(
        "  Track: implement or embed the executor behind this hook; then replace this stub.",
        file=sys.stderr,
    )
    return 78


if __name__ == "__main__":
    raise SystemExit(main())
