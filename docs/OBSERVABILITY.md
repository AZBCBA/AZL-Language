## Observability (Tracing, Logging, Metrics)

### Status
- `tracing` and `tracing-subscriber` wired. Spans exist for `emit`, `process_events`, `dispatch_event`, and `execute_handler_with_timeout` (including `component` and `timeout_ms` fields). Test hooks capture processed event order under cfg(test).

### Tracing
- Use `tracing` with structured fields (component, event, span, op, error_kind)
- Spans for: file load, parse, interpret, compile, VM execute, FFI
- Correlate events by request/session IDs where applicable

### Current spans
- `azl.emit` (event)
- `azl.events.process` (max)
- `azl.events.dispatch` (event)
- `azl.handler` (event, component, timeout_ms)

### Logging
- Levels: error, warn, info, debug, trace
- Strict mode defaults to info; debug/trace only in dev

### Metrics
- Counters: events processed, errors by kind, GC cycles
- Gauges: memory usage, queue depths
- Histograms: op latencies (parse, execute, compile)

Planned additions
- Listener timeout count, cycle-detection count
- Per-priority processed counters (critical/high/medium/low)
- Expose `EventBus::stats_json()` for structured scraping in tests and observability exporters

### SLOs
- Track p95 execution for basic scripts; alert on regression


