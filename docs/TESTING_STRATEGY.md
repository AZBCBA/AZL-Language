## Testing Strategy

### Near-term tests (Pure AZL)
- Interpreter: expression evaluation, division-by-zero logs and returns, type_of classification
- Virtual OS: read/write/list_dir/file_exists/delete_file/http/mmap/munmap/exec/console.write
- Stdlib: file/network/time/random deterministic behaviors

### Levels
- Unit: tokenizer, parser, interpreter primitives
- Integration: event flow with recursion/cycle guard; syscall round-trips
- Property-based: arithmetic equivalences for numbers; RNG determinism per seed
- Golden: log outputs for selected flows

### Coverage
- ≥ 80% short-term across interpreter + stdlib + system interface

### CI
- Load system + interpreter + tests via scripts and verify zero failures; emit summary artifacts in `reports/`

### Current status
- Pure AZL interpreter, stdlib, and system interface verified; tests being migrated to `azl/testing/`


