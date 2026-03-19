"""
Python semantic runtime — phase 1: execution parity with tools/azl_interpreter_minimal.c
for the enterprise subset (say/set/emit/link, component init/behavior, listen for quoted events).

Full self-host of azl/runtime/interpreter/azl_interpreter.azl is a separate expansion track.
"""

from azl_semantic_engine.minimal_runtime import MinimalAZLRuntime, run_file

__all__ = ["MinimalAZLRuntime", "run_file"]
