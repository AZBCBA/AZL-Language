# AZL Language

AZL is a **component–event** language: programs are built from named `component` blocks with `init` and `behavior` sections, asynchronous coordination uses `emit` / `listen`, and failures are intended to flow through an explicit error system rather than silent degradation. Grammar, parser, interpreter, stdlib, and much of the tooling live as **AZL source** under `azl/`. Authoritative syntax and behavior are [AZL_CURRENT_SPECIFICATION.md](docs/language/AZL_CURRENT_SPECIFICATION.md) and [AZL_LANGUAGE_RULES.md](docs/language/AZL_LANGUAGE_RULES.md).

**Native runtime (today):** the HTTP supervisor in `tools/azl_native_engine.c` forks a child that runs a **concatenated** `.azl` bundle. That child is either the **minimal C interpreter** or a **Python runtime** with the same subset (`AZL_RUNTIME_SPINE`); full semantics are specified in `azl/runtime/interpreter/azl_interpreter.azl`, and making that path the default enterprise semantic owner is **ongoing** ([RUNTIME_SPINE_DECISION.md](docs/RUNTIME_SPINE_DECISION.md), [PROJECT_COMPLETION_ROADMAP.md](docs/PROJECT_COMPLETION_ROADMAP.md)).

**Broader library surface:** LHA3-style memory, quantum- and topology-flavored **software** modules, neural orchestration, optional Torch FFI (`AZL_ENABLE_TORCH_FFI`), and HTTP bridges for LLMs. Most of this is **not** exercised by the default native child; boundaries are documented in [AZL_GPU_NEURAL_QUANTUM_INVENTORY.md](docs/AZL_GPU_NEURAL_QUANTUM_INVENTORY.md) and [DEEP_AUDIT_QUANTUM_MEMORY_PHYSICS.md](docs/DEEP_AUDIT_QUANTUM_MEMORY_PHYSICS.md). Native LLM access is designed around an **Ollama-compatible HTTP proxy**; in-process GGUF is **not** implemented and is reported via `GET /api/llm/capabilities`.

**Documentation canon (shipped work + full doc map):** [docs/AZL_DOCUMENTATION_CANON.md](docs/AZL_DOCUMENTATION_CANON.md) · Index: [docs/README.md](docs/README.md) · **Where files belong (root vs `.azl/` vs trees):** [docs/REPOSITORY_LAYOUT.md](docs/REPOSITORY_LAYOUT.md) · **Local `.azl/` subfolders:** [docs/LOCAL_WORKSPACE_LAYOUT.md](docs/LOCAL_WORKSPACE_LAYOUT.md)

Canonical repo: **https://github.com/AZBCBA/AZL-Language** — [Contributing](docs/CONTRIBUTING.md) · [Issues](https://github.com/AZBCBA/AZL-Language/issues)

## One-command native startup

```bash
export AZL_STRICT=1 AZL_LOG_LEVEL=debug AZL_DAEMON=1
bash scripts/start_azl_native_mode.sh
```

The driver emits `azl.begin` and `system.boot`; phases advance until the stack reports ready.

## Getting Started
- Native startup:
  - `bash scripts/start_azl_native_mode.sh`
- Sysproxy + daemon bridge test:
  - `AZL_REQUIRE_API_TOKEN=true AZL_API_TOKEN=your-token bash scripts/test_sysproxy_setup.sh`

See OPERATIONS.md for the full runbook.

## Native-Only Deployment Mode

To enforce AZL-native deployment direction (no Python/JS bootstrap paths), use:

```bash
# Optional: provide your own native executor command
# export AZL_NATIVE_EXEC_CMD=/path/to/azl-native-engine
# Optional: runtime child — unset uses AZL_RUNTIME_SPINE (default c_minimal → C interpreter)
# export AZL_RUNTIME_SPINE=azl_interpreter   # reserved semantic hook (see docs/PROJECT_COMPLETION_ROADMAP.md)
# export AZL_NATIVE_RUNTIME_CMD="bash scripts/azl_c_interpreter_runtime.sh"
bash scripts/start_azl_native_mode.sh
```

When `AZL_NATIVE_ONLY=1`, Python legacy startup paths are blocked by design.

Run native completion gates (`check_azl_native_gates.sh` runs **gate 0** — `self_check_release_helpers.sh` for release scripts + `release/native/manifest.json` via **`jq`** — before A–H; needs **`rg`** + **`jq`**):

```bash
bash scripts/check_azl_native_gates.sh
bash scripts/enforce_legacy_entrypoint_blocklist.sh
bash scripts/verify_native_runtime_live.sh
# Enterprise combined HTTP (also runs inside scripts/run_tests.sh):
bash scripts/verify_enterprise_native_http_live.sh
```

**Strength bar (gates + live capabilities in one command):** `bash scripts/verify_azl_strength_bar.sh` — see [docs/AZL_DOCUMENTATION_CANON.md](docs/AZL_DOCUMENTATION_CANON.md) §1.7.

**Full verification (release order + all tests):** `bash scripts/run_full_repo_verification.sh` — set `RUN_OPTIONAL_BENCHES=0` to skip LLM benches.

