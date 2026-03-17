# AZL Language Rules and Identity

## This is AZL — Not Java, Not TypeScript

**AZL** is its own programming language. It has its own syntax, semantics, and rules. Do not assume Java, TypeScript, JavaScript, or C semantics when reading or writing AZL code or documentation.

- **File extension**: `.azl`
- **Execution**: Component-based, event-driven; runs via the AZL runtime (Python host `azl_runner.py` + pure AZL interpreter/parser in `azl/`).
- **Grammar and parser**: Defined and implemented in AZL (see `azl/core/parser/azl_parser.azl` and `docs/language/GRAMMAR.md`).

## Core rules

1. **Components** are the top-level unit. Every runnable program is made of `component ::name { init { } behavior { } memory { } }`.
2. **Events** drive behavior: `emit event_name with payload` and `listen for "event_name" then { }`.
3. **Variables**: `set` for assignment, `let` for declare-and-assign. Variables can be component-scoped with `::name`.
4. **Control flow**: `if`/`else`, `while`, `for`, `loop while`, `loop for item in collection`; `break` and `continue` as in the current spec.
5. **Functions**: `fn name(params) { body }`; lexical scoping, `return`.
6. **Output**: `say message` (not `print` from Java/JS).
7. **No implicit Java/TS**: No `class`, `interface`, `export default`, or npm/package semantics unless explicitly added to the AZL spec.

## Where the rules are defined

- **Current behavior**: [AZL_CURRENT_SPECIFICATION.md](AZL_CURRENT_SPECIFICATION.md)
- **Grammar and tokens**: [GRAMMAR.md](GRAMMAR.md) and `azl/core/parser/azl_parser.azl`
- **Standard library**: `docs/stdlib.md` and `azl/stdlib/`

## For contributors

When adding features or fixing bugs:

- Follow the **current** AZL spec; do not introduce Java/TypeScript-only concepts without updating the spec.
- Keep documentation under `docs/` and `docs/language/` in sync with the implementation.
- Use the project's error system; no placeholders or silent fallbacks in production code.
