# Real-world language benchmarks (reference workloads)

This directory holds **standard, widely cited** microbenchmark sources used to compare **programming language implementations** in the wild—not AZL-specific HTTP timings.

## What this is

| Item | Role |
|------|------|
| **spectral-norm** | Classic **[Computer Language Benchmarks Game](https://benchmarksgame-team.pages.debian.net/benchmarksgame/)** workload (matrix-style numeric kernel). Upstream maintains rankings across dozens of languages. |
| **`spectralnorm.c`** | C reference (Sebastien Loisel contribution; see file header). |
| **`spectralnorm.py`** | Same algorithm in Python for **C vs Python** wall-time comparison. |

## What this is **not**

- **Not** a claim that AZL’s `.azl` interpreter beats C on this kernel today. A **native AZL** port of spectral-norm would be added separately once you want “AZL vs C” on the same problem.
- **Not** a replacement for **`scripts/perf_smoke.sh`** (native engine HTTP latency).

## How to run (requires [hyperfine](https://github.com/sharkdp/hyperfine))

From repository root:

```bash
bash scripts/benchmark_language_real_world.sh
```

Optional:

```bash
export AZL_BENCHMARK_SPECTRAL_N=1200   # problem size (default 800)
export AZL_BENCHMARK_HYPERFINE_RUNS=10
make benchmark-real-world
```

See **`docs/BENCHMARKS_REAL_WORLD.md`** for methodology, **ERROR** exits, and how this relates to AZL.
