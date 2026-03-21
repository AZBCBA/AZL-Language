# Measuring AZL using the same *kinds* of lenses as Python

**Purpose:** Python’s “quality” is not one score — it is judged with **several parallel rulers** (tests, benchmarks, releases, ecosystem, security process, …). This document maps those **same lenses** to **concrete AZL commands and numbers** you can record over time.

**Plain English:** If you want to “measure AZL like the real world measures Python,” you use **the same categories**, and for each category you run **the AZL equivalent** and **write down the numbers** (or pass/fail where that is the only honest output).

---

## 1. Correctness (tests & specification)

| How Python is judged | AZL equivalent | What to run | What to record |
|----------------------|----------------|-------------|----------------|
| Huge regression suite on the reference implementation | Native gates (C ↔ Python parity on fixtures) + full verify | `bash scripts/check_azl_native_gates.sh` | **Seconds** (wall time) + **pass/fail** |
| Broader integration | Full repo verification | `make verify` (or `RUN_OPTIONAL_BENCHES=0 bash scripts/run_full_repo_verification.sh`) | **Seconds** + **pass/fail** |
| Size of the parity contract | Count of gated semantic fixtures | *(included in JSON report below)* | **Integer** (e.g. `p0_semantic_*.azl` count) |

---

## 2. Performance (speed on defined workloads)

| How Python is judged | AZL equivalent | What to run | What to record |
|----------------------|----------------|-------------|----------------|
| Micro-benchmark suites (e.g. many small timed programs) | **Reference ruler:** C vs Python on spectral-norm (not AZL code yet) | `make benchmark-real-world` | **Mean ms** per implementation, **ratio** (from hyperfine) |
| “How long does our full check take?” | Timed integration bar | `time make verify` or phases inside `make benchmark-azl-full-report` | **Seconds per phase** |
| AZL vs CPython on the *same* program | **Future:** port a kernel to `.azl` + same hyperfine driver | *(not shipped yet)* | **Mean ms** for AZL next to C/Python |

---

## 3. Stability (upgrades don’t break people)

| How Python is judged | AZL equivalent | What to run / do | What to record |
|----------------------|-----------------|------------------|----------------|
| Release notes + deprecation policy | CHANGELOG + roadmap | Read `CHANGELOG.md`, `docs/PROJECT_COMPLETION_ROADMAP.md` | **Qualitative** + **version tags** |
| CI always green on main | Same idea | `make verify` on each merge | **Pass rate over time** (your CI or manual log) |

---

## 4. Security & operations

| How Python is judged | AZL equivalent | What to record |
|----------------------|----------------|----------------|
| CVEs, advisories | Your process as the project grows | **Qualitative** for now |
| Live HTTP contract | `scripts/verify_native_runtime_live.sh` (inside `make verify`) | **Pass/fail** + any logged latencies from perf smoke |

---

## 5. Practicality (ecosystem & tooling)

| How Python is judged | AZL equivalent | What to record |
|----------------------|----------------|----------------|
| PyPI size, downloads | azlpack / stdlib surface / LSP | **Counts** (packages, tests that prove LSP) — expand as AZL grows |
| Docs | Doc verification pieces | `make verify-doc-pieces` | **Pass/fail** + piece counts from manifest |

---

## 6. Adoption

| How Python is judged | AZL equivalent |
|----------------------|------------------|
| Surveys, jobs, GitHub | **Your** metrics: users, repos, deployments — outside this repo unless you add telemetry you control. |

---

## One command that writes a **measurement file** (numbers + metadata)

From repository root:

```bash
bash scripts/measure_azl_quality_parallel.sh
```

**Richer snapshot** (still not full `make verify` unless you ask):

```bash
AZL_MEASURE_COMPREHENSIVE=1 bash scripts/measure_azl_quality_parallel.sh
```

That turns on **promoted doc-piece timing**, **reference C/Python spectral-norm** (if `hyperfine` + `gcc` exist), and **perf smoke** timing when `scripts/perf_smoke.sh` is runnable.

**Heaviest** (full integration bar + reference):

```bash
AZL_MEASURE_FULL_VERIFY=1 AZL_MEASURE_REFERENCE=1 bash scripts/measure_azl_quality_parallel.sh
```

Writes:

- **JSON** — **`.azl/benchmarks/azl_quality_measurement_*.json`** — schema **`azl_quality_measurement_v2`** adds **codebase inventory** (file/line counts, interpreter size) and **documentation manifest** counts.
- **Plain-language report** — **`.azl/benchmarks/azl_quality_measurement_*_report.md`** — tables in everyday wording.

See **`scripts/azl_local_layout.sh`** for **`AZL_BENCHMARKS_DIR`**.  
**Errors:** prefix **`ERROR[BENCHMARK_AZL_QUALITY_PARALLEL]:`** — **`docs/ERROR_SYSTEM.md`**.

**Makefile:** `make measure-azl-quality`

---

## See also

- [BENCHMARKS_AZL_VS_REAL_WORLD.md](BENCHMARKS_AZL_VS_REAL_WORLD.md) — why there is no single “AZL vs Python” number yet  
- [INTEGRATION_VERIFY.md](INTEGRATION_VERIFY.md) — `make verify`  
- [AZL_ENGINEERING_REALITY_AUDIT.md](AZL_ENGINEERING_REALITY_AUDIT.md) — claims vs what runs  
