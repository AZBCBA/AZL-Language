# AZL Standard Library (Pure AZL)

## Overview [VERIFIED]

The standard library is implemented as a pure AZL component `::azl.stdlib` that registers string, array, object, math, time, file and network helpers at startup (no external dependencies). It exposes a simple call protocol via events, and file/network operations use deterministic in-memory stores provided by the virtual OS.

- Component: `azl/stdlib/core/azl_stdlib.azl`
- No placeholders: RNG/time are deterministic; fs/http are in-memory
- Call interface: emit `call_function` with `[module, function, args]`; receive `function.result` or `function.error`

## Module Map

Internal registry (`::functions`) contains:
- `math`: add, subtract, multiply, divide, power, sqrt, abs, floor, ceil, round, random, min, max
- `string`: length, split, join, replace, substring, to_upper, to_lower, trim, starts_with, ends_with, contains
- `array`: length, push, pop, shift, unshift, slice, concat, index_of, includes, map, filter, reduce, sort, reverse
- `object`: keys, values, entries, has, get, set, delete, merge, clone, size
- `file`: read, write, append, exists, delete, list, size, modified
- `network`: http_get, http_post, http_put, http_delete, websocket_connect/send/close (stubs route to deterministic responses)
- `time`: now, timestamp, format, parse, add, subtract, diff

## How to call stdlib functions

Emit a `call_function` event with three arguments and listen for `function.result`:

```azl
emit call_function with ["math", "random", [0, 1]]
listen for "function.result" then { say "rand = " + ::event.data }
```

Notes:
- `args` is an array; pass `[]` if no arguments
- On missing entries, `function.error` is emitted with an error string

## Deterministic RNG and time [VERIFIED]
- RNG: Linear Congruential Generator with seed in `::rng_seed` (`random_seed([seed])` to set)
- Time: Monotonic ticks in `::time_ticks` (each `time_now([])` increments ticks)

## File and network behavior [VERIFIED]
- Files are stored in-memory (`::fs_store` in system interface). `file_*` helpers read/write/append and maintain `size` and `modified` metadata.
- HTTP helpers use `::http_store` keyed by URL. GET returns stored body or a deterministic default; POST/PUT set the body; DELETE clears it.

Example:
```azl
emit call_function with ["file", "write", ["/tmp/x.txt", "hello"]]
emit call_function with ["file", "read", ["/tmp/x.txt"]]
listen for "function.result" then { say "content = " + ::event.data }
```

## Function reference (selected)

- Math: `random([min, max])`, `add([a,b])`, `power([a,b])`, `sqrt([a])`
- String: `split([str, sep])`, `replace([str, old, new])`, `substring([str,start,end])`
- Array: `map([array, fn])`, `filter([array, fn])` (expects callable per your runtime conventions), `reduce([array, fn, init])`
- Object: `keys([obj])`, `get([obj, key])`, `set([obj, key, value])`
- File: `read([path])`, `write([path, content])`, `append([path, content])`, `exists([path])`, `list([path])`
- Network: `http_get([url])`, `http_post([url, body])`
- Time: `now([])`, `format([ts, fmt])`, `diff([a,b])`

## Notes
- The previous import-based stdlib (`stdlib/*.azl`) is retained for reference, but the canonical stdlib is `::azl.stdlib`.
- For portability, prefer the `call_function` protocol over direct function calls.

#### `flatten(array)`
Flattens a nested array structure.

**Parameters:**
- `array`: The input array (may contain nested arrays)

**Returns:** A flattened array

#### `find(array, predicate)`
Finds the first element that matches the predicate.

**Parameters:**
- `array`: The input array
- `predicate`: A function that returns true/false for each element

**Returns:** The first matching element or null if none found

#### `find_index(array, predicate)`
Finds the index of the first element that matches the predicate.

**Parameters:**
- `array`: The input array
- `predicate`: A function that returns true/false for each element

**Returns:** The index of the first matching element or -1 if none found

#### `includes(array, value)`
Checks if an array contains a specific value.

**Parameters:**
- `array`: The input array
- `value`: The value to search for

