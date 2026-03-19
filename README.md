## One-command run (full AZME on AZL)

```bash
export AZL_STRICT=1 AZL_LOG_LEVEL=debug AZL_DAEMON=1
bash scripts/start_azl_native_mode.sh
```

The driver emits `azl.begin` and `system.boot`; all phases advance automatically until ready.

# AZL Language

**AZL** is a unified, component-based, event-driven programming language. It has its own syntax, grammar, and rules — **this is AZL, not Java, not TypeScript.** The runtime target is native AZL execution; see [docs/language/AZL_LANGUAGE_RULES.md](docs/language/AZL_LANGUAGE_RULES.md) and [docs/language/AZL_CURRENT_SPECIFICATION.md](docs/language/AZL_CURRENT_SPECIFICATION.md).

**This repository is the full project.** Work from here: clone from GitHub, make changes, push, and open Pull Requests. Contributions are welcome — see [Contributing](docs/CONTRIBUTING.md) and [GitHub Issues](https://github.com/AZBCBA/AZL-Language/issues).

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
# Optional: provide runtime process launched by native engine (default: C interpreter)
# export AZL_NATIVE_RUNTIME_CMD="bash scripts/azl_c_interpreter_runtime.sh"
bash scripts/start_azl_native_mode.sh
```

When `AZL_NATIVE_ONLY=1`, Python legacy startup paths are blocked by design.

Run native completion gates:

```bash
bash scripts/check_azl_native_gates.sh
bash scripts/enforce_legacy_entrypoint_blocklist.sh
bash scripts/verify_native_runtime_live.sh
```

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

## CI
- `ci.yml`: placeholder/v2 guards, smoke tests, perf smoke, full tests
- `nightly.yml`: sysproxy E2E with logs

## 🎯 Quick Start

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

## 📚 Language Reference

### Basic Syntax

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

## 📖 Standard Library

AZL comes with a comprehensive standard library organized into modules:

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

## 🧪 Testing

Use AZL components to assert behavior via emitted events and stdlib operations. A pure-AZL test harness is under `azl/testing`.

## 📁 Project Structure (native-first AZL)

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
│   └── verify_native_runtime_live.sh
└── azl/testing/                 # Pure AZL tests
```

## 🛠️ Development

### Building (Pure AZL)

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

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Acknowledgments

- Inspired by modern functional programming languages
- Built in AZL; a Rust bootstrap existed historically but is no longer required for core execution
- Standard library design influenced by JavaScript and Python

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/AZBCBA/AZL-Language/issues)
- **Discussions**: [GitHub Discussions](https://github.com/AZBCBA/AZL-Language/discussions)
- **Documentation**: [docs/](docs/)

---

**AZL** - Where clarity meets power in programming. 🚀 