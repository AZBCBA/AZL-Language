# What can feed the **AZL language** (reuse map)

**Canonical product tree:** `azl/` (this is what gates and the native engine expect).

Everything below is **candidates to mine** for idioms, components, and integration patterns — **promote into `azl/` only** after you copy, test, and wire contracts.

---

## 1) `project/entries/azl/` — entrypoints you still run

| File | `component ::` (main) | Likely language value |
|------|------------------------|------------------------|
| `run_azl_pure.azl` | `::azl.pure.runner` | Minimal runner / boot pattern for “pure AZL” demos |
| `azme_chat_integration.azl` | `::azme.chat_integration` | How AZME chat is stitched into a combined bundle (used by `scripts/run_full.sh`, `run_chat.sh`, `launch_agi_system.sh`) |
| `azme_complete_launcher.azl` | `::azme.complete_launcher` | Fat launcher composition (see also `launch_azme_complete.sh`) |
| `azme_interactive_chat.azl` | `::azme.interactive_chat` | Interactive CLI-style chat loop patterns |
| `azme_example.azl` | `::azme.example`, `::calculator_behavior`, `::greeter_behavior`, `::coordinator_behavior` | **Good teaching material**: small multi-component coordination |
| `agi_behavior_template.azl` | `::agi_behavior_template` | Agent spawn / behavior template pattern |

---

## 2) `project/repo_root/azl/` — moved demos / training sketches

| File | Notes | Likely language value |
|------|--------|------------------------|
| `quantum_processor_example.azl` | `::example.quantum_processor_demo`, executor, runner | Event-driven pipeline example |
| `real_proof_demonstration.azl` | `::proof.demonstration` | Proof / assertion-style narration patterns |
| `simple_working_training.azl` | `::simple.working.training` | End-to-end “training” story in AZL |
| `start_training.azl` | `::launch.training`, `::nlp.training` | Boot + NLP training orchestration sketch |
| `generate_weights.azl` | `::weight_generator` | Weight init / generation idiom |
| `azme_production_launcher.azl` | `::azme.production_launcher` | Production-shaped launcher (verify before trusting) |
| `azme_real_ai_system.azl` | `::azme.real_ai_system` | Large integration surface — mine **small** pieces |
| `azme_status.azl` | `::azme.status` | Status / usage strings (updated paths for idle entries) |
| `azme_training_monitor.azl` | `::azme.training_monitor` | Monitoring hooks pattern |
| `continuous_real_training.azl`, `continuous_training_loop.azl`, `real_training_system.azl`, `functional_library.azl` | Use older `::name.block` style in places, not only `component ::` | **Historical syntax + training loops** — compare to current grammar; extract ideas, not paste wholesale |

---

## 3) `azme/` — **111** `.azl` files (~**74** `component ::` lines)

This tree is **the AZME product**, not the core language — but it is **rich AZL source** for:

- **Runtime glue:** `azme/runtime/{azme_unified_runtime,azme_runtime_bootstrap}.azl`, `azme/cognitive/azme_cognitive_loop.azl`
- **Plugin / tool patterns:** `azme/system/azme_plugin_*.azl`, `azme/integrations/*`
- **Interface / IO:** `azme/interface/azme_chat_interface.azl`, voice/web/fs helpers
- **Neural / training orchestration:** `azme/neural/*`, `azme/training/*`, `azme/learning/*`
- **Sandbox / simulation:** `azme/sandbox/*`
- **Perception (heavy / external):** `azme/perception/*` — often assumes external stacks; mine **event shapes** first

**Practical rule:** when promoting to `azl/`, prefer **small components** with **clear events** and **no undeclared host deps**.

---

## 4) `azl/examples/` — **official** language demos (use these first)

| File | Component | Use |
|------|-----------|-----|
| `azl_syntax_examples.azl` | `::azl.syntax_examples` | Grammar / style reference |
| `runtime_demo.azl` | `::azl.runtime_demo` | Runtime behavior |
| `compiler_demo.azl` | `::azl.compiler_demo` | Compiler path |
| `self_hosting_parser_demo.azl` | `::azl.self_hosting_demo` | Parser / self-host story |
| `iris_training.azl`, `iris_neural_classifier.azl`, `capability_showcase.azl` | (open file for `component ::`) | ML-ish examples in **current** tree |

---

## 5) Root `stdlib/` and `modules/` (parallel to `azl/stdlib`)

Small legacy trees (`stdlib/string.azl`, `modules/quantum.azl`, …). **Treat as historical.** Before reuse, **diff against** `azl/stdlib/` and promote only what is missing or clearer.

---

## 6) Config / JSON that shapes behavior (not “language syntax” but affects runs)

| Path | Role |
|------|------|
| `project/entries/config/*.json` | Training / unified LLM configs for AZME pipelines |
| `tokenizers/tokenizer*.json` | Tokenizer assets for training-side tooling |
| `project/repo_root/json/*` | Old probes / exports (e.g. large `lha3_memory_export.json`) — **data**, not code |

---

## Suggested order when you “start using” this

1. Read **`azl/examples/`** and **`project/entries/azl/azme_example.azl`** (smallest wins).  
2. If you need **chat bundles**, trace **`project/entries/azl/azme_chat_integration.azl`** from `scripts/run_chat.sh` / `run_full.sh`.  
3. Pull **one component** from **`azme/`** at a time into `azl/` with a test or gate.  
4. Only then open **large** files (`continuous_*`, `real_training_system`, `azme_real_ai_system`).

Regenerate component lists anytime:

```bash
rg -n '^[[:space:]]*component[[:space:]]+::' project/entries/azl project/repo_root/azl azme azl/examples --glob '*.azl'
```
