# AZL Language — Documentation index

**Canonical record of what is shipped and verified, plus a full map of all docs:** [AZL_DOCUMENTATION_CANON.md](AZL_DOCUMENTATION_CANON.md) (replaces former `WORK_QUEUE.md`, `STATUS.md`, and `AZL_STRENGTH_BAR.md`).

Single entry point for **accurate** project docs. Older “status report”, “supervisor”, and duplicate ecosystem summaries were removed as misleading; use **git history** if you need a retired filename.

## Start here (operations)

| Document | Use |
|----------|-----|
| [AI_MAINTAINER_CONTINUITY_HANDOFF.md](AI_MAINTAINER_CONTINUITY_HANDOFF.md) | **New session:** long-discussion context; anti-loop; reality vs aspiration (humans + AI) |
| [AZL_STRATEGIC_CONSENSUS_AND_EXECUTION_PLAN.md](AZL_STRATEGIC_CONSENSUS_AND_EXECUTION_PLAN.md) | **Consensus + phased plan** (native/AOT, compression policy, wedges) |
| [AZL_LITERAL_CODEC_CONTAINER_V0.md](AZL_LITERAL_CODEC_CONTAINER_V0.md) | **Literal container v0** (Exact tier bytes + CRC); doc contract in CI |
| [../AGENTS.md](../AGENTS.md) | **Agent entry** — read order for assistants |
| [AZL_DOCUMENTATION_CANON.md](AZL_DOCUMENTATION_CANON.md) | **Shipped work, strength bar, work-queue completion, doc map, open milestones** |
| [../README.md](../README.md) | Clone, quick start, native mode |
| [../OPERATIONS.md](../OPERATIONS.md) | Runbook: daemons, sysproxy, tests |
| [../RELEASE_READY.md](../RELEASE_READY.md) | **Release gate order** before shipping native profile |
| [AZL_NATIVE_RUNTIME_CONTRACT.md](AZL_NATIVE_RUNTIME_CONTRACT.md) | Native HTTP/runtime behavior contract |
| [RUNTIME_SPINE_DECISION.md](RUNTIME_SPINE_DECISION.md) | **Spine source of truth:** C engine vs AZL interpreter (current vs target, P0–P5) |

## Roadmap and audits (planning)

| Document | Use |
|----------|-----|
| [PROJECT_COMPLETION_STATEMENT.md](PROJECT_COMPLETION_STATEMENT.md) | **Tier A vs B:** when you may say “complete” (`verify_native_release_profile_complete.sh`) |
| [TIER_B_BACKLOG.md](TIER_B_BACKLOG.md) | **Tier B** sprint queue (P0–P5 + hygiene) after Tier A |
| [PROJECT_COMPLETION_ROADMAP.md](PROJECT_COMPLETION_ROADMAP.md) | Phased completion vs contract (P0 executor gap, P1–P5) |
| [AZL_PERFECTION_PLAN.md](AZL_PERFECTION_PLAN.md) | Strategic gaps and phased goals |
| [CANONICAL_HTTP_PROFILE.md](CANONICAL_HTTP_PROFILE.md) | C native engine vs enterprise `http_server` — pick per deployment |
| [AZL_GPU_NEURAL_SURFACE_MAP.md](AZL_GPU_NEURAL_SURFACE_MAP.md) | **RepertoireField** (§0) + GPU / neural / LHA3 / legacy `azl/quantum/` file map; `scripts/audit_gpu_neural_quantum_surfaces.sh`; **`scripts/verify_repertoire_field_surface_contract.sh`** (**`REPERTOIREFIELD_SURFACE_CONTRACT_V1`**) |
| [AZL_BCBA_NAMING_FRAME.md](AZL_BCBA_NAMING_FRAME.md) | BCBA-led product language: ABA for human-like AI learning; naming options for memory + whole-picture reasoning |
| [AZL_ENGINEERING_REALITY_AUDIT.md](AZL_ENGINEERING_REALITY_AUDIT.md) | Engineering reality vs your vision (LHA3, RepertoireField/`quantum`, crypto demo, Rust, speed) |
| [INTEGRATION_VERIFY.md](INTEGRATION_VERIFY.md) | **`make verify`** — full integration check; **doc trust:** **`release/doc_verification_pieces.json`**, **`make verify-doc-pieces`**, promoted pieces = step **0** of verify |
| [RELATED_WORKSPACES.md](RELATED_WORKSPACES.md) | **Rust / weights / finetune paths** outside the repo; **`RUST_OFFTREE_CONTRACT_V1`** + **`scripts/verify_rust_offtree_doc_contract.sh`** |
| [BENCHMARKS_AZL_VS_REAL_WORLD.md](BENCHMARKS_AZL_VS_REAL_WORLD.md) | **Plain English:** full AZL vs “languages on charts”; **`make benchmark-azl-full-report`** |
| [BENCHMARKS_REAL_WORLD.md](BENCHMARKS_REAL_WORLD.md) | **Industry reference:** Benchmarks Game **spectral-norm** (C vs Python) + **hyperfine** — `make benchmark-real-world` |
| [LLM_INFRASTRUCTURE_AUDIT.md](LLM_INFRASTRUCTURE_AUDIT.md) | LLM / HTTP / proxy stack; **`GET /api/llm/capabilities`**; benches |
| [NATIVE_LLM_INDEPENDENCE_CODE_AUDIT.md](NATIVE_LLM_INDEPENDENCE_CODE_AUDIT.md) | Code-derived gaps: in-process GGUF vs Ollama / `llama-cli` / pure `.azl` |
| [INTEGRATIONS_HOST_VS_NATIVE.md](INTEGRATIONS_HOST_VS_NATIVE.md) | AnythingLLM / `azl/integrations`: pure AZL vs host-shaped reference |
| [AUDIT_STRENGTH_ITEMS.md](AUDIT_STRENGTH_ITEMS.md) | Focused strength / risk audit (HAVE vs NEED) |

