## Engineering Readiness Checklists

### Phase 1 Status Summary
- Error taxonomy expanded (Timeout, Cycle, Ffi) and used in runtime; spans wired for emit/process/dispatch/handler.
- EventBus recursion guard, cycle detection, centralized per-listener timeout, and priority queues + batching implemented.
- `nalgebra` math in runtime and initial FFI math bridge added; tests in progress.
- Expression evaluator precedence (+, *) and parentheses implemented; handler-scope cleanup and memory metrics added.

### Phase 1 (Runtime/FFI/Core)
- [ ] Type system validation with coercion rules and tests
- [x] Scoped memory cleanup + usage metrics (basic handler cleanup; counters; reports)
- [x] Event queue with priority + timeouts; recursion/cycle guards (implemented); tracing spans added (emit/process/dispatch/handler)
- [ ] Error taxonomy wired end-to-end with spans/context
- [ ] FFI strict gating; zero panics; 90% coverage

### Phase 2 (Interpreter)
- [ ] Lexer (escapes, numbers, spans)
- [ ] Parser (recovery, diagnostics)
- [ ] AST with spans
- [ ] Interpreter (env, scopes, control flow, functions)
- [ ] Event integration; golden tests; fuzz green

### Phase 3 (Compiler/VM)
- [ ] AST→Bytecode; verifier; disassembler
- [ ] VM core; instruction set; runtime checks
- [ ] GC hooks; equivalence tests; fuzz

### Ops & Docs (Every Phase)
- [ ] Observability hooks
- [ ] CI gates updated
- [ ] Runbooks/docs updated


