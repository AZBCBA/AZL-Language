# LHA3 Memory Stdlib API

Standard interface for quantum-enhanced LHA3 memory in AZL. Use these events to store and retrieve from LHA3 without dropping to host languages.

## Honesty: what “compression” means here

**Read first:** [LHA3_COMPRESSION_HONESTY.md](LHA3_COMPRESSION_HONESTY.md).  
Events **`compaction_fractal_memory`** / **`memory.lha3.compaction_applied`** on **`::memory.lha3_quantum`** and **`quantum_engine.apply_compaction`** on the engine implement **heuristic retention / count-based ratio math**, **not** lossless or lossy **byte codecs** over arbitrary payloads. For real blob compression, use a **separate, explicitly documented** codec path.

## Component

- **::memory.lha3_quantum** — Primary LHA3 component (p-adic, fractal, hyperdimensional)

## Store

```azl
emit "store_quantum_state" to ::memory.lha3_quantum with {
  key: "my_key",
  state: { data: "value", metadata: {} }
}
```

```azl
emit "lha3.store.processing_queue" to ::memory.lha3_quantum with {
  kind: "consciousness_step",
  step: ::current_step,
  awareness: ::state
}
```

## Retrieve

Listen for responses:

```azl
listen for "memory.lha3.compaction_applied" then {
  set ::result = ::event.data
}
listen for "memory.lha3.optimized" then {
  set ::result = ::event.data
}
```

## Initialize

```azl
emit "initialize_lha3_memory" to ::memory.lha3_quantum with {
  p_adic_prime: 7,
  precision: 10,
  max_dimensions: 64,
  ram_limit_gb: 2
}
listen for "memory.lha3.ready" then {
  say "LHA3 ready"
}
```

## Events

| Event | Direction | Purpose |
|-------|-----------|---------|
| `initialize_lha3_memory` | → ::memory.lha3_quantum | Initialize engine |
| `store_quantum_state` | → ::memory.lha3_quantum | Store state |
| `lha3.store.processing_queue` | → ::memory.lha3_quantum | Queue processing |
| `compaction_fractal_memory` | → ::memory.lha3_quantum | **Heuristic compaction signal** (forwards to engine; **not** byte codec — see [LHA3_COMPRESSION_HONESTY.md](LHA3_COMPRESSION_HONESTY.md)) |
| `memory.lha3.ready` | ← | Engine ready |
| `memory.lha3.compaction_applied` | ← | **Heuristic compaction result** (ratio / synthetic sizes from **counts** — not payload encoding) |
| `memory.lha3.optimized` | ← | Optimization scoring complete |
| `quantum_engine.apply_compaction` | → ::quantum.memory.lha3_quantum_engine | Internal: **policy ratio × item count** (same honesty contract) |
| `quantum_engine.compaction_applied` | ← | Engine applied **heuristic** compaction bookkeeping |