**Returns:** true if the value is found, false otherwise

## String Module (`stdlib/string.azl`)

The string module provides utilities for string manipulation and processing.

### Functions

#### `split(str, sep)`
Splits a string into an array using a separator.

**Parameters:**
- `str`: The input string
- `sep`: The separator character

**Returns:** An array of substrings

**Example:**
```azl
import { split } from "stdlib/string.azl";

let words = split("hello,world,azl", ",");
// Result: ["hello", "world", "azl"]
```

#### `join(array, sep)`
Joins an array of strings into a single string.

**Parameters:**
- `array`: Array of strings to join
- `sep`: The separator string

**Returns:** A single joined string

#### `to_upper(str)`
Converts a string to uppercase.

**Parameters:**
- `str`: The input string

**Returns:** The uppercase version of the string

#### `to_lower(str)`
Converts a string to lowercase.

**Parameters:**
- `str`: The input string

**Returns:** The lowercase version of the string

#### `trim(str)`
Removes whitespace from the beginning and end of a string.

**Parameters:**
- `str`: The input string

**Returns:** The trimmed string

#### `replace(str, old, new)`
Replaces occurrences of a substring in a string.

**Parameters:**
- `str`: The input string
- `old`: The substring to replace
- `new`: The replacement string

**Returns:** The string with replacements made

#### `starts_with(str, prefix)`
Checks if a string starts with a specific prefix.

**Parameters:**
- `str`: The input string
- `prefix`: The prefix to check for

**Returns:** true if the string starts with the prefix

#### `ends_with(str, suffix)`
Checks if a string ends with a specific suffix.

**Parameters:**
- `str`: The input string
- `suffix`: The suffix to check for

**Returns:** true if the string ends with the suffix

#### `contains(str, substr)`
Checks if a string contains a substring.

**Parameters:**
- `str`: The input string
- `substr`: The substring to search for

**Returns:** true if the substring is found

#### `index_of(str, substr)`
Finds the index of the first occurrence of a substring.

**Parameters:**
- `str`: The input string
- `substr`: The substring to search for

**Returns:** The index of the first occurrence or -1 if not found

#### `repeat(str, count)`
Repeats a string a specified number of times.

**Parameters:**
- `str`: The string to repeat
- `count`: The number of times to repeat

**Returns:** The repeated string

## Math Module (`stdlib/math.azl`)

The math module provides mathematical functions and utilities.

### Functions

#### `abs(x)`
Returns the absolute value of a number.

**Parameters:**
- `x`: The input number

**Returns:** The absolute value

#### `min(a, b)`
Returns the minimum of two numbers.

**Parameters:**
- `a`: First number
- `b`: Second number

**Returns:** The smaller of the two numbers

#### `max(a, b)`
Returns the maximum of two numbers.

**Parameters:**
- `a`: First number
- `b`: Second number

**Returns:** The larger of the two numbers

#### `floor(x)`
Returns the floor of a number.

**Parameters:**
- `x`: The input number

**Returns:** The largest integer less than or equal to x

#### `ceil(x)`
Returns the ceiling of a number.

**Parameters:**
- `x`: The input number

**Returns:** The smallest integer greater than or equal to x

#### `round(x)`
Rounds a number to the nearest integer.

**Parameters:**
- `x`: The input number

**Returns:** The rounded integer

#### `pow(base, exponent)`
Raises a number to a power.

**Parameters:**
- `base`: The base number
- `exponent`: The exponent

**Returns:** base raised to the power of exponent

#### `sqrt(x)`
Calculates the square root of a number.

**Parameters:**
- `x`: The input number (must be non-negative)

**Returns:** The square root, or null if x is negative

#### `random()`
Returns a random number between 0 and 1.

**Returns:** A random number in [0, 1)

#### `random_range(min, max)`
Returns a random number in a specified range.

**Parameters:**
- `min`: Minimum value (inclusive)
- `max`: Maximum value (exclusive)

**Returns:** A random number in [min, max)

#### `clamp(value, min_val, max_val)`
Clamps a value to a specified range.

