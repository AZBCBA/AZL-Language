# Contributing to AZL Language

Thank you for contributing to **AZL** — the component-based, event-driven programming language. This project is **AZL language**, not Java, TypeScript, or any other language. Please follow AZL's rules and architecture.

## Repository layout (Python + pure AZL)

- **`azl_runner.py`** — Main entry: Python host that runs `.azl` files (component engine, expression evaluation, init/behavior execution).
- **`azl/`** — Pure AZL runtime: interpreter, parser, compiler, stdlib, error system, security. Grammar and parsing live in AZL (e.g. `azl/core/parser/azl_parser.azl`).
- **`scripts/azl`** — CLI to run AZL (e.g. `scripts/azl run <file.azl>`).
- **`scripts/run_combined_azl.py`** — Builds and runs combined AZL (compiler + interpreter).
- **`docs/`** — All project documentation. Language spec: `docs/language/AZL_CURRENT_SPECIFICATION.md` and `docs/language/AZL_LANGUAGE_RULES.md`.

There is **no** `src/lib.rs` or `Cargo.toml` at repo root. The runtime is **Python + pure AZL**.

## Active work areas (coordinate before changing)

- **`azl_runner.py`** — Component loading, event dispatch, `eval_expr`, `parse_azl_list`, init/behavior execution.
- **`azl/core/parser/azl_parser.azl`** — Token types, keywords, operators, punctuation, `tokenize`, `parse_azl_code`, AST.
- **`azl/core/compiler/`** — Compiler pipeline (parser, bytecode, optimizers).
- **`azl/runtime/interpreter/`** — AZL interpreter.
- **`azl/core/error_system.azl`** — Error handling.
- **`docs/language/AZL_CURRENT_SPECIFICATION.md`** — Single source of truth for **current** AZL syntax and behavior.

Please avoid large, conflicting edits in these areas without coordination. Add tests and docs freely; for runtime/parser/compiler changes, discuss in issues or PRs.

## Standards

- **No placeholders or mocks** in production code.
- **Strict mode** must pass before merging (see `OPERATIONS.md` and `docs/STRICT_MODE_AND_FEATURE_FLAGS.md`).
- **Error system**: Use the project's error handling; no silent fallbacks in production paths.
- **AZL syntax and rules**: Follow `docs/language/AZL_CURRENT_SPECIFICATION.md` and `docs/language/AZL_LANGUAGE_RULES.md`. Do not assume Java/TypeScript semantics.

## Code style

- Descriptive names; clear control flow; guard clauses.
- **Indentation**: 4 spaces (Python and AZL).
- Tests and documentation required for new features and behavior changes.

## Process

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/your-feature`).
3. Make changes; update specs/docs under `docs/` when changing behavior.
4. Add or adjust tests (pure AZL tests under `azl/testing/`, Python tests as appropriate).
5. Ensure the project runs (e.g. `python3 azl_runner.py <file.azl>` or `scripts/azl run <file.azl>`).
6. Push and open a Pull Request. Keep PRs small and reviewable.

## Documentation

- **Current language spec**: `docs/language/AZL_CURRENT_SPECIFICATION.md`
- **AZL rules and identity**: `docs/language/AZL_LANGUAGE_RULES.md`
- **Grammar reference**: `docs/language/GRAMMAR.md`
- **Architecture**: `docs/ARCHITECTURE_OVERVIEW.md`, `azl/docs/AZL_LANGUAGE_ARCHITECTURE.md`

When you change AZL syntax or runtime behavior, update the spec and grammar docs so the repo stays accurate for contributors and users.
