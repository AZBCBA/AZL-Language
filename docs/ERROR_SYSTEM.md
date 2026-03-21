## Error System (Production, Mandatory)

### Goals
- Zero panics in strict mode; all failure modes represented as typed errors
- Rich diagnostics: spans, categories, causes, and call stacks
- Clear recovery policies; fail-fast only for unrecoverable conditions

### Taxonomy
- Parse: invalid tokens, unexpected constructs, unterminated strings
- Type: invalid coercions, arity mismatches, unsupported operations
- Runtime: out-of-bounds, undefined vars, division by zero, timeouts
- Compilation: IR/bytecode generation failures, symbol resolution
- IO/Network: filesystem, network errors, external process failures
- Other: explicitly categorized if none of the above apply
 - Timeout: listener/component timeouts
 - Cycle: event chain cycle detection
 - FFI: cross-language/bridge errors

### Structure
- Pure AZL interpreter: records `{ kind, message, context }` in `::errors` and emits `log_error`. Event cycle/recursion guards return safe statuses and log.
- (Historical) Rust `AzlError` variants existed; treat as legacy. The pure runtime uses AZL-level structures.

### Practices
- Always attach spans where an error originates and where it is observed
- Preserve causes (`source`) for chained errors
- Log with structured fields (component, operation, span, error_kind)
- In events and FFI, never swallow errors; propagate or convert with fidelity
 - Current implementation: new variants (`Timeout`, `Cycle`, `Ffi`) are available and used by runtime; span/call-context propagation is planned during interpreter/VM work. *[VERIFIED: Error variants implemented in src/error.rs:88-96 with proper thiserror integration; helper methods at lines 138-148]*

### Recovery Policies
- Parser: continue to next statement boundary; accumulate diagnostics
- Interpreter: continue unless state would be corrupted; otherwise abort current component with precise error
- EventBus: recursion guard, timeout; log and drop offending event if exceeded; report summary