## Language (syntax and rules)

| Document | Use |
|----------|-----|
| [language/AZL_CURRENT_SPECIFICATION.md](language/AZL_CURRENT_SPECIFICATION.md) | **Implemented** behavior |
| [language/AZL_LANGUAGE_RULES.md](language/AZL_LANGUAGE_RULES.md) | AZL identity (not Java/TS) |
| [language/GRAMMAR.md](language/GRAMMAR.md) | Grammar; parser lives in `azl/core/parser/` |

Broader / historical spec draft: [../azl/docs/AZL_LANGUAGE_SPECIFICATION.md](../azl/docs/AZL_LANGUAGE_SPECIFICATION.md) (vision; prefer `AZL_CURRENT_SPECIFICATION` for truth).

## Architecture and APIs

| Document | Use |
|----------|-----|
| [ARCHITECTURE_OVERVIEW.md](ARCHITECTURE_OVERVIEW.md) | System shape |
| [ERROR_SYSTEM.md](ERROR_SYSTEM.md) | Error handling |
| [stdlib.md](stdlib.md) | Standard library |
| [VIRTUAL_OS_API.md](VIRTUAL_OS_API.md) | Virtual OS / syscalls |
| [STRICT_MODE_AND_FEATURE_FLAGS.md](STRICT_MODE_AND_FEATURE_FLAGS.md) | Flags and strict mode |
| [LHA3_STDLIB_API.md](LHA3_STDLIB_API.md) | LHA3 memory API surface |
| [LHA3_COMPRESSION_HONESTY.md](LHA3_COMPRESSION_HONESTY.md) | **Honesty contract:** LHA3 **compress** events = heuristic retention, **not** byte codecs; CI via **`verify_lha3_compression_honesty_contract.sh`** |
| [API_REFERENCE.md](API_REFERENCE.md) | API-style reference (where maintained) |

## CI/CD and contributing

| Document | Use |
|----------|-----|
| [CI_CD_PIPELINE.md](CI_CD_PIPELINE.md) | GitHub Actions overview |
| [GITHUB_BRANCH_PROTECTION.md](GITHUB_BRANCH_PROTECTION.md) | **`release/ci/required_github_status_checks.json`** + CI contract; **`make branch-protection-*`** |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute |
| [OBSERVABILITY.md](OBSERVABILITY.md) | Logs / metrics hooks |