Release profile details: `RELEASE_READY.md` and `release/native/manifest.json`.

## Installation (clone and run)

The canonical source is GitHub. Clone and run:

```bash
git clone https://github.com/AZBCBA/AZL-Language.git
cd AZL-Language
bash scripts/start_azl_native_mode.sh
```

See [OPERATIONS.md](OPERATIONS.md) for the full runbook.

**Contributing:** Fork the repo, make changes on a branch, then open a [Pull Request](https://github.com/AZBCBA/AZL-Language/pulls). See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

## Run tests

```bash
./scripts/run_tests.sh
```

Run full native validation: `./scripts/run_all_tests.sh`.

## LLM and chat benchmarks (optional)

- **Suite (native + optional enterprise):** `bash scripts/run_product_benchmark_suite.sh` — same as below, plus `/v1/chat` when `AZL_API_TOKEN` is set.
- **C engine + Ollama:** `bash scripts/run_native_engine_llm_bench.sh` (starts a fresh `azl-native-engine`; requires `ollama serve` and a pulled model, e.g. `llama3.2:1b`).
- **Three-way comparison** (Python / curl / C proxy): `bash scripts/benchmark_llm_ollama.sh` — set `AZL_BENCH_PORT` and `AZL_BENCH_TOKEN` if the engine is already running.
- **Enterprise HTTP chat:** `AZL_API_TOKEN=… bash scripts/benchmark_enterprise_v1_chat.sh` with the combined daemon on `AZL_ENTERPRISE_PORT` (default `8080`).

See [docs/LLM_INFRASTRUCTURE_AUDIT.md](docs/LLM_INFRASTRUCTURE_AUDIT.md).

**Shipped vs open milestones:** [docs/AZL_DOCUMENTATION_CANON.md](docs/AZL_DOCUMENTATION_CANON.md) · **HTTP profiles (C vs enterprise):** [docs/CANONICAL_HTTP_PROFILE.md](docs/CANONICAL_HTTP_PROFILE.md) · **P0 semantic slice:** `bash scripts/run_semantic_interpreter_slice.sh`

## CI
- **`test-and-deploy.yml`**: **Canonical** PR/main CI/CD — repo guards (`run_full`, `audit_live`, stale v2), **`run_all_tests.sh`**, **`perf_smoke`**, AZME E2E job, native engine matrix, benchmarks, C coverage, Docker → GHCR, optional staging — see [docs/CI_CD_PIPELINE.md](docs/CI_CD_PIPELINE.md)
- **`main` branch protection:** **eight** required jobs — [docs/GITHUB_BRANCH_PROTECTION.md](docs/GITHUB_BRANCH_PROTECTION.md), **`release/ci/required_github_status_checks.json`**. Local: **`make branch-protection-contract`**; maintainers: **`make branch-protection-verify`** / **`make branch-protection-apply`**.
- `ci.yml` / `native-release-gates.yml`: **`workflow_dispatch` only** (legacy / focused reruns)
- `azl-ci.yml`: all branches — same guards + **`run_all_tests.sh`** + **`run_examples.sh`**
- `nightly.yml`: **`check_azl_native_gates.sh`** + sysproxy E2E + logs

**Completion (precise wording):** [docs/PROJECT_COMPLETION_STATEMENT.md](docs/PROJECT_COMPLETION_STATEMENT.md) — Tier **A** = `make native-release-profile-complete` / `bash scripts/verify_native_release_profile_complete.sh`. Tier **B** = full roadmap ([docs/PROJECT_COMPLETION_ROADMAP.md](docs/PROJECT_COMPLETION_ROADMAP.md)).

Documentation index: [docs/README.md](docs/README.md).

## Syntax samples

### Hello World

```azl
component ::hello {
  init {
    say "Hello, AZL!"
  }
}
```

### Variables and Functions

```azl
component ::greet {
  init {
    set name = "AZL"
    say greet(name)
  }
  fn greet(name) {
    return "Hello, " + name + "!"
  }
}
```

### Components and Events

```azl
component ::counter {
  init {
    set ::count = 0
    emit "tick"
  }
  behavior {
    listen for "tick" then {
      set ::count = ::count + 1
      say "Count: " + ::count
    }
  }
}
```

## Language reference

### Basic syntax

#### Variables
```azl
set x = 42
set name = "AZL"
set is_active = true
set items = [1, 2, 3, 4, 5]
```

#### Functions
```azl
fn add(a, b) {
  return a + b
}
set result = add(5, 3)
```

#### Control Flow
```azl
if x > 10 {
  say "x is greater than 10"
} else {
  say "x is 10 or less"
}

set i = 0
while i < 5 {
  say "Count: " + i
  set i = i + 1
}

for j from 0 to 4 {
  say "For count: " + j
}
```

#### Arrays
```azl
set arr = [1, 2, 3, 4, 5]
set first = arr[0]
set last = arr[arr.length - 1]
arr.push(6)
arr[0] = 10
```

### Components and Events (current runtime)

```azl
component ::demo.app {
  init {
    say "hello";
    emit test.event with { msg: "ok" };
  }
  behavior {
    listen for "test.event" then { say "received"; }
  }
}
```

### Error Handling

Use the error system: `emit "error" with { message: "..." }` and `listen for "error" then { }`. See `azl/core/error_system.azl`.

## Standard library

The tree under `azl/stdlib/` and related core modules provides shared utilities. Examples (non-exhaustive):

### Core Array Module (`stdlib/core/array.azl`)

Functional programming utilities for array manipulation:

- `map(array, func)` - Transform array elements
- `filter(array, predicate)` - Filter array elements
- `reduce(array, func, initial)` - Reduce array to single value
- `length(array)` - Get array length
- `push(array, item)` - Add item to array
- `slice(array, start, end)` - Extract portion of array
- `flatten(array)` - Flatten nested arrays
- `find(array, predicate)` - Find first matching element
- `find_index(array, predicate)` - Find index of first match
- `includes(array, value)` - Check if array contains value

### String Module (`stdlib/string.azl`)

String manipulation and processing:

- `split(str, sep)` - Split string by separator
- `join(array, sep)` - Join array into string
- `to_upper(str)` - Convert to uppercase
- `to_lower(str)` - Convert to lowercase
- `trim(str)` - Remove whitespace
- `replace(str, old, new)` - Replace substrings
- `starts_with(str, prefix)` - Check prefix
- `ends_with(str, suffix)` - Check suffix
- `contains(str, substr)` - Check substring
- `index_of(str, substr)` - Find substring index
- `repeat(str, count)` - Repeat string

### Math Module (`stdlib/math.azl`)

Mathematical functions and utilities:

- `abs(x)` - Absolute value
- `min(a, b)`, `max(a, b)` - Min/max values
- `floor(x)`, `ceil(x)`, `round(x)` - Rounding functions
- `pow(base, exponent)` - Exponentiation
- `sqrt(x)` - Square root
- `random()`, `random_range(min, max)` - Random numbers
- `clamp(value, min, max)` - Clamp value to range
- `lerp(start, end, t)` - Linear interpolation
- `sign(x)` - Sign function
- `is_even(n)`, `is_odd(n)` - Number properties
- `gcd(a, b)`, `lcm(a, b)` - Greatest common divisor/least common multiple

### I/O Module (`stdlib/io.azl`)

File and directory operations:

- `read_file(path)` - Read file contents
- `write_file(path, content)` - Write to file
- `append_file(path, content)` - Append to file
- `file_exists(path)` - Check file existence
- `delete_file(path)` - Delete file
- `list_directory(path)` - List directory contents
- `create_directory(path)` - Create directory
- `delete_directory(path)` - Delete directory

## Testing

Use AZL components to assert behavior via emitted events and stdlib operations. A pure-AZL test harness lives under `azl/testing`. CI and release gates use `scripts/run_tests.sh` and `scripts/run_all_tests.sh`.

## Repository layout (native-first)

```
azl-language/
├── azl/
│   ├── core/
│   │   ├── parser/azl_parser.azl   # Grammar & parser (written in AZL)
│   │   ├── compiler/              # Compiler pipeline
│   │   └── error_system.azl
│   ├── runtime/interpreter/azl_interpreter.azl
│   ├── system/azl_system_interface.azl
│   ├── stdlib/core/azl_stdlib.azl
│   └── docs/                     # AZL-specific docs
├── docs/
│   ├── language/
│   │   ├── AZL_CURRENT_SPECIFICATION.md   # Current syntax & behavior
│   │   ├── AZL_LANGUAGE_RULES.md          # AZL identity & rules
│   │   └── GRAMMAR.md                     # Grammar reference
│   ├── ARCHITECTURE_OVERVIEW.md
│   ├── STRICT_MODE_AND_FEATURE_FLAGS.md
│   ├── stdlib.md
│   └── VIRTUAL_OS_API.md
├── scripts/
│   ├── start_azl_native_mode.sh  # Canonical native startup
│   ├── run_enterprise_daemon.sh  # Canonical combined component launcher
│   ├── verify_native_runtime_live.sh
│   └── verify_enterprise_native_http_live.sh
└── azl/testing/                 # Pure AZL tests
```

## Development

### Building (pure AZL)

See `build_azl.azl` for the virtual build pipeline using the system interface’s syscalls.

### Contributing

AZL is its own language; follow [docs/language/AZL_LANGUAGE_RULES.md](docs/language/AZL_LANGUAGE_RULES.md) and the [Contributing guide](docs/CONTRIBUTING.md). Summary:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Make changes; update `docs/` when changing behavior
4. Push and open a Pull Request

### Code Style

- Use 4 spaces for indentation
- Descriptive names; guard edge cases; deterministic behavior
- Write tests for new features

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

AZL draws ideas from event-driven and functional idioms familiar from other ecosystems; the **language semantics are AZL-specific** and must be read from the spec, not assumed from JavaScript or Python. A historical Rust bootstrap path is deprecated for core execution.

## Support

- [GitHub Issues](https://github.com/AZBCBA/AZL-Language/issues)
- [GitHub Discussions](https://github.com/AZBCBA/AZL-Language/discussions)
- [Documentation index](docs/README.md)