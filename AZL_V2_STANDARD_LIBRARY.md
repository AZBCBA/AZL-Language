# AZL v2 Standard Library

## Overview
AZL v2 comes with a comprehensive standard library of built-in functions that make it a powerful programming language for intelligent systems.

## File I/O Functions

### `read_file(path)`
Reads the contents of a file and returns it as a string.
```azl
let content = read_file("data.txt")
say content
```

### `write_file(path, content)`
Writes content to a file and returns a success message.
```azl
let result = write_file("output.txt", "Hello World!")
say result  # "File written successfully"
```

## String Operations

### `split(text, delimiter)`
Splits a string into an array using the specified delimiter.
```azl
let fruits = split("apple,banana,cherry", ",")
# Result: ["apple", "banana", "cherry"]
```

### `join(array, separator)`
Joins an array of values into a string using the specified separator.
```azl
let words = ["hello", "world"]
let sentence = join(words, " ")
# Result: "hello world"
```

### `replace(text, from, to)`
Replaces all occurrences of `from` with `to` in the given text.
```azl
let result = replace("hello world", "world", "azl")
# Result: "hello azl"
```

## Array Operations

### `push(array, item)`
Adds an item to the end of an array and returns the new array.
```azl
let numbers = [1, 2, 3]
let new_numbers = push(numbers, 4)
# Result: [1, 2, 3, 4]
```

### `pop(array)`
Removes and returns the last item from an array.
```azl
let numbers = [1, 2, 3, 4]
let last = pop(numbers)
# Result: 4
```

### `slice(array, start, end)`
Extracts a portion of an array from index `start` to `end` (exclusive).
```azl
let numbers = [1, 2, 3, 4, 5]
let middle = slice(numbers, 1, 3)
# Result: [2, 3]
```

## Mathematical Functions

### Basic Math
- `abs(number)` - Absolute value
- `floor(number)` - Round down to nearest integer
- `ceil(number)` - Round up to nearest integer
- `round(number)` - Round to nearest integer
- `min(a, b)` - Minimum of two numbers
- `max(a, b)` - Maximum of two numbers

### Advanced Math
- `sqrt(number)` - Square root
- `pow(base, exponent)` - Power function
- `sin(angle)` - Sine (radians)
- `cos(angle)` - Cosine (radians)
- `tan(angle)` - Tangent (radians)
- `log(number)` - Natural logarithm
- `exp(number)` - Exponential function

### Examples
```azl
let x = -5.7
say abs(x)      # 5.7

let y = 16.0
say sqrt(y)     # 4.0

let z = 2.5
say pow(z, 3)   # 15.625

let angle = 0.5
say sin(angle)  # 0.479425538604203
```

## Utility Functions

### `random()`
Generates a random number between 0 and 1.
```azl
let random_num = random()
say random_num  # e.g., 0.19838352650905988
```

### `now()`
Returns the current Unix timestamp (seconds since epoch).
```azl
let current_time = now()
say current_time  # e.g., 1754033276
```

### `typeof(value)`
Returns the type of a value as a string.
```azl
say typeof("hello")  # "string"
say typeof(42)       # "number"
say typeof(true)     # "boolean"
say typeof([1,2,3])  # "array"
```

### `stringify(value)`
Converts any value to a string representation.
```azl
say stringify([1, 2, 3])  # "[1, 2, 3]"
say stringify(3.14)       # "3.14"
```

## Complete Example

```azl
# File operations
let content = "Hello from AZL v2!"
write_file("test.txt", content)
let file_content = read_file("test.txt")
say file_content

# String manipulation
let text = "apple,banana,cherry"
let fruits = split(text, ",")
let joined = join(fruits, " | ")
say joined  # "apple | banana | cherry"

# Array operations
let numbers = [1, 2, 3, 4, 5]
let pushed = push(numbers, 6)
let popped = pop(pushed)
say popped  # 6

# Math calculations
let a = 3.0
let b = 4.0
let hypotenuse = sqrt(pow(a, 2) + pow(b, 2))
say hypotenuse  # 5.0

# Time and random
let timestamp = now()
let random_val = random()
say "Time: " + stringify(timestamp)
say "Random: " + stringify(random_val)
```

## Error Handling

All functions include proper error handling:
- File operations return descriptive error messages if files can't be read/written
- Math functions check for invalid inputs (e.g., negative numbers for sqrt)
- Array operations validate indices and array bounds
- Type checking ensures correct argument types

## Performance

All functions are implemented in native Rust for maximum performance:
- File I/O uses standard library functions
- Math functions use optimized CPU instructions
- Array operations are memory-efficient
- String operations use efficient algorithms

## Future Additions

Planned additions to the standard library:
- Network functions (HTTP requests, WebSocket)
- Database operations (SQLite, Redis)
- Image processing
- Machine learning utilities
- Quantum simulation functions
- Neural network operations 