Workflows live under `.github/workflows/` — **`test-and-deploy.yml`** is **canonical** for PR/push to **`main`**/**`master`** (repo guards, **`run_all_tests.sh`**, **`perf_smoke`**, AZME E2E, native matrix, benchmarks, coverage, Docker → GHCR, optional staging). **`ci.yml`** / **`native-release-gates.yml`** are **`workflow_dispatch` only**; **`azl-ci.yml`** covers all branches; **`nightly.yml`** runs native gates then sysproxy E2E. Details: [CI_CD_PIPELINE.md](CI_CD_PIPELINE.md).

**Native gates** (`scripts/check_azl_native_gates.sh`) start with **gate 0** (`self_check_release_helpers.sh`: **`rg`**, **`jq`**, release script **`bash -n`**, tag policy, **`release/native/manifest.json`** paths), then **F3** (P0 interpreter slice C↔Python), **F4** (nested **`listen`** in listener + **`emit`** queue flush, `p0_nested_listen_emit_chain.azl`), **F5** (`p0_semantic_var_alias.azl` — **`set ::dst = ::src`**), **F6** (`p0_semantic_expr_plus_chain.azl` — **`+`** / **`==`** on sums), **F7** (`p0_semantic_dotted_counter.azl` — **`::a.b.c`** keys), **F8** (`p0_semantic_behavior_interpret_listen.azl` — **`behavior` / `listen` / `emit interpret`**), **F9** (`p0_semantic_behavior_listen_then.azl` — **`listen … then`**; stdout mismatch exit **59**, not live-verify **69**), **F10** (`p0_semantic_emit_event_payload.azl` — **`emit … with { … }`** → **`::event.data.<key>`** for the listener body), **F11** (`p0_semantic_emit_multi_payload.azl` — comma-separated multi-key **`with`** payload), **F12** (`p0_semantic_emit_queued_payloads.azl` — two **`emit … with`** per **`init`**), **F13** (`p0_semantic_payload_expr_chain.azl` — **`::event.data.*`** in **`set`** **`+`** RHS), **F14** (`p0_semantic_payload_if_branch.azl` — **`if`** on **`::event.data.*`** in listener), **F15** (`p0_semantic_nested_emit_payload.azl`), **F16** (`p0_semantic_quoted_emit_with_payload.azl`), **F17** (`p0_semantic_payload_ne_branch.azl`), **F18** (`p0_semantic_payload_or_fallback.azl`), **F19** (`p0_semantic_emit_empty_with.azl`), **F20** (`p0_semantic_payload_single_quote.azl`), **F21** (`p0_semantic_payload_key_collide.azl` — shared **`trace`** key outer/inner), **F22** (`p0_semantic_nested_listen_emit_payload.azl` — nested **`listen`** + **`emit with`**), **F23** (`p0_semantic_nested_listen_then_payload.azl`), **F24** (`p0_semantic_payload_numeric_value.azl`), **F25** (`p0_semantic_link_in_listener.azl`), **F26** (`p0_semantic_payload_bool_true.azl`), **F27** (`p0_semantic_nested_multikey_payload.azl`), **F28** (`p0_semantic_payload_bool_false.azl`), **F29** (`p0_semantic_payload_null_value.azl`), **F30** (`p0_semantic_first_matching_listener.azl`), **F31** (`p0_semantic_payload_float_value.azl`), **F32** (`p0_semantic_payload_missing_eq_null.azl`), **F33** (`p0_semantic_payload_big_int.azl`), **F34** (`p0_semantic_set_from_payload.azl`), **F35** (`p0_semantic_payload_present_ne_null.azl`), **F36** (`p0_semantic_payload_quoted_negative.azl`), **F37** (`p0_semantic_emit_from_listener_chain.azl`), **F38** (`p0_semantic_payload_trailing_colon_key.azl`), **F39** (`p0_semantic_if_true_literal_listener.azl`), **F40** (`p0_semantic_if_false_literal_listener.azl`), **F41** (`p0_semantic_listen_in_init_emit.azl`), **F42** (`p0_semantic_payload_squote_space.azl`), **F43** (`p0_semantic_sequential_payload_events.azl`), **F44** (`p0_semantic_if_one_literal_listener.azl`), **F45** (`p0_semantic_emit_quoted_event_only.azl`), **F46** (`p0_semantic_say_unset_blank_line.azl`), **F47** (`p0_semantic_if_global_from_payload.azl`), **F48** (`p0_semantic_if_zero_literal_listener.azl`), **F49** (`p0_semantic_emit_unquoted_event_only.azl`), **F50** (`p0_semantic_say_empty_string_global.azl`), **F51** (`p0_semantic_if_string_false_from_payload.azl`), **F52** (`p0_semantic_if_var_true_string.azl`), **F53** (`p0_semantic_same_event_twice_payload.azl`), **F54** (`p0_semantic_listen_in_boot_entry.azl`), **F55** (`p0_semantic_if_var_one_string.azl`), **F56** (`p0_semantic_if_var_zero_string.azl`), **F57** (`p0_semantic_if_var_empty_string.azl`), **F58** (`p0_semantic_cross_component_first_listener.azl`), **F59** (`p0_semantic_double_emit_same_event.azl`), **F60** (`p0_semantic_if_or_empty_then_one_string.azl`), **F61** (`p0_semantic_if_global_eq_globals.azl`), **F62** (`p0_semantic_if_global_ne_globals.azl`), **F63** (`p0_semantic_if_global_ne_equal_skip.azl`), **F64** (`p0_semantic_set_global_concat_globals.azl`), **F65** (`p0_semantic_if_literal_eq_strings.azl`), **F66** (`p0_semantic_if_literal_ne_strings.azl`), **F67** (`p0_semantic_set_triple_concat_mixed.azl`), **F68** (`p0_semantic_return_in_listener_if.azl` — **`return`** inside **`if`** in listener), **F69** (`p0_semantic_for_split_line_loop.azl` — **`::src.split("delim")`** + **`for ::var in ::lines`** in listener), **F70** (`p0_semantic_dot_length_global.azl` — **`::var.length`** in **`if`**), **F71** (`p0_semantic_split_chars_for.azl` — **`split_chars()`** + **`for ::c`**), **F72** (`p0_semantic_push_string_listener.azl` — **`set ::buf.push`** + **`for ::row`**), **F73** (`p0_semantic_int_sub_column_length.azl` — **`::column - ::var.length`**), **F74** (`p0_semantic_tokenize_in_string_char.azl` — **`in_string`** / quote path + **`::handled`**), **F75** (`p0_semantic_tokens_push_tz_concat.azl` — **`tz|…`** **`.push`** + **`::acc.concat`**), **F76** (`p0_semantic_tokenize_line_inc_concat.azl` — **`::line + 1`**, **`::current + ::c`**), **F77** (`p0_semantic_tokenize_outer_line_loop.azl` — **`split("\\n")`** + **`for ::line_text`** + **`concat`** + eol **`push`**), **F78** (`p0_semantic_say_double_interpolate.azl` — double-quoted **`say`** **`::`** / **`.length`**; single quotes literal), **F79** (`p0_semantic_emit_payload_var_bind.azl` — **`emit with { k: ::var }`** resolved at emit), **F80** (`p0_semantic_tokenize_cache_miss_branch.azl` — **`if (::cached_tok != null)`** + **`tok_misses`** on miss), **F81** (`p0_semantic_tokenize_cache_hit_branch.azl` — cache hit: **`tok_hits + 1`**, **`set ::tokens = ::cached_tok`**, **`return`**), **F82** (`p0_semantic_tokenize_cache_hit_emit_complete.azl` — hit path + **`emit tokenize_complete`** + **`::event.data.tokens`**), **F83** (`p0_semantic_parse_cache_miss_branch.azl` — **`::tokens`** from payload + **`ast_misses`**), **F84** (`p0_semantic_parse_cache_hit_branch.azl` — parse cache hit + **`::ast`**), **F85** (`p0_semantic_parse_cache_hit_emit_complete.azl` — **`emit parse_complete`** + **`::event.data.ast`**), **F86** (`p0_semantic_execute_payload_emit_complete.azl` — **`execute_complete`** + **`::event.data.ast`/`scope`**), **F87** (`p0_semantic_execute_use_vm_env_off.azl` — **`::internal.env("AZL_USE_VM")`**, gate unsets env), **F88** (`p0_semantic_halt_execution_listener.azl` — **`emit halt_execution`** → **`listen for "halt_execution"`**, **`::halted`**), **F89** (`p0_semantic_execute_ast_nodes_preloop.azl` — **`::ast != null && ::ast.nodes != null`**, **`for ::n in ::ast.nodes`**, **`execute_complete`**), **F90** (`p0_semantic_execute_vm_path_ok.azl` — **`AZL_USE_VM=1`**, **`::vm_compile_ast`** + **`::vm_run_bytecode_program`**, ok path), **F91** (`p0_semantic_execute_vm_compile_error.azl` — compile-fail **`F91_VM_BAD`**), **F92** (`p0_semantic_execute_vm_empty_bytecode.azl` — empty bytecode **`F92_VM_EMPTY`**), **F93** (`p0_semantic_execute_ast_tree_walk.azl` — **`::execute_ast(::ast, ::scope)`**, **`say|…`** in **`::ast.nodes`**, **`AZL_USE_VM` unset**), **F94** (`p0_semantic_execute_ast_emit_step.azl` — **`emit|…`** inside **`execute_ast`**, listener drain), **F95**–**F129** (`p0_semantic_execute_ast_*.azl` — **`set|`** / **`emit|…|with|…`** / **`import|/`link|`** preloop / **`memory|…`** / **`component|`** + **`memory|emit|…|with|…`** (incl. **two** / **three** rows between **`component|`**) + **bare** **`memory|emit|…`** between **`component|`** / **multi-`component|`** + **`memory|say|…`** interleave; tail fixture **`p0_semantic_execute_ast_preloop_component_memory_bare_emit_component_say.azl`**), **G2** (`verify_semantic_spine_owner_contract.sh` — semantic spine must stay Python **`minimal_runtime`**, not C), **H** (`verify_p0_interpreter_tokenizer_boundary.sh` on `azl_interpreter.azl`). **Exit codes:** [ERROR_SYSTEM.md](ERROR_SYSTEM.md) § Native gates / Shell helpers. **Strength bar:** `scripts/verify_azl_strength_bar.sh` — see [AZL_DOCUMENTATION_CANON.md](AZL_DOCUMENTATION_CANON.md) §1.7. **Full tree:** `scripts/run_full_repo_verification.sh` (step **3:** **`verify_azl_interpreter_semantic_spine_smoke.sh`** — real **`azl_interpreter.azl`** **`init`** on Python spine, P0.1b). **P0 slice smoke:** `scripts/run_semantic_interpreter_slice.sh`. **Product LLM benches:** `scripts/run_product_benchmark_suite.sh` (see `RELEASE_READY.md`).

**`scripts/test_azl_use_vm_path.sh`** (from `run_all_tests.sh`) checks `AZL_USE_VM` docs + wiring, **source-level parity** between `vm_run_bytecode_program` and tree-walker say/emit (`check_azl_vm_tree_parity.py`), and the eligible fixture `azl/tests/fixtures/vm_parity_minimal.azl`.

**LSP:** `tools/azl_lsp.py` provides diagnostics and **`textDocument/definition`** (jump to `component ::…`, matching `emit`/`listen` sites, `fn` / `function`). Integration tests: `scripts/verify_lsp_smoke.sh`, `scripts/test_lsp_jump_to_def.sh` (fixture `azl/tests/lsp_definition_resolution.azl`).

## Packages, training, runbooks

| Document | Use |
|----------|-----|
| [AZLPACK_SPEC.md](AZLPACK_SPEC.md) | Package format; first-party dogfood pack `packages/src/azl-hello/` |
| [TRAIN_IN_PURE_AZL.md](TRAIN_IN_PURE_AZL.md) | Training in AZL |
| [AZME_PRODUCTION_RUNBOOK.md](AZME_PRODUCTION_RUNBOOK.md) | AZME operations (theoretical / verify before use) |
| [../project/entries/docs/README_PREPARE_AZME_TRAINING.md](../project/entries/docs/README_PREPARE_AZME_TRAINING.md) | Prepare AZME training env |
| [../project/entries/docs/AZL_AZME_TRAINING_GUIDE.md](../project/entries/docs/AZL_AZME_TRAINING_GUIDE.md) | AZL/AZME training guide |
| [../project/entries/docs/AZME_USAGE_GUIDE.md](../project/entries/docs/AZME_USAGE_GUIDE.md) | AZME ask/spawn usage examples |

## Experimental / future-only

| Document | Use |
|----------|-----|
| [advanced_features.md](advanced_features.md) | **Not implemented** — theoretical features only |

## Other

| Document | Use |
|----------|-----|
| [CODEGEN.md](CODEGEN.md) | Code generation notes |
| [AZL_LSP_SETUP.md](AZL_LSP_SETUP.md) | LSP: diagnostics + go to definition |
| [STRICT_AZL_GRAMMAR_CONFORMANCE_CHECKLIST.md](STRICT_AZL_GRAMMAR_CONFORMANCE_CHECKLIST.md) | Grammar conformance |
| [reflection_flow.md](reflection_flow.md) | Reflection flow |
| [ENTERPRISE_BUILD_SYSTEM.md](ENTERPRISE_BUILD_SYSTEM.md) | Enterprise build daemon (includes quick start; former `AZL_ENTERPRISE_SETUP.md` merged here) |

`azl/docs/README.md` describes layout under `azl/` and links back here.

**Full alphabetical / categorical list:** [AZL_DOCUMENTATION_CANON.md](AZL_DOCUMENTATION_CANON.md) §4.