**Parameters:**
- `value`: The value to clamp
- `min_val`: Minimum allowed value
- `max_val`: Maximum allowed value

**Returns:** The clamped value

#### `lerp(start, end, t)`
Performs linear interpolation between two values.

**Parameters:**
- `start`: Starting value
- `end`: Ending value
- `t`: Interpolation factor (0-1)

**Returns:** The interpolated value

#### `sign(x)`
Returns the sign of a number.

**Parameters:**
- `x`: The input number

**Returns:** 1 if positive, -1 if negative, 0 if zero

#### `is_even(n)`
Checks if a number is even.

**Parameters:**
- `n`: The input number

**Returns:** true if the number is even

#### `is_odd(n)`
Checks if a number is odd.

**Parameters:**
- `n`: The input number

**Returns:** true if the number is odd

#### `gcd(a, b)`
Calculates the greatest common divisor of two numbers.

**Parameters:**
- `a`: First number
- `b`: Second number

**Returns:** The greatest common divisor

#### `lcm(a, b)`
Calculates the least common multiple of two numbers.

**Parameters:**
- `a`: First number
- `b`: Second number

**Returns:** The least common multiple

## I/O Module (`stdlib/io.azl`)

The I/O module provides file and directory operations.

### Functions

#### `read_file(path)`
Reads the contents of a file.

**Parameters:**
- `path`: The file path to read

**Returns:** The file contents as a string

#### `write_file(path, content)`
Writes content to a file.

**Parameters:**
- `path`: The file path to write to
- `content`: The content to write

**Returns:** true on success

#### `append_file(path, content)`
Appends content to a file.

**Parameters:**
- `path`: The file path to append to
- `content`: The content to append

**Returns:** true on success

#### `file_exists(path)`
Checks if a file exists.

**Parameters:**
- `path`: The file path to check

**Returns:** true if the file exists

#### `delete_file(path)`
Deletes a file.

**Parameters:**
- `path`: The file path to delete

**Returns:** true on success

#### `list_directory(path)`
Lists the contents of a directory.

**Parameters:**
- `path`: The directory path to list

**Returns:** An array of file/directory names

#### `create_directory(path)`
Creates a new directory.

**Parameters:**
- `path`: The directory path to create

**Returns:** true on success

#### `delete_directory(path)`
Deletes a directory.

**Parameters:**
- `path`: The directory path to delete

**Returns:** true on success

## Usage Examples

### Functional Programming Pipeline
```azl
import { map, filter, reduce } from "stdlib/core/array.azl";
import { split, join } from "stdlib/string.azl";

let text = "hello,world,azl,programming";
let words = split(text, ",");
let filtered = filter(words, fn(word) { return word.length > 3; });
let result = map(filtered, fn(word) { return word.to_upper(); });
let final = join(result, " ");
say("Result: " + final);
```

### Mathematical Operations
```azl
import { abs, pow, sqrt } from "stdlib/math.azl";

let x = -5;
let y = abs(x);
let z = pow(y, 2);
let w = sqrt(z);
say("x: " + x + ", abs: " + y + ", squared: " + z + ", sqrt: " + w);
```

### File Operations
```azl
import { write_file, read_file } from "stdlib/io.azl";

write_file("test.txt", "Hello, AZL!");
let content = read_file("test.txt");
say("File content: " + content);
```

## Best Practices

1. **Import Only What You Need**: Import specific functions rather than entire modules to keep your code clean.

2. **Use Pure Functions**: The standard library functions are pure and don't have side effects. Use them for predictable behavior.

3. **Chain Operations**: Take advantage of functional programming patterns to chain operations together.

4. **Error Handling**: Check return values for operations that might fail (like file operations).

5. **Performance**: For large arrays, consider using more efficient algorithms or breaking operations into smaller chunks.

6. **Contributing**: When adding new functions to the standard library:

1. Follow the existing naming conventions
2. Include comprehensive documentation
3. Add unit tests for new functions
4. Ensure functions are pure and predictable
5. Consider performance implications
6. Update this documentation 