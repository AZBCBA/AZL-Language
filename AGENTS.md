# Agent instructions (AZL Language repository)

**For Cursor, Codex, Copilot, or any automated assistant:** this repo’s **continuity** lives in **git**, not in chat history.

## Before you architect or claim “how AZL runs”

1. **`docs/AI_MAINTAINER_CONTINUITY_HANDOFF.md`** — long-discussion consensus, anti-loop rules, reality vs aspiration.  
2. **`docs/AZL_STRATEGIC_CONSENSUS_AND_EXECUTION_PLAN.md`** — north star, phases, compression policy, research wedges.  
3. **`docs/RUNTIME_SPINE_DECISION.md`** — **source of truth** for the current native/spine trace.  
4. **`docs/PROJECT_COMPLETION_ROADMAP.md`** — P0–P5 queue and gates; **§ P0.1** = ordered vertical-slice plan toward **`azl_interpreter.azl`** on the semantic spine (see **`docs/TIER_B_BACKLOG.md`** § **P0.1 execution checklist**).

## Honesty

- **`docs/AZL_ENGINEERING_REALITY_AUDIT.md`** — code vs narrative.  
- **`docs/LHA3_COMPRESSION_HONESTY.md`** — heuristic vs literal byte codecs.

## Errors and verification

- **`docs/ERROR_SYSTEM.md`** — mandatory failure behavior.  
- Integration: **`docs/INTEGRATION_VERIFY.md`** (`make verify`).
- **P0.1b (release):** **`scripts/verify_azl_interpreter_semantic_spine_smoke.sh`** runs inside **`run_full_repo_verification.sh`** step **3** — real **`azl/runtime/interpreter/azl_interpreter.azl`** **`init`** on Python spine (**`docs/ERROR_SYSTEM.md`** **286–290**); not full **`behavior`** yet.

## Semantic spine parity (C minimal ↔ Python `minimal_runtime`)

**`scripts/check_azl_native_gates.sh`** gates **F2–F82** diff **`tools/azl_interpreter_minimal.c`** vs **`tools/azl_runtime_spine_host.py`** on **`azl/tests/p0_semantic_*.azl`** (and **`c_minimal_link_ping.azl`** for F2). New behavior needs a fixture + gate block + new **§ Native gates** rows in **`docs/ERROR_SYSTEM.md`** (avoid exit collisions; **286–290** = interpreter spine smoke, not F68). **F9** stdout mismatch = **59** (not **`verify_native_runtime_live.sh`** **69**). **F10–F14** = **111–125**; **F15–F18** = **126–137**; **F19–F20** = **138–143**; **F21** = **144–146**; **F22** = **147–149**; **F23–F25** = **150–158**; **F26–F28** = **159–167**; **F29–F31** = **168–176**; **F32–F35** = **177–188**; **F36–F39** = **189–200**; **F40–F43** = **201–212**; **F44–F47** = **213–224**; **F48–F51** = **225–236**; **F52–F55** = **237–248**; **F56–F58** = **249–257**; **F59–F61** = **258–266**; **F62** = **267–269**; **F63** = **270** / **272** / **273** (skip **271** — **`CODEC_DECOMPRESS_FAILED`**); **F64** = **274–276**; **F65–F67** = **277–285**; **F68** = **291–293**; **F69** = **294–296**; **F70** = **297–299**; **F71** = **311–313**; **F72** = **314–316**; **F73** = **317–319**; **F74** = **323–325**; **F75** = **326–328**; **F76** = **329–331**; **F77** = **332–334**; **F78** = **335–337**; **F79** = **338–340**; **F80** = **341–343**; **F81** = **344–346**; **F82** = **347–349**.

## Cursor

- **Always-on rule:** `.cursor/rules/azl-continuity.mdc`

Do not treat aspirational comments inside `.azl` files as proof of runtime behavior until the spine and tests agree.
