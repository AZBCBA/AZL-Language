# AZL Language — Core and Documentation

**AZL** is a component-based, event-driven programming language. This directory holds the **pure AZL** runtime (interpreter, parser, compiler, stdlib) and AZL-specific documentation. The language is **AZL**, not Java or TypeScript; it has its own syntax and rules.

## How to run AZL

There is **no** `cargo build` or `Cargo.toml` at the repository root. Use one of these:

- **Python runner (main entry)**  
  From the repo root:
  ```bash
  python3 azl_runner.py path/to/file.azl
  ```
- **CLI script**  
  ```bash
  ./scripts/azl run path/to/file.azl
  ```
- **Combined build (compiler + interpreter)**  
  ```bash
  python3 scripts/run_combined_azl.py ...
  ```
- **JS dev harness**  
  ```bash
  node scripts/azl_runtime.js test_core.azl ::test.core
  ```

See the root [README.md](../../README.md) and [OPERATIONS.md](../../OPERATIONS.md) for the full runbook.

## Layout of `azl/`

- **`runtime/interpreter/`** — AZL interpreter (`azl_interpreter.azl`).
- **`core/parser/`** — Parser written in AZL (`azl_parser.azl`): tokenizer, keywords, operators, AST.
- **`core/compiler/`** — Compiler pipeline (parser, bytecode, optimizers).
- **`core/error_system.azl`** — Error handling.
- **`system/azl_system_interface.azl`** — System interface (virtual OS, sysproxy).
- **`stdlib/`** — Standard library (core, etc.).
- **`security/`**, **`bootstrap/`** — Capabilities and bootstrap.

## Documentation

- **Current language spec**: [docs/language/AZL_CURRENT_SPECIFICATION.md](../../docs/language/AZL_CURRENT_SPECIFICATION.md)
- **AZL rules (not Java/TS)**: [docs/language/AZL_LANGUAGE_RULES.md](../../docs/language/AZL_LANGUAGE_RULES.md)
- **Grammar**: [docs/language/GRAMMAR.md](../../docs/language/GRAMMAR.md)
- **Architecture**: [AZL_LANGUAGE_ARCHITECTURE.md](AZL_LANGUAGE_ARCHITECTURE.md) and root [docs/ARCHITECTURE_OVERVIEW.md](../../docs/ARCHITECTURE_OVERVIEW.md)

The file [AZL_LANGUAGE_SPECIFICATION.md](AZL_LANGUAGE_SPECIFICATION.md) in this directory describes a broader/v1.0-style vision; the **implemented** behavior is defined in `docs/language/AZL_CURRENT_SPECIFICATION.md`.
