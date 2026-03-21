# AZL “full” testing vs “languages in the real world” — plain English

**Who this is for:** You want **one benchmark that tests all of AZL** and a **chart like other languages** (Python, Rust, C, … on the same program). This page explains **what exists today**, **what is impossible without lying**, and **what to run**.

---

## 1. What sites like the Benchmarks Game actually show

On **[The Computer Language Benchmarks Game](https://benchmarksgame-team.pages.debian.net/benchmarksgame/)**, people submit **the same small program** (for example **spectral-norm**) written in **many languages**. The site times **that one program** in each language.

So the comparison is always:

> **Same task, same algorithm shape, different language implementations.**

AZL is **not** on that website today, and there is **no official row** that says “AZL” next to “Python” for spectral-norm — because **nobody has submitted** a conforming AZL program + driver that the game accepts.

---

## 2. Why there is no single button “test 100% of AZL like one Benchmarks Game program”

AZL in this repo is **not one tiny program**. It is:

| Part | What it is |
|------|------------|
| **Language + libraries** | Large `.azl` trees (parser, interpreter, stdlib, memory, quantum/RepertoireField surfaces, …). |
| **Runtimes** | **C minimal** child, **Python** semantic engine, **native HTTP engine**, **enterprise combined** bundle, VM / azlpack / LSP checks, … |

**No one program uses every keyword, every module, and every HTTP path at once.** So “fully test the language” in engineering terms means **a whole suite of scripts and fixtures**, not one `main()` like spectral-norm.

**Honest statement:**  
**`make verify`** (full repo verification) is the closest thing to “exercise everything the project treats as release truth” — but it measures **your integration bar**, not “AZL vs Java on binary-trees.”

---

## 3. What you should run for “all of AZL” (this repository)

| Goal | Command | What it means in plain English |
|------|---------|--------------------------------|
| **Full AZL + tests the maintainers ship** | **`make verify`** | Runs doc contracts, native gates, minimal + enterprise HTTP, quantum/LHA3 checks, grammar, VM, azlpack, LSP, … **This is the real “full AZL” bar.** |
| **One report with timings + explanation** | **`make benchmark-azl-full-report`** | Runs the big verify (optional benches off), perf smoke, and **writes a Markdown report** under **`.azl/benchmarks/`**. |
| **Reference “other languages” timing** | **`make benchmark-real-world`** | **C vs Python** on **spectral-norm** (Benchmarks Game–style). **This is not AZL** — it is a **ruler** so you see how fast “normal” languages are on a classic problem on **your** machine. |
| **Same *categories* as Python’s quality story, in numbers** | **`make measure-azl-quality`** | Writes **JSON** (timed native gates, fixture counts, optional full verify + reference spectral-norm). See **[AZL_QUALITY_MEASUREMENTS_VS_PYTHON.md](AZL_QUALITY_MEASUREMENTS_VS_PYTHON.md)**. |

Together:

- **AZL position on “our side”** = whether **`make verify`** passes and how long it takes (report).
- **Other languages on “their side”** = spectral-norm **C vs Python** (and later you could add Rust, etc.) on the same machine.

There is **still no single number** “AZL = 1.2× Python” for the **whole language** until you define **one** AZL program that does the same work as the reference and run it under a stable AZL entrypoint.

---

## 4. Roadmap (if you want a true “AZL on the chart” later)

1. **Pick one** Benchmarks Game–style kernel (e.g. spectral-norm).  
2. **Implement it in AZL** to the extent **your chosen runtime** supports (minimal subset first).  
3. **Drive it** the same way every time (fixed bundle, fixed entry, fixed `N`).  
4. **Time it** with **hyperfine** next to **C** and **Python** on the same box.  
5. Then you can say, plainly: **“On spectral-norm at N=800, AZL (minimal) took X ms; C took Y ms; Python took Z ms.”**

Until step 2–4 exist, **any claim that AZL is “on the chart” for that workload would be marketing, not measured fact.**

---

## 5. Error system

- **`make verify`** / **`run_full_repo_verification.sh`** — failures use existing **`ERROR:`** / gate exits (see [ERROR_SYSTEM.md](ERROR_SYSTEM.md)).  
- **`scripts/benchmark_azl_full_coverage_report.sh`** — if a required phase fails, the script **exits with that phase’s code** after writing a partial report.  
- **`scripts/benchmark_language_real_world.sh`** — exits **300–307**; see [ERROR_SYSTEM.md](ERROR_SYSTEM.md).

---

## See also

- [AZL_QUALITY_MEASUREMENTS_VS_PYTHON.md](AZL_QUALITY_MEASUREMENTS_VS_PYTHON.md) — Python-style lenses → AZL commands + **`make measure-azl-quality`**  
- [BENCHMARKS_REAL_WORLD.md](BENCHMARKS_REAL_WORLD.md) — spectral-norm + hyperfine  
- [INTEGRATION_VERIFY.md](INTEGRATION_VERIFY.md) — **`make verify`**  
- [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md) — which stack owns which semantics  
