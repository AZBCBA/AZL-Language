# AZL Grammar Reference

The AZL language grammar is **implemented in AZL** in the parser component. This document points to the authoritative sources and summarizes the syntactic structure.

## Authoritative source

- **Parser (tokenizer + AST)**: `azl/core/parser/azl_parser.azl`
  - Token types: `KEYWORD`, `IDENTIFIER`, `LITERAL`, `OPERATOR`, `PUNCTUATION`, `WHITESPACE`, `COMMENT`, `STRING`, `NUMBER`, `BOOLEAN`
  - Keywords, operators, and punctuation are defined in the parser's `init` block.
- **Compiler-side parser**: `azl/core/compiler/azl_parser.azl`
- **Interpreter scanner/parser**: `azl/core/interpreter/azl_scanner.azl`, `azl/core/interpreter/parser.azl`

There is no separate BNF file; the grammar is the AZL parser code. For token and keyword lists, see the parser's `::keywords`, `::operators`, and `::punctuation` in `azl/core/parser/azl_parser.azl`.

## High-level syntax (current implementation)

- **Program**: Zero or more `component ::name { init { } behavior { } memory { } }` blocks.
- **Component**: `component` `::` identifier `{` `init` block `behavior` block `memory` block `}`.
- **Variables**: `set` id `=` expr; `let` id `=` expr. Component scope: `::id`.
- **Functions**: `fn` id `(` params `)` `{` stmts `}`; calls: id `(` args `)`.
- **Control flow**: `if` `(` expr `)` block `else` block; `while` `(` expr `)` block; `for` `(` init `;` cond `;` update `)` block; `loop while` block; `loop for` id `in` expr block; `break`; `continue`.
- **Events**: `emit` id `with` expr; `listen for` string `then` block.
- **Output**: `say` expr.
- **Data**: Numbers, strings, arrays `[ ... ]`, objects `{ ... }`.
- **Operators**: Arithmetic `+ - * / %`; comparison `== != > < >= <=`; logical `and or not`; assignment `= += -= *= /=`; `++`, `--`.

For full, up-to-date semantics and examples, see [AZL_CURRENT_SPECIFICATION.md](AZL_CURRENT_SPECIFICATION.md).