### Quality Gates
- No `placeholder|TODO|FIXME` in `.azl` sources committed to main.
- Event recursion/cycle detection must be active by default.
- I/O and HTTP in pure mode must route through virtual OS stores.
- **Documentation pieces:** **`release/doc_verification_pieces.json`** is enforced by **`scripts/verify_documentation_pieces.sh`**; **`--promoted-only`** runs at the start of **`run_full_repo_verification.sh`** (**`make verify`**). See **`docs/INTEGRATION_VERIFY.md`**. Promoted pieces include **`bash -n`** on **`scripts/verify_azl_interpreter_semantic_spine_smoke.sh`** (P0.1b release step; doc anchor **`docs/ERROR_SYSTEM.md`** § *Real interpreter source on semantic spine*).
- **GitHub Actions:** PR/push to **`main`**/**`master`** is gated by **`test-and-deploy.yml`**; **`main`** branch protection requires **eight** of those jobs ( **`release/ci/required_github_status_checks.json`** + **`docs/GITHUB_BRANCH_PROTECTION.md`** ). CI runs **`verify_required_github_status_checks_contract.sh`** so renames cannot drift silently. Failing steps surface **`ERROR:`** / numeric exits — no silent green. **`ci.yml`** and **`native-release-gates.yml`** are **`workflow_dispatch` only**. **`nightly.yml`** runs **`check_azl_native_gates.sh`** then sysproxy E2E. Full matrix: **`docs/CI_CD_PIPELINE.md`**.

### Shell helpers (release + live verify)

Production scripts return **non-zero** with **`ERROR:`** on **stderr**; no silent fallback.

| Script | Exit | Meaning |
|--------|------|---------|
| `scripts/self_check_release_helpers.sh` | **40** | **`rg`** not found |
| | **41** | Expected release helper file missing |
| | **42** | **`bash -n`** failed on a helper script |
| | **43** | **`azl_release_tag_policy.sh`** direct run did not exit **2** |
| | **44** | Direct-run **ERROR** message contract broken |
| | **45** | Valid tag **`v1.2.3`** rejected by policy |
| | **46** | Invalid tag assert did not exit **87** |
| | **47** | **`gh_verify_remote_tag.sh`** no-arg exit not **2** |
| | **48** | **`gh_verify_remote_tag.sh`** usage text missing |
| | **49** | **`jq`** not found |
| | **50** | **`release/native/manifest.json`** unreadable or invalid JSON |
| | **51** | **`gates[]`** entry not a non-empty string |
| | **57** | **`gates[]`** path not a file on disk |
| | **52** | **`github_release`** not an object |
| | **53** | **`github_release.workflow`** missing or not a non-empty string |
| | **54** | **`github_release.workflow`** file missing on disk |
| | **55** | **`github_release.scripts`** not an array |
| | **56** | **`github_release.scripts`** entry not a non-empty string |
| | **58** | **`github_release.scripts`** path not a file on disk |
| `scripts/azl_release_tag_policy.sh` | **2** | Run directly — **source** from release scripts only |
| `scripts/gh_verify_remote_tag.sh` | **2** | Usage: missing **`<tag>`** argument |
| | **3** | **`GITHUB_REPOSITORY`** unset |
| | **4** | **`GH_TOKEN`** unset |
| | **5** | **`gh`** or **`jq`** not found |
| | **6** | Tag shape invalid (see **`scripts/azl_release_tag_policy.sh`**) |
| | **7** | **`refs/tags/<tag>`** not found on remote (**`gh api`** failed) |
| | **9** | **`jq @uri`** encoding failed for **`refs/tags/<tag>`** |
| `scripts/gh_create_sample_release.sh` | **2** | **`gh`** not found |
| | **3** | **`GITHUB_REPOSITORY`** or **`GH_TOKEN`** unset; or **`GITHUB_REF`** unset when **`AZL_RELEASE_TAG`** unset |
| | **4** | **`GITHUB_REF`** not **`refs/tags/v*.*.*`** and **`AZL_RELEASE_TAG`** unset |
| | **5** | Tag does not match **`vMAJOR.MINOR.PATCH`** (+ optional **`-prerelease`** / **`+build`**) — **`azl_release_tag_policy.sh`** |
| | **6** | Missing file under **`dist/`** |
| | **7** | GitHub Release already exists for that tag |
| | **8** | **`gh release create`** failed |
| `scripts/verify_native_runtime_live.sh` | **69** | **`AZL_NATIVE_ENGINE_BIN`** set but file missing or not executable |
| | **70** | Engine did not reach **`/healthz`** + **`/readyz`** HTTP **200** in time |
| | **71** | **`/healthz`**, **`/readyz`**, **`/status`**, or **`/api/exec_state`** contract failed |
| | **72** | Native-only **`scripts/azl run`** not blocked (**rc ≠ 64**) |
| | **74** | **`/api/llm/capabilities`** not **`ok`** |
| | **75** | Capabilities missing **`ollama_http_proxy`** |
| | **76** | Invalid **`gguf_in_process`** shape |
| | **77** | Capabilities stub/embedded contract mismatch |
| `scripts/verify_enterprise_native_http_live.sh` | **80** | **`healthz` + `readyz`** not HTTP **200** within deadline |
| | **81** | **`healthz` / `readyz` / `status` / `exec_state`** contract failed |
| | **82** | **`healthz`** missing enterprise entry hint (**`build.daemon.enterprise`**) |
| | **83** | Could not parse **`combined`** path from **`/status`** |
| | **84** | **`/status` `combined`** path mismatch vs built enterprise combined |
| | **85** | **`/api/llm/capabilities`** not **`ok`** |
| | **86** | Capabilities missing **`ollama_http_proxy`** |
| | **87** | Stub/embedded capabilities contract mismatch (**`ERR_*` / `error:null`**) |
| | **88** | Embedded **`gguf`** shape invalid or **`gguf_in_process`** boolean missing |

### LHA3 compression honesty contract (`scripts/verify_lha3_compression_honesty_contract.sh`)

Runs **before** the native stack inside **`scripts/verify_quantum_lha3_stack.sh`**. Ensures **`docs/LHA3_COMPRESSION_HONESTY.md`** exists with contract anchor **`LHA3_COMPRESSION_HONESTY_CONTRACT_V1`**, and **`LHA3_COMPRESSION_MODEL=heuristic_retention`** markers remain in **`azl/quantum/memory/lha3_quantum_engine.azl`** and **`azl/memory/lha3_quantum_memory.azl`**. Prefix **`ERROR[LHA3_COMPRESSION_HONESTY]:`** on stderr.

| Exit | Meaning |
|------|---------|
| **220** | Not repository root |
| **221** | **`docs/LHA3_COMPRESSION_HONESTY.md`** missing |
| **222** | Contract anchor **`LHA3_COMPRESSION_HONESTY_CONTRACT_V1`** missing from honesty doc |
| **223** | Marker missing in **`lha3_quantum_engine.azl`** |
| **224** | Marker missing in **`lha3_quantum_memory.azl`** |
| **225** | **`rg`** not found |

### AZL literal codec container — doc contract (`scripts/verify_azl_literal_codec_container_doc_contract.sh`)

Runs in **`scripts/run_tests.sh`**. Ensures **`docs/AZL_LITERAL_CODEC_CONTAINER_V0.md`** exists with anchor **`AZL_LITERAL_CODEC_CONTAINER_CONTRACT_V1`** and required normative section headings (wire format, decoder algorithm, error identifiers). **Does not** run compress/decompress — that is **future** harness work. Prefix **`ERROR[AZL_LITERAL_CODEC_CONTAINER_DOC]:`** on stderr.

| Exit | Meaning |
|------|---------|
| **250** | Not repository root |
| **251** | **`docs/AZL_LITERAL_CODEC_CONTAINER_V0.md`** missing |
| **252** | Contract anchor **`AZL_LITERAL_CODEC_CONTAINER_CONTRACT_V1`** missing |
| **253** | **`rg`** not found |
| **254** | Required section heading missing from spec doc |

Semantic **`CODEC_*`** identifiers for **runtime decoders** are defined in **`docs/AZL_LITERAL_CODEC_CONTAINER_V0.md`** §6.

### AZL literal codec round-trip harness (`scripts/verify_azl_literal_codec_roundtrip.sh`)

Runs in **`scripts/run_tests.sh`**. **`PYTHONPATH=tools`** **`python3 -m azl_literal_codec.roundtrip_verify`** — identity **`codec_id=0`** encode/decode corpus, CRC tamper, bad magic, truncation, bad **`format_version`**. Prefix **`ERROR[AZL_LITERAL_CODEC_ROUNDTRIP]:`** on stderr.

| Exit | Meaning |
|------|---------|
| **260** | Not repository root |
| **261** | **`python3`** not found |
| **262** | Unexpected failure / assertion mismatch (including unexpected exception) |
| **263** | **`CODEC_TRUNCATED`** |
| **264** | **`CODEC_MAGIC_INVALID`** |
| **265** | **`CODEC_VERSION_UNSUPPORTED`** |
| **266** | **`CODEC_HEADER_INVALID`** |
| **267** | **`CODEC_CRC_MISMATCH`** |
| **268** | **`CODEC_KIND_UNKNOWN`** |
| **269** | **`CODEC_CODEC_UNKNOWN`** |
| **270** | **`CODEC_LENGTH_MISMATCH`** |
| **271** | **`CODEC_DECOMPRESS_FAILED`** (zlib / codec **1** corrupt stream) |

### RepertoireField surface contract (`scripts/verify_repertoire_field_surface_contract.sh`)

Runs at the start of **`scripts/run_tests.sh`**. Ensures **`docs/AZL_GPU_NEURAL_SURFACE_MAP.md`** contains **`REPERTOIREFIELD_SURFACE_CONTRACT_V1`** and **RepertoireField**, and **`azl/quantum/real_quantum_processor.azl`** exists. Prefix **`ERROR[REPERTOIREFIELD_SURFACE]:`** on stderr.

| Exit | Meaning |
|------|---------|
| **230** | Not repository root |
| **231** | GPU surface map doc missing |
| **232** | **`rg`** not found |
| **233** | Contract anchor missing |
| **234** | **RepertoireField** string missing from doc |
| **235** | **`real_quantum_processor.azl`** missing |

### Rust off-tree doc contract (`scripts/verify_rust_offtree_doc_contract.sh`)

Runs at the start of **`scripts/run_tests.sh`**. Ensures **`docs/RELATED_WORKSPACES.md`** contains **`RUST_OFFTREE_CONTRACT_V1`** and **`azme-azl`**. Prefix **`ERROR[RUST_OFFTREE_DOC]:`** on stderr.

| Exit | Meaning |
|------|---------|
| **240** | Related-workspaces doc missing |
| **241** | **`rg`** not found |
| **242** | **`RUST_OFFTREE_CONTRACT_V1`** missing |
| **243** | **`azme-azl`** mention missing |

### Real-world language benchmark (`scripts/benchmark_language_real_world.sh`)

**Optional maintainer benchmark** — not part of **`make verify`**. Runs **[hyperfine](https://github.com/sharkdp/hyperfine)** on **spectral-norm** from the **[Computer Language Benchmarks Game](https://benchmarksgame-team.pages.debian.net/benchmarksgame/)** lineage (**C vs Python**). Requires **`hyperfine`**, **`gcc`**, **`python3`**. Prefix **`ERROR[BENCHMARK_LANGUAGE_REAL_WORLD]:`** on stderr. See **`docs/BENCHMARKS_REAL_WORLD.md`**.

| Exit | Meaning |
|------|---------|
| **300** | Not repository root |
| **301** | **`hyperfine`** not found |
| **302** | **`gcc`** not found |
| **303** | **`python3`** not found |
| **304** | Missing **`benchmarks/real_world/spectralnorm.c`** or **`.py`** |
| **305** | **`gcc`** compile of spectral-norm failed |
| **306** | Empty output from C or Python at verification **N=100** |
| **307** | C vs Python numerical mismatch at **N=100** |

### AZL quality measurement (`scripts/measure_azl_quality_parallel.sh`)

**Optional maintainer metrics** — maps **Python-style quality lenses** (correctness surface, **codebase inventory**, **doc manifest** counts, timings, optional reference C/Python spectral-norm) to **JSON** (**`azl_quality_measurement_v2`**) and a **plain-language Markdown report** (**`*_report.md`**) under **`.azl/benchmarks/`**. Always runs **timed** **`check_azl_native_gates.sh`**; optional **`AZL_MEASURE_COMPREHENSIVE=1`** (doc promoted + reference + perf smoke when runnable), **`AZL_MEASURE_FULL_VERIFY=1`**, **`AZL_MEASURE_REFERENCE=1`**, **`AZL_MEASURE_RUN_ALL_TESTS=1`**. Prefix **`ERROR[BENCHMARK_AZL_QUALITY_PARALLEL]:`** on stderr. See **`docs/AZL_QUALITY_MEASUREMENTS_VS_PYTHON.md`**.

| Exit | Meaning |
|------|---------|
| **320** | Not repository root |
| **321** | **`python3`** not found |
| *(propagated)* | **`check_azl_native_gates.sh`** failure (**JSON still written** before exit) |
| *(propagated)* | **`run_full_repo_verification.sh`** failure when **`AZL_MEASURE_FULL_VERIFY=1`** |
| *(propagated)* | **`benchmark_language_real_world.sh`** failure when **`AZL_MEASURE_REFERENCE=1`** |

### Full AZL coverage report (`scripts/benchmark_azl_full_coverage_report.sh`)

Writes **`.azl/benchmarks/azl_full_coverage_report_*.md`**: promoted doc pieces, **`run_full_repo_verification.sh`** (**`RUN_OPTIONAL_BENCHES=0`**), **`perf_smoke.sh`**, optional **spectral-norm** reference. Prefix **`ERROR[BENCHMARK_AZL_FULL_REPORT]:`** on stderr.

| Exit | Meaning |
|------|---------|
| **310** | Not repository root |
| *(propagated)* | First failing child phase (**doc pieces**, **verify**, **`perf_smoke.sh`**, or reference script) |

### Native gates (`scripts/check_azl_native_gates.sh`)

Semantic parity slices **F5–F87** map to the rows below (**F9** stdout mismatch = **59**, intentionally **not** **`verify_native_runtime_live.sh`** **69**; **F10** = **111–113**; **F11** = **114–116**; **F12** = **117–119**; **F13** = **120–122**; **F14** = **123–125**; **F15** = **126–128**; **F16** = **129–131**; **F17** = **132–134**; **F18** = **135–137**; **F19** = **138–140**; **F20** = **141–143**; **F21** = **144–146**; **F22** = **147–149**; **F23** = **150–152**; **F24** = **153–155**; **F25** = **156–158**; **F26** = **159–161**; **F27** = **162–164**; **F28** = **165–167**; **F29** = **168–170**; **F30** = **171–173**; **F31** = **174–176**; **F32** = **177–179**; **F33** = **180–182**; **F34** = **183–185**; **F35** = **186–188**; **F36** = **189–191**; **F37** = **192–194**; **F38** = **195–197**; **F39** = **198–200**; **F40** = **201–203**; **F41** = **204–206**; **F42** = **207–209**; **F43** = **210–212**; **F44** = **213–215**; **F45** = **216–218**; **F46** = **219–221**; **F47** = **222–224**; **F48** = **225–227**; **F49** = **228–230**; **F50** = **231–233**; **F51** = **234–236**; **F52** = **237–239**; **F53** = **240–242**; **F54** = **243–245**; **F55** = **246–248**; **F56** = **249–251**; **F57** = **252–254**; **F58** = **255–257**; **F59** = **258–260**; **F60** = **261–263**; **F61** = **264–266**; **F62** = **267–269**; **F63** = **270** / **272** / **273** (Python failure uses **272**, not **271** — **271** is **`CODEC_DECOMPRESS_FAILED`** in literal codec harness); **F64** = **274–276**; **F65** = **277–279**; **F66** = **280–282**; **F67** = **283–285**; **F68** = **291–293**; **F69** = **294–296**; **F70** = **297–299**; **F71** = **311–313**; **F72** = **314–316**; **F73** = **317–319**; **F74** = **323–325**; **F75** = **326–328**; **F76** = **329–331**; **F77** = **332–334**; **F78** = **335–337**; **F79** = **338–340**; **F80** = **341–343**; **F81** = **344–346**; **F82** = **347–349**; **F83** = **350–352**; **F84** = **353–355**; **F85** = **356–358**; **F86** = **359–361**; **F87** = **362–364**).

**Gate 0** runs **`self_check_release_helpers.sh`** — its exits **40–58** propagate unchanged.

| Exit | Meaning |
|------|---------|
| **10** | **`start_azl_native_mode.sh`** missing **`AZL_NATIVE_ONLY`** guard |
| **12** | **`verify_native_runtime_live.sh`** not executable |
| **13** | **`verify_quantum_lha3_stack.sh`** not executable |
| **14** | **`verify_azl_grammar_conformance.sh`** not executable |
| **15** | **`verify_azl_literal_codec_container_doc_contract.sh`** not executable |
| **16** | **`verify_enterprise_native_http_live.sh`** not executable |
| **39** | **`verify_azl_literal_codec_roundtrip.sh`** not executable |
| **19** | VM opcode token missing in **`azl/runtime/vm/azl_vm.azl`** |
| **20** | Native engine binary not built or not executable |
| **21** | **`tools/azl_native_engine.c`** not enforcing **`AZL_NATIVE_RUNTIME_CMD`** |
| **22** | Native engine missing **`GET /api/llm/capabilities`** |
| **23** | **`azl-interpreter-minimal`** missing after build |
| **24** | C minimal **`c_minimal_link_ping`** run failed |
| **25** | C minimal output missing **`C_MINIMAL_LINK_PING_OK`** |
| **26** | Python spine host **`c_minimal_link_ping`** run failed |
| **27** | C vs Python **`c_minimal_link_ping`** stdout mismatch |
| **28** | P0 slice C run failed or output missing **`P0_SEMANTIC_INTERPRETER_SLICE_OK`** |
| **29** | Python spine host P0 slice run failed |
| **30** | C vs Python P0 slice stdout mismatch |
| **31** | Script defaults **`AZL_ENABLE_LEGACY_HOST`** to **1** (**forbidden**) |
| **32** | C minimal **`p0_nested_listen_emit_chain`** run failed or output missing marker |
| **33** | Python spine host **`p0_nested_listen_emit_chain`** run failed |
| **34** | C vs Python **`p0_nested_listen_emit_chain`** stdout mismatch |
| **35** | C minimal **`p0_semantic_var_alias`** failed or missing **`P0_SEMANTIC_VAR_ALIAS_OK`** |
| **36** | Python spine host **`p0_semantic_var_alias`** failed |
| **37** | C vs Python **`p0_semantic_var_alias`** stdout mismatch |
| **40** | C minimal **`p0_semantic_expr_plus_chain`** failed or missing **`P0_SEMANTIC_EXPR_PLUS_OK`** |
| **41** | Python spine host **`p0_semantic_expr_plus_chain`** failed |
| **42** | C vs Python **`p0_semantic_expr_plus_chain`** stdout mismatch |
| **59** | C vs Python **`p0_semantic_behavior_listen_then`** stdout mismatch (**F9**; code **59** avoids collision with **`verify_native_runtime_live.sh`** **69**) |
| **61** | C minimal **`p0_semantic_dotted_counter`** failed or missing **`P0_SEMANTIC_DOTTED_COUNTER_OK`** |
| **62** | Python spine host **`p0_semantic_dotted_counter`** failed |
| **63** | C vs Python **`p0_semantic_dotted_counter`** stdout mismatch |
| **64** | C minimal **`p0_semantic_behavior_interpret_listen`** failed or missing **`P0_SEMANTIC_BEHAVIOR_INTERPRET_OK`** |
| **65** | Python spine host **`p0_semantic_behavior_interpret_listen`** failed |
| **66** | C vs Python **`p0_semantic_behavior_interpret_listen`** stdout mismatch |
| **67** | C minimal **`p0_semantic_behavior_listen_then`** failed or missing **`P0_SEMANTIC_LISTEN_THEN_OK`** |
| **68** | Python spine host **`p0_semantic_behavior_listen_then`** failed |
| **111** | C minimal **`p0_semantic_emit_event_payload`** failed, missing **`P0_SEMANTIC_EMIT_PAYLOAD_OK`**, or missing expected payload line (**`spine-f10`**) (**F10**) |
| **112** | Python spine host **`p0_semantic_emit_event_payload`** failed (**F10**) |
| **113** | C vs Python **`p0_semantic_emit_event_payload`** stdout mismatch (**F10**) |
| **114** | C minimal **`p0_semantic_emit_multi_payload`** failed, missing **`P0_SEMANTIC_EMIT_MULTI_OK`**, or missing expected payload lines (**`spine-f11a`** / **`spine-f11b`**) (**F11**) |
| **115** | Python spine host **`p0_semantic_emit_multi_payload`** failed (**F11**) |
| **116** | C vs Python **`p0_semantic_emit_multi_payload`** stdout mismatch (**F11**) |
| **117** | C minimal **`p0_semantic_emit_queued_payloads`** failed or missing expected lines (**`P0_SEMANTIC_EMIT_QUEUED_OK`**, **`spine-f12a`** / **`spine-f12b`**, **`P12_AFTER_*`**) (**F12**) |
| **118** | Python spine host **`p0_semantic_emit_queued_payloads`** failed (**F12**) |
| **119** | C vs Python **`p0_semantic_emit_queued_payloads`** stdout mismatch (**F12**) |
| **120** | C minimal **`p0_semantic_payload_expr_chain`** failed or missing **`P0_SEMANTIC_PAYLOAD_EXPR_OK`** or **`spine-f13-sfx`** (**F13**) |
| **121** | Python spine host **`p0_semantic_payload_expr_chain`** failed (**F13**) |
| **122** | C vs Python **`p0_semantic_payload_expr_chain`** stdout mismatch (**F13**) |
| **123** | C minimal **`p0_semantic_payload_if_branch`** failed or missing **`P0_SEMANTIC_PAYLOAD_IF_OK`** or **`branch-strict`** (**F14**) |
| **124** | Python spine host **`p0_semantic_payload_if_branch`** failed (**F14**) |
| **125** | C vs Python **`p0_semantic_payload_if_branch`** stdout mismatch (**F14**) |
| **126** | C minimal **`p0_semantic_nested_emit_payload`** failed or missing expected lines (**`P0_SEMANTIC_NESTED_EMIT_OK`**, **`nested-val`**, **`hold`**) (**F15**) |
| **127** | Python spine host **`p0_semantic_nested_emit_payload`** failed (**F15**) |
| **128** | C vs Python **`p0_semantic_nested_emit_payload`** stdout mismatch (**F15**) |
| **129** | C minimal **`p0_semantic_quoted_emit_with_payload`** failed or missing **`P0_SEMANTIC_QUOTED_EMIT_OK`** / **`quoted-id`** (**F16**) |
| **130** | Python spine host **`p0_semantic_quoted_emit_with_payload`** failed (**F16**) |
| **131** | C vs Python **`p0_semantic_quoted_emit_with_payload`** stdout mismatch (**F16**) |
| **132** | C minimal **`p0_semantic_payload_ne_branch`** failed or missing **`P0_SEMANTIC_PAYLOAD_NE_OK`** / **`not-loose`** (**F17**) |
| **133** | Python spine host **`p0_semantic_payload_ne_branch`** failed (**F17**) |
| **134** | C vs Python **`p0_semantic_payload_ne_branch`** stdout mismatch (**F17**) |
| **135** | C minimal **`p0_semantic_payload_or_fallback`** failed or missing **`P0_SEMANTIC_PAYLOAD_OR_OK`** / **`fallback`** (**F18**) |
| **136** | Python spine host **`p0_semantic_payload_or_fallback`** failed (**F18**) |
| **137** | C vs Python **`p0_semantic_payload_or_fallback`** stdout mismatch (**F18**) |
| **138** | C minimal **`p0_semantic_emit_empty_with`** failed or missing **`P0_SEMANTIC_EMPTY_WITH_OK`** (**F19**) |
| **139** | Python spine host **`p0_semantic_emit_empty_with`** failed (**F19**) |
| **140** | C vs Python **`p0_semantic_emit_empty_with`** stdout mismatch (**F19**) |
| **141** | C minimal **`p0_semantic_payload_single_quote`** failed or missing **`P0_SEMANTIC_SQUOTE_PAYLOAD_OK`** / **`sq-val`** (**F20**) |
| **142** | Python spine host **`p0_semantic_payload_single_quote`** failed (**F20**) |
| **143** | C vs Python **`p0_semantic_payload_single_quote`** stdout mismatch (**F20**) |
| **144** | C minimal **`p0_semantic_payload_key_collide`** failed or missing **`P0_SEMANTIC_PAYLOAD_KEY_COLLIDE_OK`** / **`outer-val`** / **`inner-val`** (**F21**) |
| **145** | Python spine host **`p0_semantic_payload_key_collide`** failed (**F21**) |
| **146** | C vs Python **`p0_semantic_payload_key_collide`** stdout mismatch (**F21**) |
| **147** | C minimal **`p0_semantic_nested_listen_emit_payload`** failed or missing **`P0_SEMANTIC_NESTED_LISTEN_PAYLOAD_OK`** / **`nested-reg`** / **`P22_CHILD_OK`** (**F22**) |
| **148** | Python spine host **`p0_semantic_nested_listen_emit_payload`** failed (**F22**) |
| **149** | C vs Python **`p0_semantic_nested_listen_emit_payload`** stdout mismatch (**F22**) |
| **150** | C minimal **`p0_semantic_nested_listen_then_payload`** failed or missing **`P0_SEMANTIC_NESTED_LISTEN_THEN_OK`** / **`then-payload`** (**F23**) |
| **151** | Python spine host **`p0_semantic_nested_listen_then_payload`** failed (**F23**) |
| **152** | C vs Python **`p0_semantic_nested_listen_then_payload`** stdout mismatch (**F23**) |
| **153** | C minimal **`p0_semantic_payload_numeric_value`** failed or missing **`P0_SEMANTIC_PAYLOAD_NUM_OK`** / bare **`42`** line (**F24**) |
| **154** | Python spine host **`p0_semantic_payload_numeric_value`** failed (**F24**) |
| **155** | C vs Python **`p0_semantic_payload_numeric_value`** stdout mismatch (**F24**) |
| **156** | C minimal **`p0_semantic_link_in_listener`** failed or missing **`P0_SEMANTIC_LINK_IN_LISTENER_OK`** / **`F25_LINKED_INIT`** / **`F25_H_OK`** (**F25**) |
| **157** | Python spine host **`p0_semantic_link_in_listener`** failed (**F25**) |
| **158** | C vs Python **`p0_semantic_link_in_listener`** stdout mismatch (**F25**) |
| **159** | C minimal **`p0_semantic_payload_bool_true`** failed or missing **`P0_SEMANTIC_PAYLOAD_BOOL_TRUE_OK`** / bare **`true`** line (**F26**) |
| **160** | Python spine host **`p0_semantic_payload_bool_true`** failed (**F26**) |
| **161** | C vs Python **`p0_semantic_payload_bool_true`** stdout mismatch (**F26**) |
| **162** | C minimal **`p0_semantic_nested_multikey_payload`** failed or missing **`P0_SEMANTIC_NESTED_MULTIKEY_OK`** / **`P27_INNER_OK`** / **`one`** / **`two`** lines (**F27**) |
| **163** | Python spine host **`p0_semantic_nested_multikey_payload`** failed (**F27**) |
| **164** | C vs Python **`p0_semantic_nested_multikey_payload`** stdout mismatch (**F27**) |
| **165** | C minimal **`p0_semantic_payload_bool_false`** failed or missing **`P0_SEMANTIC_PAYLOAD_BOOL_FALSE_OK`** / bare **`false`** line (**F28**) |
| **166** | Python spine host **`p0_semantic_payload_bool_false`** failed (**F28**) |
| **167** | C vs Python **`p0_semantic_payload_bool_false`** stdout mismatch (**F28**) |
| **168** | C minimal **`p0_semantic_payload_null_value`** failed or missing **`P0_SEMANTIC_PAYLOAD_NULL_OK`** / bare **`null`** line (**F29**) |
| **169** | Python spine host **`p0_semantic_payload_null_value`** failed (**F29**) |
| **170** | C vs Python **`p0_semantic_payload_null_value`** stdout mismatch (**F29**) |
| **171** | C minimal **`p0_semantic_first_matching_listener`** failed or missing **`P0_SEMANTIC_FIRST_LISTENER_OK`** / **`FIRST`** / spurious **`SECOND`** (**F30**) |
| **172** | Python spine host **`p0_semantic_first_matching_listener`** failed (**F30**) |
| **173** | C vs Python **`p0_semantic_first_matching_listener`** stdout mismatch (**F30**) |
| **174** | C minimal **`p0_semantic_payload_float_value`** failed or missing **`P0_SEMANTIC_PAYLOAD_FLOAT_OK`** / **`3.14`** line (**F31**) |
| **175** | Python spine host **`p0_semantic_payload_float_value`** failed (**F31**) |
| **176** | C vs Python **`p0_semantic_payload_float_value`** stdout mismatch (**F31**) |
| **177** | C minimal **`p0_semantic_payload_missing_eq_null`** failed or missing **`F32_ABSENT_EQ_NULL`** / **`P0_SEMANTIC_PAYLOAD_MISSING_EQ_NULL_OK`** (**F32**) |
| **178** | Python spine host **`p0_semantic_payload_missing_eq_null`** failed (**F32**) |
| **179** | C vs Python **`p0_semantic_payload_missing_eq_null`** stdout mismatch (**F32**) |
| **180** | C minimal **`p0_semantic_payload_big_int`** failed or missing **`P0_SEMANTIC_PAYLOAD_BIG_INT_OK`** / **`65535`** line (**F33**) |
| **181** | Python spine host **`p0_semantic_payload_big_int`** failed (**F33**) |
| **182** | C vs Python **`p0_semantic_payload_big_int`** stdout mismatch (**F33**) |
| **183** | C minimal **`p0_semantic_set_from_payload`** failed or missing **`P0_SEMANTIC_SET_FROM_PAYLOAD_OK`** / **`cloned`** line (**F34**) |
| **184** | Python spine host **`p0_semantic_set_from_payload`** failed (**F34**) |
| **185** | C vs Python **`p0_semantic_set_from_payload`** stdout mismatch (**F34**) |
| **186** | C minimal **`p0_semantic_payload_present_ne_null`** failed or missing **`F35_PRES_NOT_NULL`** / **`P0_SEMANTIC_PAYLOAD_NE_NULL_OK`** (**F35**) |
| **187** | Python spine host **`p0_semantic_payload_present_ne_null`** failed (**F35**) |
| **188** | C vs Python **`p0_semantic_payload_present_ne_null`** stdout mismatch (**F35**) |
| **189** | C minimal **`p0_semantic_payload_quoted_negative`** failed or missing **`P0_SEMANTIC_PAYLOAD_QUOTED_NEG_OK`** / **`-7`** line (**F36**) |
| **190** | Python spine host **`p0_semantic_payload_quoted_negative`** failed (**F36**) |
| **191** | C vs Python **`p0_semantic_payload_quoted_negative`** stdout mismatch (**F36**) |
| **192** | C minimal **`p0_semantic_emit_from_listener_chain`** failed or wrong order / missing **`P37_*`** / **`P0_SEMANTIC_EMIT_FROM_LISTENER_OK`** (**F37**) |
| **193** | Python spine host **`p0_semantic_emit_from_listener_chain`** failed (**F37**) |
| **194** | C vs Python **`p0_semantic_emit_from_listener_chain`** stdout mismatch (**F37**) |
| **195** | C minimal **`p0_semantic_payload_trailing_colon_key`** failed or missing **`P0_SEMANTIC_PAYLOAD_TRAILING_COLON_KEY_OK`** / **`z9`** line (**F38**) |
| **196** | Python spine host **`p0_semantic_payload_trailing_colon_key`** failed (**F38**) |
| **197** | C vs Python **`p0_semantic_payload_trailing_colon_key`** stdout mismatch (**F38**) |
| **198** | C minimal **`p0_semantic_if_true_literal_listener`** failed or missing **`F39_TRUE_BRANCH`** / **`P0_SEMANTIC_IF_TRUE_LITERAL_OK`** (**F39**) |
| **199** | Python spine host **`p0_semantic_if_true_literal_listener`** failed (**F39**) |
| **200** | C vs Python **`p0_semantic_if_true_literal_listener`** stdout mismatch (**F39**) |
| **201** | C minimal **`p0_semantic_if_false_literal_listener`** failed, spurious **`F40_BAD`**, or missing **`P0_SEMANTIC_IF_FALSE_LITERAL_OK`** (**F40**) |
| **202** | Python spine host **`p0_semantic_if_false_literal_listener`** failed (**F40**) |
| **203** | C vs Python **`p0_semantic_if_false_literal_listener`** stdout mismatch (**F40**) |
| **204** | C minimal **`p0_semantic_listen_in_init_emit`** failed or wrong order / missing **`F41_DYN_OK`** / **`P0_SEMANTIC_LISTEN_IN_INIT_OK`** (**F41**) |
| **205** | Python spine host **`p0_semantic_listen_in_init_emit`** failed (**F41**) |
| **206** | C vs Python **`p0_semantic_listen_in_init_emit`** stdout mismatch (**F41**) |
| **207** | C minimal **`p0_semantic_payload_squote_space`** failed or missing **`P0_SEMANTIC_PAYLOAD_SQUOTE_SPACE_OK`** / **`a b`** line (**F42**) |
| **208** | Python spine host **`p0_semantic_payload_squote_space`** failed (**F42**) |
| **209** | C vs Python **`p0_semantic_payload_squote_space`** stdout mismatch (**F42**) |
| **210** | C minimal **`p0_semantic_sequential_payload_events`** failed or wrong order / missing **`P0_SEMANTIC_TWO_EVENTS_TWO_PAYLOADS_OK`** / **`one`** / **`two`** (**F43**) |
| **211** | Python spine host **`p0_semantic_sequential_payload_events`** failed (**F43**) |
| **212** | C vs Python **`p0_semantic_sequential_payload_events`** stdout mismatch (**F43**) |
| **213** | C minimal **`p0_semantic_if_one_literal_listener`** failed or missing **`F44_ONE_BRANCH`** / **`P0_SEMANTIC_IF_ONE_LITERAL_OK`** (**F44**) |
| **214** | Python spine host **`p0_semantic_if_one_literal_listener`** failed (**F44**) |
| **215** | C vs Python **`p0_semantic_if_one_literal_listener`** stdout mismatch (**F44**) |
| **216** | C minimal **`p0_semantic_emit_quoted_event_only`** failed or missing **`F45_QUOTED_EMIT_NO_WITH_OK`** (**F45**) |
| **217** | Python spine host **`p0_semantic_emit_quoted_event_only`** failed (**F45**) |
| **218** | C vs Python **`p0_semantic_emit_quoted_event_only`** stdout mismatch (**F45**) |
| **219** | C minimal **`p0_semantic_say_unset_blank_line`** failed or missing blank first line / **`P0_SEMANTIC_SAY_UNSET_BLANK_OK`** (**F46**) |
| **220** | Python spine host **`p0_semantic_say_unset_blank_line`** failed (**F46**) |
| **221** | C vs Python **`p0_semantic_say_unset_blank_line`** stdout mismatch (**F46**) |
| **222** | C minimal **`p0_semantic_if_global_from_payload`** failed or missing **`F47_FLAG_BRANCH`** / **`P0_SEMANTIC_IF_GLOBAL_FROM_PAYLOAD_OK`** (**F47**) |
| **223** | Python spine host **`p0_semantic_if_global_from_payload`** failed (**F47**) |
| **224** | C vs Python **`p0_semantic_if_global_from_payload`** stdout mismatch (**F47**) |
| **225** | C minimal **`p0_semantic_if_zero_literal_listener`** failed, spurious **`F48_BAD`**, or missing **`P0_SEMANTIC_IF_ZERO_LITERAL_OK`** (**F48**) |
| **226** | Python spine host **`p0_semantic_if_zero_literal_listener`** failed (**F48**) |
| **227** | C vs Python **`p0_semantic_if_zero_literal_listener`** stdout mismatch (**F48**) |
| **228** | C minimal **`p0_semantic_emit_unquoted_event_only`** failed or missing **`F49_UNQUOTED_EMIT_OK`** (**F49**) |
| **229** | Python spine host **`p0_semantic_emit_unquoted_event_only`** failed (**F49**) |
| **230** | C vs Python **`p0_semantic_emit_unquoted_event_only`** stdout mismatch (**F49**) |
| **231** | C minimal **`p0_semantic_say_empty_string_global`** failed or missing blank first line / **`P0_SEMANTIC_SAY_EMPTY_STRING_OK`** (**F50**) |
| **232** | Python spine host **`p0_semantic_say_empty_string_global`** failed (**F50**) |
| **233** | C vs Python **`p0_semantic_say_empty_string_global`** stdout mismatch (**F50**) |
| **234** | C minimal **`p0_semantic_if_string_false_from_payload`** failed, spurious **`F51_BAD`**, or missing **`P0_SEMANTIC_IF_STRING_FALSE_OK`** (**F51**) |
| **235** | Python spine host **`p0_semantic_if_string_false_from_payload`** failed (**F51**) |
| **236** | C vs Python **`p0_semantic_if_string_false_from_payload`** stdout mismatch (**F51**) |
| **237** | C minimal **`p0_semantic_if_var_true_string`** failed or missing **`F52_TRUE_STRING_VAR`** / **`P0_SEMANTIC_IF_VAR_TRUE_STRING_OK`** (**F52**) |
| **238** | Python spine host **`p0_semantic_if_var_true_string`** failed (**F52**) |
| **239** | C vs Python **`p0_semantic_if_var_true_string`** stdout mismatch (**F52**) |
| **240** | C minimal **`p0_semantic_same_event_twice_payload`** failed, wrong stdout order, or missing **`P0_SEMANTIC_SAME_EVENT_TWICE_OK`** (**F53**) |
| **241** | Python spine host **`p0_semantic_same_event_twice_payload`** failed (**F53**) |
| **242** | C vs Python **`p0_semantic_same_event_twice_payload`** stdout mismatch (**F53**) |
| **243** | C minimal **`p0_semantic_listen_in_boot_entry`** failed, wrong stdout order, or missing **`F54_BOOT_LISTEN_OK`** / **`P0_SEMANTIC_LISTEN_IN_BOOT_ENTRY_OK`** (**F54**) |
| **244** | Python spine host **`p0_semantic_listen_in_boot_entry`** failed (**F54**) |
| **245** | C vs Python **`p0_semantic_listen_in_boot_entry`** stdout mismatch (**F54**) |
| **246** | C minimal **`p0_semantic_if_var_one_string`** failed or missing **`F55_ONE_STRING_VAR`** / **`P0_SEMANTIC_IF_VAR_ONE_STRING_OK`** (**F55**) |
| **247** | Python spine host **`p0_semantic_if_var_one_string`** failed (**F55**) |
| **248** | C vs Python **`p0_semantic_if_var_one_string`** stdout mismatch (**F55**) |
| **249** | C minimal **`p0_semantic_if_var_zero_string`** failed, spurious **`F56_BAD`**, or missing **`P0_SEMANTIC_IF_VAR_ZERO_STRING_OK`** (**F56**) |
| **250** | Python spine host **`p0_semantic_if_var_zero_string`** failed (**F56**) |
| **251** | C vs Python **`p0_semantic_if_var_zero_string`** stdout mismatch (**F56**) |
| **252** | C minimal **`p0_semantic_if_var_empty_string`** failed, spurious **`F57_BAD`**, or missing **`P0_SEMANTIC_IF_VAR_EMPTY_STRING_OK`** (**F57**) |
| **253** | Python spine host **`p0_semantic_if_var_empty_string`** failed (**F57**) |
| **254** | C vs Python **`p0_semantic_if_var_empty_string`** stdout mismatch (**F57**) |
| **255** | C minimal **`p0_semantic_cross_component_first_listener`** failed, spurious **`F58_SECOND_BAD`**, wrong stdout order, or missing **`F58_FIRST_LINKED`** / **`P0_SEMANTIC_CROSS_COMP_FIRST_OK`** (**F58**) |
| **256** | Python spine host **`p0_semantic_cross_component_first_listener`** failed (**F58**) |
| **257** | C vs Python **`p0_semantic_cross_component_first_listener`** stdout mismatch (**F58**) |
| **258** | C minimal **`p0_semantic_double_emit_same_event`** failed, wrong stdout order, or missing **`P0_SEMANTIC_DOUBLE_EMIT_SAME_OK`** (**F59**) |
| **259** | Python spine host **`p0_semantic_double_emit_same_event`** failed (**F59**) |
| **260** | C vs Python **`p0_semantic_double_emit_same_event`** stdout mismatch (**F59**) |
| **261** | C minimal **`p0_semantic_if_or_empty_then_one_string`** failed or missing **`F60_OR_TRUE_BRANCH`** / **`P0_SEMANTIC_IF_OR_EMPTY_ONE_OK`** (**F60**) |
| **262** | Python spine host **`p0_semantic_if_or_empty_then_one_string`** failed (**F60**) |
| **263** | C vs Python **`p0_semantic_if_or_empty_then_one_string`** stdout mismatch (**F60**) |
| **264** | C minimal **`p0_semantic_if_global_eq_globals`** failed or missing **`F61_EQ_TRUE_BRANCH`** / **`P0_SEMANTIC_IF_GLOBAL_EQ_OK`** (**F61**) |
| **265** | Python spine host **`p0_semantic_if_global_eq_globals`** failed (**F61**) |
| **266** | C vs Python **`p0_semantic_if_global_eq_globals`** stdout mismatch (**F61**) |
| **267** | C minimal **`p0_semantic_if_global_ne_globals`** failed or missing **`F62_NEQ_BRANCH`** / **`P0_SEMANTIC_IF_GLOBAL_NE_OK`** (**F62**) |
| **268** | Python spine host **`p0_semantic_if_global_ne_globals`** failed (**F62**) |
| **269** | C vs Python **`p0_semantic_if_global_ne_globals`** stdout mismatch (**F62**) |
| **270** | C minimal **`p0_semantic_if_global_ne_equal_skip`** failed, spurious **`F63_BAD`**, or missing **`P0_SEMANTIC_IF_GLOBAL_NE_EQUAL_OK`** (**F63**) |
| **272** | Python spine host **`p0_semantic_if_global_ne_equal_skip`** failed (**F63**) |
| **273** | C vs Python **`p0_semantic_if_global_ne_equal_skip`** stdout mismatch (**F63**) |
| **274** | C minimal **`p0_semantic_set_global_concat_globals`** failed, wrong stdout order, or missing **`hello`** / **`P0_SEMANTIC_SET_GLOBAL_CONCAT_OK`** (**F64**) |
| **275** | Python spine host **`p0_semantic_set_global_concat_globals`** failed (**F64**) |
| **276** | C vs Python **`p0_semantic_set_global_concat_globals`** stdout mismatch (**F64**) |
| **277** | C minimal **`p0_semantic_if_literal_eq_strings`** failed or missing **`F65_LITERAL_EQ_BRANCH`** / **`P0_SEMANTIC_IF_LITERAL_EQ_STRINGS_OK`** (**F65**) |
| **278** | Python spine host **`p0_semantic_if_literal_eq_strings`** failed (**F65**) |
| **279** | C vs Python **`p0_semantic_if_literal_eq_strings`** stdout mismatch (**F65**) |
| **280** | C minimal **`p0_semantic_if_literal_ne_strings`** failed or missing **`F66_LITERAL_NE_BRANCH`** / **`P0_SEMANTIC_IF_LITERAL_NE_STRINGS_OK`** (**F66**) |
| **281** | Python spine host **`p0_semantic_if_literal_ne_strings`** failed (**F66**) |
| **282** | C vs Python **`p0_semantic_if_literal_ne_strings`** stdout mismatch (**F66**) |
| **283** | C minimal **`p0_semantic_set_triple_concat_mixed`** failed, wrong stdout order, or missing **`preMIDpost`** / **`P0_SEMANTIC_SET_TRIPLE_CONCAT_OK`** (**F67**) |
| **284** | Python spine host **`p0_semantic_set_triple_concat_mixed`** failed (**F67**) |
| **285** | C vs Python **`p0_semantic_set_triple_concat_mixed`** stdout mismatch (**F67**) |
| **291** | C minimal **`p0_semantic_return_in_listener_if`** failed, wrong stdout order, or missing **`EARLY`** / **`LATE`** / **`P0_SEMANTIC_RETURN_IN_LISTENER_OK`** (**F68**) |
| **292** | Python spine host **`p0_semantic_return_in_listener_if`** failed (**F68**) |
| **293** | C vs Python **`p0_semantic_return_in_listener_if`** stdout mismatch (**F68**) |
| **294** | C minimal **`p0_semantic_for_split_line_loop`** failed, wrong stdout order, or missing **`alpha`** / **`beta`** / **`gamma`** / **`P0_SEMANTIC_FOR_SPLIT_OK`** (**F69**) |
| **295** | Python spine host **`p0_semantic_for_split_line_loop`** failed (**F69**) |
| **296** | C vs Python **`p0_semantic_for_split_line_loop`** stdout mismatch (**F69**) |
| **297** | C minimal **`p0_semantic_dot_length_global`** failed, wrong stdout order, or missing **`ZERO`** / **`TWO`** / **`P0_SEMANTIC_DOT_LENGTH_OK`** (**F70**) |
| **298** | Python spine host **`p0_semantic_dot_length_global`** failed (**F70**) |
| **299** | C vs Python **`p0_semantic_dot_length_global`** stdout mismatch (**F70**) |
| **311** | C minimal **`p0_semantic_split_chars_for`** failed, wrong stdout order, or missing **`a`** / **`b`** / **`P0_SEMANTIC_SPLIT_CHARS_OK`** (**F71**) |
| **312** | Python spine host **`p0_semantic_split_chars_for`** failed (**F71**) |
| **313** | C vs Python **`p0_semantic_split_chars_for`** stdout mismatch (**F71**) |
| **314** | C minimal **`p0_semantic_push_string_listener`** failed, wrong stdout order, or missing **`P0_SEMANTIC_PUSH_INIT_OK`** / **`first`** / **`second`** / **`P0_SEMANTIC_PUSH_STRING_OK`** (**F72**) |
| **315** | Python spine host **`p0_semantic_push_string_listener`** failed (**F72**) |
| **316** | C vs Python **`p0_semantic_push_string_listener`** stdout mismatch (**F72**) |
| **317** | C minimal **`p0_semantic_int_sub_column_length`** failed, wrong stdout order, or missing **`P0_SEMANTIC_INT_SUB_INIT_OK`** / **`3`** / **`P0_SEMANTIC_INT_SUB_OK`** (**F73**) |
| **318** | Python spine host **`p0_semantic_int_sub_column_length`** failed (**F73**) |
| **319** | C vs Python **`p0_semantic_int_sub_column_length`** stdout mismatch (**F73**) |
| **323** | C minimal **`p0_semantic_tokenize_in_string_char`** failed, wrong stdout order, or missing **`P0_SEMANTIC_IN_STRING_INIT_OK`** / **`OUTSIDE`** / **`STRING_START`** / **`b`** / **`STRING_END`** / **`P0_SEMANTIC_IN_STRING_OK`** (**F74**) |
| **324** | Python spine host **`p0_semantic_tokenize_in_string_char`** failed (**F74**) |
| **325** | C vs Python **`p0_semantic_tokenize_in_string_char`** stdout mismatch (**F74**) |
| **326** | C minimal **`p0_semantic_tokens_push_tz_concat`** failed, wrong stdout order, or missing **`P0_SEMANTIC_TOK_TZ_INIT_OK`** / **`tz|eol|;|1|0`** / **`tz|id|x|1|1`** / **`P0_SEMANTIC_TOK_TZ_OK`** (**F75**) |
| **327** | Python spine host **`p0_semantic_tokens_push_tz_concat`** failed (**F75**) |
| **328** | C vs Python **`p0_semantic_tokens_push_tz_concat`** stdout mismatch (**F75**) |
| **329** | C minimal **`p0_semantic_tokenize_line_inc_concat`** failed, wrong stdout order, or missing **`P0_SEMANTIC_TOK_INCR_INIT_OK`** / **`2`** / **`ab`** / **`P0_SEMANTIC_TOK_INCR_OK`** (**F76**) |
| **330** | Python spine host **`p0_semantic_tokenize_line_inc_concat`** failed (**F76**) |
| **331** | C vs Python **`p0_semantic_tokenize_line_inc_concat`** stdout mismatch (**F76**) |
| **332** | C minimal **`p0_semantic_tokenize_outer_line_loop`** failed, wrong stdout order, or missing **`P0_SEMANTIC_TOK_OUTER_INIT_OK`** / **`tz|id|x|1|1`** / **`tz|eol|;|1|0`** / **`tz|id|y|2|1`** / **`tz|eol|;|2|0`** / **`P0_SEMANTIC_TOK_OUTER_OK`** (**F77**) |
| **333** | Python spine host **`p0_semantic_tokenize_outer_line_loop`** failed (**F77**) |
| **334** | C vs Python **`p0_semantic_tokenize_outer_line_loop`** stdout mismatch (**F77**) |
| **335** | C minimal **`p0_semantic_say_double_interpolate`** failed, wrong stdout order, or missing **`P0_SEM_SAY_DIP_INIT`** / **`V=ab`** / **`LEN=2`** / **`DOT=9`** / **`NONE=|Z`** / **`LIT=::msg`** / **`P0_SEM_SAY_DIP_OK`** (**F78**) |
| **336** | Python spine host **`p0_semantic_say_double_interpolate`** failed (**F78**) |
| **337** | C vs Python **`p0_semantic_say_double_interpolate`** stdout mismatch (**F78**) |
| **338** | C minimal **`p0_semantic_emit_payload_var_bind`** failed, wrong stdout order, or missing **`carry-bytes`** / **`P0_SEMANTIC_EMIT_PAYLOAD_VAR_OK`** (**F79**) |
| **339** | Python spine host **`p0_semantic_emit_payload_var_bind`** failed (**F79**) |
| **340** | C vs Python **`p0_semantic_emit_payload_var_bind`** stdout mismatch (**F79**) |
| **341** | C minimal **`p0_semantic_tokenize_cache_miss_branch`** failed, wrong stdout order, or missing **`CACHE_MISS`** / **`1`** / **`P0_SEM_TOK_CACHE_MISS_OK`** (**F80**) |
| **342** | Python spine host **`p0_semantic_tokenize_cache_miss_branch`** failed (**F80**) |
| **343** | C vs Python **`p0_semantic_tokenize_cache_miss_branch`** stdout mismatch (**F80**) |
| **344** | C minimal **`p0_semantic_tokenize_cache_hit_branch`** failed, wrong stdout order, or missing **`CACHE_HIT`** / **`1`** / **`hit-body`** / **`P0_SEM_TOK_CACHE_HIT_OK`** (**F81**) |
| **345** | Python spine host **`p0_semantic_tokenize_cache_hit_branch`** failed (**F81**) |
| **346** | C vs Python **`p0_semantic_tokenize_cache_hit_branch`** stdout mismatch (**F81**) |
| **347** | C minimal **`p0_semantic_tokenize_cache_hit_emit_complete`** failed, wrong stdout order, or missing **`CACHE_HIT`** / **`TC_INNER`** / **`hit-body`** / **`P0_SEM_F82_OK`** (**F82**) |
| **348** | Python spine host **`p0_semantic_tokenize_cache_hit_emit_complete`** failed (**F82**) |
| **349** | C vs Python **`p0_semantic_tokenize_cache_hit_emit_complete`** stdout mismatch (**F82**) |
| **350** | C minimal **`p0_semantic_parse_cache_miss_branch`** failed, wrong stdout order, or missing **`seed-toks`** / **`PARSE_MISS`** / **`1`** / **`P0_SEM_PARSE_CACHE_MISS_OK`** (**F83**) |
| **351** | Python spine host **`p0_semantic_parse_cache_miss_branch`** failed (**F83**) |
| **352** | C vs Python **`p0_semantic_parse_cache_miss_branch`** stdout mismatch (**F83**) |
| **353** | C minimal **`p0_semantic_parse_cache_hit_branch`** failed, wrong stdout order, or missing **`seed-toks`** / **`PARSE_HIT`** / **`1`** / **`ast-node`** / **`P0_SEM_PARSE_CACHE_HIT_OK`** (**F84**) |
| **354** | Python spine host **`p0_semantic_parse_cache_hit_branch`** failed (**F84**) |
| **355** | C vs Python **`p0_semantic_parse_cache_hit_branch`** stdout mismatch (**F84**) |
| **356** | C minimal **`p0_semantic_parse_cache_hit_emit_complete`** failed, wrong stdout order, or missing **`seed-toks`** / **`PARSE_HIT`** / **`PC_INNER`** / **`ast-body`** / **`P0_SEM_F85_OK`** (**F85**) |
| **357** | Python spine host **`p0_semantic_parse_cache_hit_emit_complete`** failed (**F85**) |
| **358** | C vs Python **`p0_semantic_parse_cache_hit_emit_complete`** stdout mismatch (**F85**) |
| **359** | C minimal **`p0_semantic_execute_payload_emit_complete`** failed, wrong stdout order, or missing **`ast-body`** / **`scope-body`** / **`EXEC_LINE`** / **`EC_INNER`** / **`tw-result`** / **`P0_SEM_F86_OK`** (**F86**) |
| **360** | Python spine host **`p0_semantic_execute_payload_emit_complete`** failed (**F86**) |
| **361** | C vs Python **`p0_semantic_execute_payload_emit_complete`** stdout mismatch (**F86**) |
| **362** | C minimal **`p0_semantic_execute_use_vm_env_off`** failed, wrong stdout, or missing **`P0_SEM_USE_VM_OFF_OK`** — requires **`AZL_USE_VM`** unset (**F87**) |
| **363** | Python spine host **`p0_semantic_execute_use_vm_env_off`** failed (**F87**) |
| **364** | C vs Python **`p0_semantic_execute_use_vm_env_off`** stdout mismatch (**F87**) |
| **97** | Semantic spine owner probe failed ( **`verify_semantic_spine_owner_contract.sh`**: bad **`--semantic-owner`** exit or missing host) |
| **98** | Semantic spine owner line mismatch (expected **`AZL_SEMANTIC_OWNER=minimal_runtime_python`**) |
| **99** | **`azl_azl_interpreter_runtime.sh`** no longer **`exec python3`** spine host (C must not own semantic spine) |
| **100** | **`azl_runtime_spine_host.py`** missing **`minimal_runtime.run_file`** import contract |

**Gate G** runs **`verify_runtime_spine_contract.sh`** — exits **90–96** propagate (table below). **Gate G2** runs **`verify_semantic_spine_owner_contract.sh`** — exits **92**, **97–100** propagate. **Gate H** runs **`verify_p0_interpreter_tokenizer_boundary.sh`** (Python **`SystemExit`**, typically **1** with **`ERROR:`** on stderr).

### Runtime spine contract (`scripts/verify_runtime_spine_contract.sh`)

| Exit | Meaning |
|------|---------|
| **90** | Default **`AZL_RUNTIME_SPINE`** must resolve to C minimal launcher |
| **91** | **`AZL_RUNTIME_SPINE=azl_interpreter`** must resolve to semantic launcher |
| **92** | **`python3`** not found |
| **93** | Spine host invalid combined path did not exit **71** |
| **94** | Spine host stderr missing **`ERR_AZL_COMBINED_PATH_INVALID`** |
| **95** | Spine host **`c_minimal_link_ping`** did not exit **0** |
| **96** | Spine host output missing **`C_MINIMAL_LINK_PING_OK`** |

### Semantic spine owner (`scripts/verify_semantic_spine_owner_contract.sh`)

Tier B **P0.1** guard: with **`AZL_RUNTIME_SPINE=azl_interpreter`**, the child launcher must remain **`exec python3 …/azl_runtime_spine_host.py`** → **`azl_semantic_engine.minimal_runtime`**, not the C minimal binary.

| Exit | Meaning |
|------|---------|
| **92** | **`python3`** not found |
| **97** | Owner probe failed (host missing, or **`--semantic-owner`** not exit **0**) |
| **98** | Owner stdout line not exactly **`AZL_SEMANTIC_OWNER=minimal_runtime_python`** |
| **99** | Semantic launcher contract broken (**`exec python3`** / **`azl_runtime_spine_host.py`**) |
| **100** | Spine host import contract broken (**`minimal_runtime.run_file`**) |

### Real interpreter source on semantic spine (`scripts/verify_azl_interpreter_semantic_spine_smoke.sh`)

Tier B **P0.1** release crumb: concatenates **`azl/tests/stubs/azl_security_for_interpreter_spine.azl`** + **`azl/runtime/interpreter/azl_interpreter.azl`**, runs **`tools/azl_runtime_spine_host.py`** with **`AZL_ENTRY=azl.interpreter`**, asserts exit **0**, no **`component not found: ::azl.security`** on stderr, and stdout contains **`Pure AZL Interpreter Initialized`**. Prefix **`ERROR[AZL_INTERPRETER_SEMANTIC_SPINE_SMOKE]:`** on stderr.

| Exit | Meaning |
|------|---------|
| **40** | **`rg`** not found |
| **92** | **`python3`** not found |
| **286** | Required file missing (stub, interpreter source, or spine host) |
| **287** | Failed to write temp combined AZL |
| **288** | Spine host non-zero exit |
| **289** | **`link ::azl.security`** still unresolved (stderr pattern) |
| **290** | Stdout missing interpreter init marker |

### Strength bar (`scripts/verify_azl_strength_bar.sh`)

Prefix **`ERROR[AZL_STRENGTH_BAR]:`** on stderr for script-owned failures.

| Exit | Meaning |
|------|---------|
| **1** | Not run from repo root |
| **2** | **`rg`** not found |
| **3** | **`jq`** not found |
| **4** | **`python3`** not found |
| **5** | **`gcc`** not found |
| **10** | Step 1: **`check_azl_native_gates.sh`** failed (see exits above) |
| **11** | Step 2: **`verify_native_runtime_live.sh`** failed |
| **12** | Step 3: **`verify_enterprise_native_http_live.sh`** failed |

### Release checkout assertion (`scripts/gh_assert_checkout_matches_tag.sh`)

Used by **`.github/workflows/release.yml`** after **`actions/checkout`** at the release tag.

| Exit | Meaning |
|------|---------|
| **2** | Usage: missing **`<tag>`** argument |
| **3** | **`refs/tags/<tag>^{commit}`** not found (shallow clone or wrong tag) |
| **4** | **`HEAD`** ≠ peeled tag commit |
| **5** | **`git`** not found |

### Native release profile completeness (`scripts/verify_native_release_profile_complete.sh`)

**Tier A** ceremony: runs **`verify_required_github_status_checks_contract.sh`**, **`run_full_repo_verification.sh`** with **`RUN_OPTIONAL_BENCHES=0`**, **`verify_azl_strength_bar.sh`**. See **`docs/PROJECT_COMPLETION_STATEMENT.md`**.

| Exit | Meaning |
|------|---------|
| *(propagated)* | Same code as the first failing child script (contract **11–17**, release/verify/strength-bar tables, etc.) |

### Documentation verification pieces (`scripts/verify_documentation_pieces.sh`)

Runnable **pieces** from **`release/doc_verification_pieces.json`**: each entry must cite an existing **`doc`** path; its **`shell`** runs from repo root with **`set -euo pipefail`**. **`--promoted-only`** runs entries with **`"promoted": true`** — that mode is **step 0** of **`scripts/run_full_repo_verification.sh`** (**`make verify`**). Prefix **`ERROR[DOC_VERIFICATION_PIECES]:`** on stderr.

| Exit | Meaning |
|------|---------|
| **101** | Not repository root (**`Makefile`** / **`scripts`** missing) |
| **102** | **`jq`** not found |
| **103** | Manifest missing, unreadable, or not an object with **`.pieces`** array |
| **104** | Unknown CLI argument |
| **105** | Piece cites **`doc`** path that is not a regular file |
| **106** | Piece **`shell`** command failed |
| **107** | Duplicate **`id`** in manifest |
| **109** | Piece missing required **`id`**, **`doc`**, or **`shell`** |

### Required GitHub status checks contract (`scripts/verify_required_github_status_checks_contract.sh`)

Runs in **CI** ( **`test-and-deploy.yml`**, **`azl-ci.yml`** ): validates **`release/ci/required_github_status_checks.json`** against **`.github/workflows/test-and-deploy.yml`** (job ids, **`name:`** lines, matrix variants). No GitHub API.

| Exit | Meaning |
|------|---------|
| **11** | **`jq`** not found |
| **12** | Config missing / invalid JSON / bad **`workflow_assertions`** / **`must_not_require_job_ids`** inconsistency |
| **13** | **`workflow_file`** path missing on disk |
| **14** | Job block or **`name:`** line mismatch vs assertion |
| **15** | Matrix variant missing under **`matrix.include`** |
| **16** | Forbidden context string appears in derived required list |
| **17** | Derived required-context list empty |

### Branch protection (`scripts/gh_apply_main_branch_protection.sh`)

Maintainer / local: **PUT**, **`--dry-run`**, or **`--verify`** **GET**. Required contexts are read from **`release/ci/required_github_status_checks.json`** (not hard-coded). **`--dry-run`** needs **`jq`** only. **PUT** / **`--verify`** need **`gh`** + auth (**`--verify`** needs permission to read protection). Not invoked from Actions.

| Exit | Meaning |
|------|---------|
| **0** | **`--help`** / **`-h`** (usage on stderr), or **`--verify`** success |
| **2** | Invalid arguments (e.g. both **`--dry-run`** and **`--verify`**, or extra branch argument) |
| **3** | **`GITHUB_REPOSITORY`** unset and **`gh repo view`** could not resolve owner/repo |
| **4** | **`release/ci/required_github_status_checks.json`** missing, invalid JSON, or cannot derive contexts |
| **5** | **`gh`** or **`jq`** not found |
| **6** | **`gh`** not authenticated (N/A for **`--dry-run`**) |
| **7** | GitHub API **PUT** **`…/branches/<branch>/protection`** failed (**stderr** includes API body if present) |
| **8** | **`--verify`**: branch not protected or **GET** **404** / “Branch not protected” |
| **9** | **`--verify`**: **`strict`** is not **true**, or required **contexts** / **`checks[].context`** set ≠ expected (sorted JSON arrays differ) |
| **10** | **`--verify`**: **GET** failed (non-404), or response was not valid JSON |


