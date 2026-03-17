# AZL Language — Documentation

This folder contains all project documentation. **AZL** is its own language (not Java, not TypeScript); see the language docs below for rules and syntax.

## Language (AZL syntax, rules, grammar)

| Document | Description |
|----------|-------------|
| [language/AZL_CURRENT_SPECIFICATION.md](language/AZL_CURRENT_SPECIFICATION.md) | **Current** AZL implementation: components, events, control flow, types, operators |
| [language/AZL_LANGUAGE_RULES.md](language/AZL_LANGUAGE_RULES.md) | AZL identity and rules (not Java/TS) |
| [language/GRAMMAR.md](language/GRAMMAR.md) | Grammar reference; points to parser in `azl/core/parser/azl_parser.azl` |

## Architecture and operations

| Document | Description |
|----------|-------------|
| [STATUS.md](STATUS.md) | Project status: what works, deprecated, open work |
| [ARCHITECTURE_OVERVIEW.md](ARCHITECTURE_OVERVIEW.md) | High-level architecture |
| [STRICT_MODE_AND_FEATURE_FLAGS.md](STRICT_MODE_AND_FEATURE_FLAGS.md) | Strict mode and feature flags |
| [VIRTUAL_OS_API.md](VIRTUAL_OS_API.md) | Virtual OS and syscalls |
| [ERROR_SYSTEM.md](ERROR_SYSTEM.md) | Error handling |
| [stdlib.md](stdlib.md) | Standard library |

## Contributing and CI

| Document | Description |
|----------|-------------|
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute (Python + AZL; no Rust at root) |
| [CI_CD_PIPELINE.md](CI_CD_PIPELINE.md) | CI/CD |
| [OBSERVABILITY.md](OBSERVABILITY.md) | Observability |

## Other

| Document | Description |
|----------|-------------|
| [advanced_features.md](advanced_features.md) | **Future / NOT IMPLEMENTED** — theoretical features only |
| [CODEGEN.md](CODEGEN.md) | Code generation |
| [AZME_PRODUCTION_RUNBOOK.md](AZME_PRODUCTION_RUNBOOK.md) | AZME production runbook |

Root [OPERATIONS.md](../OPERATIONS.md) is the main runbook for running and testing AZL.
