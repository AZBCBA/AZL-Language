# Tier B backlog — language & platform (after Tier A)

**Tier A** (native release profile) is defined in [PROJECT_COMPLETION_STATEMENT.md](PROJECT_COMPLETION_STATEMENT.md). This file is the **ordered continuation** for **Tier B**: roadmap work that is **not** required to say “shipping bar met,” but **is** required before claiming **full AZL spine / roadmap complete**.

Use it for sprint planning. Update rows when scope changes.

---

## P0 — Semantic spine (highest priority)

| ID | Work | Acceptance hint | Risk |
|----|------|-------------------|------|
| P0.1 | **Execute `azl/runtime/interpreter/azl_interpreter.azl` on semantic spine** — widen `tools/azl_semantic_engine/minimal_runtime.py` (and C minimal where parity is required) until the **real** interpreter `init` + minimal `behavior` path runs, or introduce a **verified** compile/transpile step to the same semantics. | Process trace: enterprise/native path with `AZL_RUNTIME_SPINE=azl_interpreter` shows **Python semantic host** (or successor) applying semantics from that file, not only `c_minimal` on the same combined program; **Gate G2** (`verify_semantic_spine_owner_contract.sh`) **fails** if the semantic spine stops being **`minimal_runtime` Python** (C must not become execution owner on that launcher). **Still open:** run full `azl_interpreter.azl` source through that engine. | **L** |
| P0.2 | **Default spine policy** — if product chooses `azl_interpreter` as default, update `scripts/azl_resolve_native_runtime_cmd.sh`, [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md), [AZL_NATIVE_RUNTIME_CONTRACT.md](AZL_NATIVE_RUNTIME_CONTRACT.md), and ops docs in one PR. | Single documented default; no contradictory “default” in README vs spine doc. | **M** |
| P0.3 | **Parity gates** — extend gates **F2/F3/F4** (or add **F5+**) for each new minimal-runtime feature so C vs Python (and later native semantic) stay byte- or contract-aligned. | `check_azl_native_gates.sh` green; [ERROR_SYSTEM.md](ERROR_SYSTEM.md) updated for new exits. | **M** |

