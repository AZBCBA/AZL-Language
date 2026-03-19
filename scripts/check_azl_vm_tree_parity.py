#!/usr/bin/env python3
"""
Source-level contract: VM runner (vm_run_bytecode_program) must use the same
observable say/emit pipeline as the tree-walker (execute_say / execute_emit).

Both SAY paths evaluate the message expression and prefix say output with 💬 .
Both EMIT paths resolve name/payload then call ::emit_event_resolved (shared dispatch).

Fails fast with stderr if the interpreter source drifts.
"""
from __future__ import annotations

import sys
from pathlib import Path


def err(msg: str) -> None:
    print(msg, file=sys.stderr)


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    path = root / "azl" / "runtime" / "interpreter" / "azl_interpreter.azl"
    if not path.is_file():
        err(f"ERROR: missing interpreter source: {path}")
        return 1
    text = path.read_text(encoding="utf-8")

    def need(label: str, *subs: str) -> None:
        for s in subs:
            if s not in text:
                err(f"ERROR: [{label}] interpreter missing expected fragment:\n  {s!r}")
                raise SystemExit(2)

    need(
        "execute_say",
        "::execute_say = (statement) => {",
        "set ::val = ::evaluate_expression(::message)",
        'say "💬 " + ::val.toString()',
    )
    need(
        "execute_emit",
        "::execute_emit = (statement) => {",
        "return ::emit_event_resolved(::ev_name, ::payload_val)",
    )
    need(
        "emit_event_resolved",
        "::emit_event_resolved = (ev_name, payload_val) => {",
        'say "📡 Emitting event: " + ev_name',
    )

    i_vm = text.find("::vm_run_bytecode_program = (program) => {")
    if i_vm < 0:
        err("ERROR: vm_run_bytecode_program not found")
        return 3
    j = text.find("\n    # Execute listen statement", i_vm)
    if j < 0:
        j = text.find("\n    ::execute_listen", i_vm)
    vm_body = text[i_vm:j] if j > 0 else text[i_vm : i_vm + 2500]

    for frag in (
        'if ::op == "SAY"',
        "set ::val = ::evaluate_expression(::ins.operand)",
        'say "💬 " + ::val.toString()',
        'else if ::op == "EMIT"',
        "set ::evn = ::evaluate_expression(::ins.operand).toString()",
        "::emit_event_resolved(::evn, ::pl)",
    ):
        if frag not in vm_body:
            err(f"ERROR: [vm_run_bytecode_program] missing:\n  {frag!r}")
            return 4

    print("azl-vm-tree-parity-source-ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
