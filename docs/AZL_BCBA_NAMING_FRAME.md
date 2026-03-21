# BCBA-aligned product language — memory, “whole picture” reasoning, and ABA

**Audience:** Maintainers and docs authors.  
**Status:** **RepertoireField** is the **chosen public name** for the whole-picture-then-commit subsystem (see §2). **LHA3** meaning / rename is **still open** (§3). Code paths today still use legacy tags **`lha3_*`** and **`azl/quantum/`** until a coordinated rename milestone.

**Engineering check:** [AZL_ENGINEERING_REALITY_AUDIT.md](AZL_ENGINEERING_REALITY_AUDIT.md) — what the repo **actually implements** vs this product language (compression, crypto, Rust, etc.).

---

## 1. What you intend (authoritative intent)

- **ABA (Applied Behavior Analysis)** here means **how humans actually learn** under real contingencies: antecedents, behaviors, consequences, reinforcement, shaping, generalization, maintenance, etc.
- AZL is meant to **use that field seriously** — not as decoration — so that **future AI systems** can **learn in a human-like way** (clear targets, measurable outcomes, ethical supervision, reproducible teaching).
- This is **real software behavior**, described in terms that match **behavior analysis**, not lab quantum hardware.

---

## 2. RepertoireField — **chosen** public name (whole picture → one outcome)

**Meaning:** the program holds the **whole situation** together, then **commits to a single outcome** — like seeing the **full board** before moving — **without** claiming quantum computers or fake physics.

**Product name (maintainer choice, locked):** **RepertoireField**.  
In behavior analysis, a **repertoire** is the set of behaviors available; the **field** is the **whole active set** you are working with at once. The name stays **on-brand for a BCBA-led project** and reads as a **real subsystem**, not sci-fi filler.

**Also-approved alternates** (use in docs or sub-features if useful): **ContingencyGraph**, **Synoptic** (layer / engine / core), **Nexus**, **Confluence**.

**Implementation note:** **`azl/quantum/`** and older “quantum” wording in code remain **legacy paths** until a coordinated rename (e.g. to **`azl/repertoire_field/`**) is scheduled — **large diff**, separate PR.

---

## 3. “LHA3” was random — give it a real meaning (or retire the letters)

**Option A — Keep the tag, define it (backronym)** so existing code and events don’t break:

| Expansion | Plain English |
|-----------|----------------|
| **L**earning **H**istory **A**rchive | Stores **what happened** over time (episodes, outcomes), for later teaching decisions |
| **L**ong-horizon **H**abit **A**ggregate | Pulls together **patterns** over long runs (not only the last step) |
| **L**attice **H**ierarchical **A**ssociations | If you want a **math-shaped** name: linked levels of association (still “just a name” unless the math is real) |

The **“3”** can mean: **third tier** of memory (e.g. working → episodic → long-horizon), or **three linked stores** you document in one place.

**Option B — New public name, LHA3 as legacy alias**

Examples tied to BA:

| Name | Meaning |
|------|---------|
| **Episode archive** | Stores **learning episodes** (context → action → outcome) |
| **Contingency log** | Stores **what followed what** (consequences tied to behavior in context) |
| **Repertoire store** | Stores **what the system can do now** and **how it got there** |

Implementation-wise, **`::memory.lha3_*`** and event names can stay until you schedule a **versioned rename** (new components + deprecation notices).

---

## 4. ABA in one line for outsiders

**“We use behavior-analytic principles so the language and runtime support teaching and learning the way humans learn — clear targets, consequences, and measurement — not only one-shot statistical optimization.”**

---

## 5. Next step (open)

- **RepertoireField:** done for **public / docs language** (see **`docs/AZL_GPU_NEURAL_SURFACE_MAP.md` §0**).  
- **LHA3:** pick a **backronym** (§3 option A), a **new public name** (§3 option B), or **defer** — code and events can stay **`lha3_*`** until you decide. When you decide, update **`docs/LHA3_STDLIB_API.md`** in one pass.
