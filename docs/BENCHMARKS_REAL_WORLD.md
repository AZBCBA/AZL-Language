# Real-world language benchmarks (industry reference workloads)

**Purpose:** Give AZL maintainers a **standard**, **externally defined** numeric benchmark—the same class of workloads used to compare **programming languages** on the [Computer Language Benchmarks Game](https://benchmarksgame-team.pages.debian.net/benchmarksgame/) (Debian team)—**separate** from AZL-native HTTP checks (`scripts/perf_smoke.sh`, `scripts/benchmark_native_api.sh`).

---

## What we ship

| Piece | Description |
|-------|-------------|
| **`benchmarks/real_world/spectralnorm.c`** | **spectral-norm** kernel in C (Benchmarks Game lineage; Sebastien Loisel contribution—see file header). |
| **`benchmarks/real_world/spectralnorm.py`** | Same algorithm in Python for a fair **C vs Python** wall-time race. |
| **`scripts/benchmark_language_real_world.sh`** | Builds C with **`gcc -O3`**, verifies **C vs Python** agree at **N=100**, then runs **[hyperfine](https://github.com/sharkdp/hyperfine)** on both at configurable **N**. |

**Output:** JSON under **`.azl/benchmarks/benchmark_language_real_world_hyperfine.json`** (via `azl_local_layout.sh` → `AZL_BENCHMARKS_DIR`).

---

## Why hyperfine

**Hyperfine** is widely used in industry and open source to benchmark CLI programs (mean, stdev, warmup). It is the de facto modern replacement for ad-hoc `time` loops.

---

## Relation to AZL the language

- **Today:** This measures **compiled C** vs **CPython** on a **classic language-benchmark kernel**. It does **not** execute `.azl` source for spectral-norm yet.
- **Later:** An **`.azl` port** of the same kernel (minimal interpreter or native path) can be added as a **third** hyperfine command, and documented here as **AZL vs reference**.

That separation is **honest**: we do not claim AZL runs Benchmarks Game workloads until a runner exists.

---

## How to run

**Prerequisites:** `hyperfine`, `gcc`, `python3` — all mandatory; the script **errors** if any are missing (**no silent fallback**).

```bash
bash scripts/benchmark_language_real_world.sh
```

```bash
export AZL_BENCHMARK_SPECTRAL_N=1200
export AZL_BENCHMARK_HYPERFINE_RUNS=10
make benchmark-real-world
```

---

## Error system

Prefix **`ERROR[BENCHMARK_LANGUAGE_REAL_WORLD]:`** on stderr. Exits **300–307** — [ERROR_SYSTEM.md](ERROR_SYSTEM.md).

---

## See also

- [BENCHMARKS_AZL_VS_REAL_WORLD.md](BENCHMARKS_AZL_VS_REAL_WORLD.md) — **plain English:** why there is no single “AZL on the Benchmarks Game chart” yet; **`make benchmark-azl-full-report`**
- [benchmarks/real_world/README.md](../benchmarks/real_world/README.md) (directory README)  
- [LLM_INFRASTRUCTURE_AUDIT.md](LLM_INFRASTRUCTURE_AUDIT.md) (HTTP / LLM benches)  
- `scripts/perf_smoke.sh` (native API latency smoke)