**Shipped increment (2026-03-20):** gate **F5** — **`p0_semantic_var_alias.azl`**; exits **35–37**. Gate **F6** — **`p0_semantic_expr_plus_chain.azl`**; exits **40–42**. Gate **F7** — **`p0_semantic_dotted_counter.azl`**; exits **61–63**. Gate **F8** — **`p0_semantic_behavior_interpret_listen.azl`**; exits **64–66**. Gate **F9** — **`p0_semantic_behavior_listen_then.azl`**; exits **67**, **68**, **59** (mismatch). **Shipped increment (2026-03-21):** gate **F10** — **`p0_semantic_emit_event_payload.azl`** (**`emit … with { … }`** → **`::event.data.*`**); exits **111**, **112**, **113** (mismatch). Gate **F11** — **`p0_semantic_emit_multi_payload.azl`** (comma-separated keys); exits **114**, **115**, **116** (mismatch). Gate **F12** — **`p0_semantic_emit_queued_payloads.azl`**; exits **117**, **118**, **119** (mismatch). Gate **F13** — **`p0_semantic_payload_expr_chain.azl`**; exits **120**, **121**, **122** (mismatch). Gate **F14** — **`p0_semantic_payload_if_branch.azl`**; exits **123**, **124**, **125** (mismatch). Gates **F15–F18** — nested/quoted **`emit`**+payload, **`!=`**, **`or`** fallback; exits **126–137** (mismatch bands per gate). Gates **F19–F20** — empty **`with`**, single-quoted values; exits **138–143**. Gate **F21** — payload key collision (**`trace`** outer/inner); exits **144–146**. Gate **F22** — nested **`listen`** + **`emit with`**; exits **147–149**. Gates **F23–F25** — **`listen … then`** + payload, numeric payload, **`link`** in listener; exits **150–158**. Gates **F26–F28** — payload **`true`**, nested inner multi-key **`with`**, payload **`false`**; exits **159–167**. Gates **F29–F31** — payload **`null`**, duplicate **`listen`** (first wins), payload float; exits **168–176**. Gates **F32–F35** — missing **`::event.data.* == null`**, big int **`65535`**, **`set`** from payload, present **`!= null`**; exits **177–188**. Gates **F36–F39** — quoted negative string, **`emit`** inside listener (nested order), **`traceid:`** payload key, **`if (true)`** in listener; exits **189–200**. Gates **F40–F43** — **`if (false)`**, **`listen`** in **`init`**, squote payload with space, sequential **`emit`** payloads; exits **201–212**. Gates **F44–F47** — **`if (1)`**, **`emit "ev"`** without **`with`**, **`say`** unset → blank line, **`if (::flag)`** after **`set`** from payload; exits **213–224**. Gates **F48–F51** — **`if (0)`**, unquoted **`emit`**, **`say`** **`""`**, payload **`"false"`** not truthy in **`if`**; exits **225–236**. Gates **F52–F55** — string **`"true"`**/**`"1"`** truthy **`if (::t)`**, same-event **`x`** twice payloads, **`listen`**+**`emit`** in **`boot.entry`**; exits **237–248**. Gates **F56–F58** — string **`"0"`**/**`""`** not truthy in **`if`**, first-**`link`** wins across components on duplicate **`listen`**; exits **249–257**. Gates **F59–F61** — two bare **`emit`** same event, **`if`** **`or`** with empty global, **`if (::a == ::b)`** on strings; exits **258–266**. Gates **F62–F64** — **`!=`** on globals, skip when equal, **`set ::u = ::a + ::b`**; exits **267–276** (**271** unused — literal codec). Gates **F65–F67** — literal **`==`**/**`!=`** in **`if`**, **`set`** with three-way **`+`**; exits **277–285**. **Literal AZL0:** identity + **zlib `codec_id=1`**, exit **271** **`CODEC_DECOMPRESS_FAILED`**; **`verify_azl_literal_codec_roundtrip.sh`**.

**Already shipped (do not re-do):** gate **H** (tokenizer + brace balance), gate **G** (spine resolver contract), **P0c/P0d** slice fixtures — see [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md).

---

## P1 — HTTP / API alignment

| ID | Work | Acceptance hint |
|----|------|-----------------|
| P1.1 | **Canonical profile per deployment** — tighten [CANONICAL_HTTP_PROFILE.md](CANONICAL_HTTP_PROFILE.md) + runbooks so **Profile A vs B** is unambiguous for your operators. | OPERATIONS / staging docs reference one primary profile per environment. |
| P1.2 | **Contract vs implementation audit** — align [AZL_NATIVE_RUNTIME_CONTRACT.md](AZL_NATIVE_RUNTIME_CONTRACT.md) with actual C routes vs `http_server.azl` where both exist. | Table of endpoints × profile; no silent mismatch in CI benches. |

---

## P2 — Process capability policy

| ID | Work | Acceptance hint |
|----|------|-----------------|
| P2.1 | **`proc.exec` / `proc.spawn`** under explicit capability / policy — per [AZL_NATIVE_RUNTIME_CONTRACT.md](AZL_NATIVE_RUNTIME_CONTRACT.md). | Tests + ERROR exits; docs. |

---

## P3 — VM breadth (`AZL_USE_VM`)

| ID | Work | Acceptance hint |
|----|------|-----------------|
| P3.1 | Widen VM slice **after** P0 semantic spine is canonical — [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md). | `scripts/test_azl_use_vm_path.sh` expanded; contract updated. |

---

## P4 — Packages

| ID | Work | Acceptance hint |
|----|------|-----------------|
| P4.1 | Resolution / publishing beyond local dogfood — [AZLPACK_SPEC.md](AZLPACK_SPEC.md). | Policy + optional registry integration tests. |

---

## P5 — In-process GGUF

**Deferred** unless product mandates — capabilities endpoint must stay honest ([LLM_INFRASTRUCTURE_AUDIT.md](LLM_INFRASTRUCTURE_AUDIT.md)).

---

## Supporting hygiene (parallel, small)

| ID | Work |
|----|------|
| H.1 | Keep [AUDIT_STRENGTH_ITEMS.md](AUDIT_STRENGTH_ITEMS.md) aligned with CI (benchmark gate, Tier A verifier). |
| H.2 | After each P0 increment, update [CHANGELOG.md](../CHANGELOG.md) and [AZL_DOCUMENTATION_CANON.md](AZL_DOCUMENTATION_CANON.md) §3. |

---

## Related

- [PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md) — phased narrative  
- [PROJECT_COMPLETION_STATEMENT.md](PROJECT_COMPLETION_STATEMENT.md) — Tier A vs B  
- [AZL_DOCUMENTATION_CANON.md](AZL_DOCUMENTATION_CANON.md) — shipped vs open  
