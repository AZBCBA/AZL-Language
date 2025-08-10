# AZL Language - Current Implementation Specification

## Overview
AZL is a component-based, event-driven programming language. This specification describes the actual current implementation. Modern constructs (let, fn, if, loops) are part of the core language.

## Core Language Features (Implemented)

### Components
```azl
component ::component_name {
  init { }
  behavior { }
  memory { }
}
```

### Variables and Assignment
- `set variable_name = value` — Assign values
- `let variable_name = value` — Declare and assign
- Variables persist between events

### Event System
- `emit event_name with payload`
- `listen for "event_name"`

### Output
- `say message`

### Control Flow
- `if/else`
- `loop while {}` and `loop for item in collection {}`
- `while {}`
- `for init; condition; update {}`
- `continue`, `break`

### Functions
- `fn name(params) { body }`
- Calls with arguments, return statements, lexical scoping

## Data Types
- Numbers, Strings, Arrays, Objects

## Operators
- Arithmetic: `+ - * /` (division by zero protection)
- Comparison: `== != > < >= <=`
- Logical: `and or not`

## Event Flow
1. `init` runs once
2. Event handlers in `behavior` react to emissions
3. Persistent state in `memory`

## Runtime and Integration
- Single interpreter component provides parsing and execution.
- Error handling: division by zero, unknown function, syntax and runtime errors.
- FFI: file system, HTTP, math via `::azl.system_interface` and `::ffi.*`.
- System interface: virtual OS with optional sysproxy bridge for host calls.

## Examples
```azl
component ::counter {
  init { set ::count = 0; say "Counter initialized" }
  behavior {
    listen for "increment" { set ::count = ::count + 1; say "Count: " + ::count }
    listen for "calculate" {
      let x = 10; let y = 5
      if y != 0 { let result = x / y; say "Result: " + result } else { say "Cannot divide by zero" }
    }
    listen for "loop_example" {
      let numbers = [1,2,3,4,5]; let sum = 0
      for let i = 0; i < numbers.length; i++ { sum = sum + numbers[i] }
      say "Sum: " + sum
    }
  }
  memory { count }
}
```

## Current Status
- ✅ Modern syntax (let, fn, if, loop, while, for)
- ✅ Error handling integrated
- ✅ FFI functions (fs, http, math)
- ✅ System interface available (virtual OS + sysproxy bridge)
- ✅ Event-driven component architecture

## No Placeholders
- Placeholder/TODO/FIXME eliminated in `.azl` sources.
- All user-visible behavior paths are implemented.
