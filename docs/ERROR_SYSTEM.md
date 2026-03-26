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
- **Documentation pieces:** **`release/doc_verification_pieces.json`** is enforced by **`scripts/verify_documentation_pieces.sh`**; **`--promoted-only`** runs at the start of **`run_full_repo_verification.sh`** (**`make verify`**). See **`docs/INTEGRATION_VERIFY.md`**. Promoted pieces include **`bash -n`** on **`scripts/verify_azl_interpreter_semantic_spine_smoke.sh`** (P0.1b; **`docs/ERROR_SYSTEM.md`** § *Real interpreter source on semantic spine*) and **`scripts/verify_azl_interpreter_semantic_spine_behavior_smoke.sh`** (P0.1c; § *Real interpreter behavior bridge on semantic spine*).
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
| `scripts/benchmark_enterprise_v1_chat.sh` | **2** | **`AZL_API_TOKEN`** unset and no **`.azl/local_api_token`** |
| | **91** | **`GET /healthz`** unreachable on enterprise port |
| | **93** | Wrong profile: C **`healthz`** or C-like **`/api/llm/capabilities`** |
| | **94** | Benchmark **`curl`** request(s) failed |
| | **95** | **`POST /v1/chat`** returned **404** |
| | | Prefix **`ERROR[AZL_ENTERPRISE_V1_CHAT_BENCH]:`** — § *Enterprise POST /v1/chat benchmark* (**91**–**95** overlap **gate G**; use stderr + script) |

### LHA3 compression honesty contract (`scripts/verify_lha3_compression_honesty_contract.sh`)

Runs **before** the native stack inside **`scripts/verify_quantum_lha3_stack.sh`**. Ensures **`docs/LHA3_COMPRESSION_HONESTY.md`** exists with contract anchor **`LHA3_COMPRESSION_HONESTY_CONTRACT_V1`**, and **`LHA3_COMPRESSION_MODEL=heuristic_retention`** markers remain in **`azl/quantum/memory/lha3_quantum_engine.azl`**, **`azl/memory/lha3_quantum_memory.azl`**, **`azl/runtime/memory/lha3_memory_system.azl`**, and **`azl/memory/fractal_memory_compression.azl`**. Prefix **`ERROR[LHA3_COMPRESSION_HONESTY]:`** on stderr.

| Exit | Meaning |
|------|---------|
| **220** | Not repository root |
| **221** | **`docs/LHA3_COMPRESSION_HONESTY.md`** missing |
| **222** | Contract anchor **`LHA3_COMPRESSION_HONESTY_CONTRACT_V1`** missing from honesty doc |
| **223** | Marker missing in **`lha3_quantum_engine.azl`** |
| **224** | Marker missing in **`lha3_quantum_memory.azl`** |
| **225** | **`rg`** not found |
| **226** | Marker missing in **`azl/runtime/memory/lha3_memory_system.azl`** |
| **227** | Marker missing in **`azl/memory/fractal_memory_compression.azl`** |

### Quantum crypto demo tier (`scripts/verify_quantum_crypto_demo_tier_contract.sh`)

Runs inside **`scripts/verify_quantum_lha3_stack.sh`** immediately after the LHA3 compression honesty script. Requires **`AZL_CRYPTO_DEMO_SURFACE=DEMO_NON_CRYPTO_STUB`** in **`azl/quantum/processor/quantum_encryption.azl`**, **`hpqvpn.azl`**, and **`agent_channels.azl`**. Prefix **`ERROR[QUANTUM_CRYPTO_DEMO]:`** on stderr.

| Exit | Meaning |
|------|---------|
| **905** | Not repository root |
| **906** | **`rg`** not found |
| **907** | Listed **`.azl`** file missing |
| **908** | Demo marker missing in a listed file |

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

### Native core engine selftest (`scripts/verify_azl_core_engine.sh`)

Runs in **`scripts/run_tests.sh`**. Compiles **`tools/azl_core_engine.c`**, **`tools/azl_bytecode.c`**, and **`tools/azl_compiler.c`** with **`AZL_CORE_ENGINE_SELFTEST`** (multi-listener dispatch, fixed-depth recursion guard, JSON bytecode hello-world **`tools/testdata/vm_hello_world.json`**, AZL-source compile + VM hello **`tools/testdata/vm_hello.azl`**, **`vm_branch.azl`** success path). **`azl_compiler_selftest`** also runs **`native_vm_negative_and_edge_suite`**: compile failures for malformed **`if`**/**`emit`**/**`set`** and unknown variables (fixtures **`tools/testdata/compile_bad_*.azl`**), **`vm_exec`** failures on JSON bytecode with bad jump target / unset **`load_var`** / unset **`emit_var`** / out-of-range **`store_var`** (**`vm_bad_*.json`**), and real **`else`** path (**`vm_branch_else.azl`**: **`failure`** with **`result=no`**, no **`success`**). Verify requires those fixtures to exist, then asserts the selftest log contains **`native_vm_negative_and_edge_suite: ok`**. Then links **`azl-native-engine`** and asserts a raw compile-subset **`tools/testdata/vm_hello.azl`** (non-bootstrap) defaults to **`execution_lane=native_compile_vm`** on stderr (no **`--use-native-core`**). Prefix **`ERROR[AZL_CORE_ENGINE_VERIFY]:`** on stderr.

| Exit | Meaning |
|------|---------|
| **627** | Not repository root / **`tools/azl_core_engine.c`** missing |
| **628** | **`gcc`** not found |
| **629** | Compile failed (**`-Wall -Wextra -Werror`**) |
| **630** | **`azl_core_engine_selftest`** non-zero exit, or selftest log missing **`native_vm_negative_and_edge_suite: ok`** (negative/edge suite not proven); historically exit **4** = JSON bytecode VM, **5** = AZL compiler / **`vm_hello.azl`** path |
| **631** | **`azl-native-engine`** link failed (lane probe build) |
| **632** | **`tools/testdata/vm_hello.azl`** missing (lane probe) |
| **903** | Lane probe: stderr missing **`execution_lane=native_compile_vm`** for raw compile-subset **`.azl`** |
| **904** | Required native negative/edge fixture missing under **`tools/testdata/`** (see script header list) |

### RepertoireField surface contract (`scripts/verify_repertoire_field_surface_contract.sh`)

Runs at the start of **`scripts/run_tests.sh`**. Ensures **`docs/AZL_GPU_NEURAL_SURFACE_MAP.md`** contains **`REPERTOIREFIELD_SURFACE_CONTRACT_V1`** and **RepertoireField**, **`azl/quantum/real_quantum_processor.azl`** exists, and that file contains **`REPERTOIREFIELD_IMPL_SCOPE=canonical_qc_numeric_processor`** (bounded simulator surface, not the full product API). Prefix **`ERROR[REPERTOIREFIELD_SURFACE]:`** on stderr.

| Exit | Meaning |
|------|---------|
| **230** | Not repository root |
| **231** | GPU surface map doc missing |
| **232** | **`rg`** not found |
| **233** | Contract anchor missing |
| **234** | **RepertoireField** string missing from doc |
| **235** | **`real_quantum_processor.azl`** missing |
| **236** | Impl scope marker missing in **`real_quantum_processor.azl`** |

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

**Note:** The same exit **integer** may be documented in **other** tables (e.g. **`verify_azl_core_engine.sh`** uses **627–632** for unrelated failures). Interpret **`$?` by which script exited** — do not assume one global meaning per integer across the repo.

Semantic parity slices **F5–F191** map to the rows below (**F9** stdout mismatch = **59**, intentionally **not** **`verify_native_runtime_live.sh`** **69**; **F10** = **111–113**; **F11** = **114–116**; **F12** = **117–119**; **F13** = **120–122**; **F14** = **123–125**; **F15** = **126–128**; **F16** = **129–131**; **F17** = **132–134**; **F18** = **135–137**; **F19** = **138–140**; **F20** = **141–143**; **F21** = **144–146**; **F22** = **147–149**; **F23** = **150–152**; **F24** = **153–155**; **F25** = **156–158**; **F26** = **159–161**; **F27** = **162–164**; **F28** = **165–167**; **F29** = **168–170**; **F30** = **171–173**; **F31** = **174–176**; **F32** = **177–179**; **F33** = **180–182**; **F34** = **183–185**; **F35** = **186–188**; **F36** = **189–191**; **F37** = **192–194**; **F38** = **195–197**; **F39** = **198–200**; **F40** = **201–203**; **F41** = **204–206**; **F42** = **207–209**; **F43** = **210–212**; **F44** = **213–215**; **F45** = **216–218**; **F46** = **219–221**; **F47** = **222–224**; **F48** = **225–227**; **F49** = **228–230**; **F50** = **231–233**; **F51** = **234–236**; **F52** = **237–239**; **F53** = **240–242**; **F54** = **243–245**; **F55** = **246–248**; **F56** = **249–251**; **F57** = **252–254**; **F58** = **255–257**; **F59** = **258–260**; **F60** = **261–263**; **F61** = **264–266**; **F62** = **267–269**; **F63** = **270** / **272** / **273** (Python failure uses **272**, not **271** — **271** is **`CODEC_DECOMPRESS_FAILED`** in literal codec harness); **F64** = **274–276**; **F65** = **277–279**; **F66** = **280–282**; **F67** = **283–285**; **F68** = **291–293**; **F69** = **294–296**; **F70** = **297–299**; **F71** = **311–313**; **F72** = **314–316**; **F73** = **317–319**; **F74** = **323–325**; **F75** = **326–328**; **F76** = **329–331**; **F77** = **332–334**; **F78** = **335–337**; **F79** = **338–340**; **F80** = **341–343**; **F81** = **344–346**; **F82** = **347–349**; **F83** = **350–352**; **F84** = **353–355**; **F85** = **356–358**; **F86** = **359–361**; **F87** = **362–364**; **F88** = **365–367**; **F89** = **368–370**; **F90** = **371–373**; **F91** = **374–376**; **F92** = **377–379**; **F93** = **380–382**; **F94** = **383–385**; **F95** = **386–388**; **F96** = **389–391**; **F97** = **392–394**; **F98** = **395–397**; **F99** = **398–400**; **F100** = **401–403**; **F101** = **404–406**; **F102** = **407–409**; **F103** = **410–412**; **F104** = **413–415**; **F105** = **416–418**; **F106** = **419–421**; **F107** = **422–424**; **F108** = **425–427**; **F109** = **428–430**; **F110** = **431–433**; **F111** = **434–436**; **F112** = **437–439**; **F113** = **440–442**; **F114** = **443–445**; **F115** = **446–448**; **F116** = **449–451**; **F117** = **452–454**; **F118** = **455–457**; **F119** = **458–460**; **F120** = **461–463**; **F121** = **464–466**; **F122** = **467–469**; **F123** = **470–472**; **F124** = **473–475**; **F125** = **476–478**; **F126** = **479–481**; **F127** = **482–484**; **F128** = **485–487**; **F129** = **488–490**; **F130** = **491–493**; **F131** = **494–496**; **F132** = **497–499**; **F133** = **500–502**; **F134** = **503–505**; **F135** = **506–508**; **F136** = **509–511**; **F137** = **512–514**; **F138** = **515–517**; **F139** = **518–520**; **F140** = **521–523**; **F141** = **524–526**; **F142** = **527–529**; **F143** = **530–532**; **F144** = **533–535**; **F145** = **536–538**; **F146** = **539–541**; **F147** = **542–544**; **F148** = **545–547**; **F149** = **560–562**; **F150** = **563–565**; **F151** = **566–568**; **F152** = **569–571**; **F153** = **572–574**; **F154** = **575–577**; **F155** = **578–580**; **F156** = **581–583**; **F157** = **584–586**; **F158** = **587–589**; **F159** = **590–592**; **F160** = **593–595**; **F161** = **596–598**; **F162** = **599–601**; **F163** = **602–604**; **F164** = **605–607**; **F165** = **608–610**; **F166** = **612–614**; **F167** = **615–617**; **F168** = **618–620**; **F169** = **621–623**; **F170** = **624–626**; **F171** = **627–629**; **F172** = **630–632**; **F173** = **768–770**; **F174** = **771–773**; **F175** = **774–776**; **F176** = **783–785**; **F177** = **786–788**; **F178** = **789–791**; **F179** = **777–779**; **F180** = **780–782**; **F181** = **792–794**; **F182** = **795–797**; **F183** = **798–800**; **F184** = **801–803**; **F185** = **804–806**; **F186** = **807–809**; **F187** = **810–812**; **F188** = **813–815**; **F189** = **816–818**; **F190** = **819–821**; **F191** = **822–824**).

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
| **365** | C minimal **`p0_semantic_halt_execution_listener`** failed, wrong stdout order, or missing **`P0_HALT_SIGNAL_OK`** / **`P0_SEM_F88_OK`** (**F88**) |
| **366** | Python spine host **`p0_semantic_halt_execution_listener`** failed (**F88**) |
| **367** | C vs Python **`p0_semantic_halt_execution_listener`** stdout mismatch (**F88**) |
| **368** | C minimal **`p0_semantic_execute_ast_nodes_preloop`** failed, wrong stdout order, or missing **F89** markers (**`P89_PRELOOP_ENTER`** … **`P0_SEM_F89_OK`**) |
| **369** | Python spine host **`p0_semantic_execute_ast_nodes_preloop`** failed (**F89**) |
| **370** | C vs Python **`p0_semantic_execute_ast_nodes_preloop`** stdout mismatch (**F89**) |
| **371** | C minimal **`p0_semantic_execute_vm_path_ok`** failed, wrong stdout, or missing VM ok-path markers — requires **`AZL_USE_VM=1`** (**F90**) |
| **372** | Python spine host **`p0_semantic_execute_vm_path_ok`** failed (**F90**) |
| **373** | C vs Python **`p0_semantic_execute_vm_path_ok`** stdout mismatch (**F90**) |
| **374** | C minimal **`p0_semantic_execute_vm_compile_error`** failed, wrong stdout, or missing compile-error markers — requires **`AZL_USE_VM=1`** (**F91**) |
| **375** | Python spine host **`p0_semantic_execute_vm_compile_error`** failed (**F91**) |
| **376** | C vs Python **`p0_semantic_execute_vm_compile_error`** stdout mismatch (**F91**) |
| **377** | C minimal **`p0_semantic_execute_vm_empty_bytecode`** failed, wrong stdout, or missing empty-bytecode markers — requires **`AZL_USE_VM=1`** (**F92**) |
| **378** | Python spine host **`p0_semantic_execute_vm_empty_bytecode`** failed (**F92**) |
| **379** | C vs Python **`p0_semantic_execute_vm_empty_bytecode`** stdout mismatch (**F92**) |
| **380** | C minimal **`p0_semantic_execute_ast_tree_walk`** failed, wrong stdout, or missing **`execute_ast`** markers — requires **`AZL_USE_VM` unset** (**F93**) |
| **381** | Python spine host **`p0_semantic_execute_ast_tree_walk`** failed (**F93**) |
| **382** | C vs Python **`p0_semantic_execute_ast_tree_walk`** stdout mismatch (**F93**) |
| **383** | C minimal **`p0_semantic_execute_ast_emit_step`** failed, wrong stdout, or missing **`emit|`** markers — requires **`AZL_USE_VM` unset** (**F94**) |
| **384** | Python spine host **`p0_semantic_execute_ast_emit_step`** failed (**F94**) |
| **385** | C vs Python **`p0_semantic_execute_ast_emit_step`** stdout mismatch (**F94**) |
| **386** | C minimal **`p0_semantic_execute_ast_set_step`** failed, wrong stdout, or missing **`set|`** markers — requires **`AZL_USE_VM` unset** (**F95**) |
| **387** | Python spine host **`p0_semantic_execute_ast_set_step`** failed (**F95**) |
| **388** | C vs Python **`p0_semantic_execute_ast_set_step`** stdout mismatch (**F95**) |
| **389** | C minimal **`p0_semantic_execute_ast_emit_with_step`** failed, wrong stdout, or missing **`emit|…|with|…`** markers — requires **`AZL_USE_VM` unset** (**F96**) |
| **390** | Python spine host **`p0_semantic_execute_ast_emit_with_step`** failed (**F96**) |
| **391** | C vs Python **`p0_semantic_execute_ast_emit_with_step`** stdout mismatch (**F96**) |
| **392** | C minimal **`p0_semantic_execute_ast_emit_multi_with_step`** failed, wrong stdout, or missing multi-**`emit|…|with|…`** markers — requires **`AZL_USE_VM` unset** (**F97**) |
| **393** | Python spine host **`p0_semantic_execute_ast_emit_multi_with_step`** failed (**F97**) |
| **394** | C vs Python **`p0_semantic_execute_ast_emit_multi_with_step`** stdout mismatch (**F97**) |
| **395** | C minimal **`p0_semantic_execute_ast_import_link_preloop`** failed, wrong stdout, or missing **`import|/`link|`** preloop markers — requires **`AZL_USE_VM` unset** (**F98**) |
| **396** | Python spine host **`p0_semantic_execute_ast_import_link_preloop`** failed (**F98**) |
| **397** | C vs Python **`p0_semantic_execute_ast_import_link_preloop`** stdout mismatch (**F98**) |
| **398** | C minimal **`p0_semantic_execute_ast_component_listen_step`** failed, wrong stdout, or missing **`component|/`listen|`** markers — requires **`AZL_USE_VM` unset** (**F99**) |
| **399** | Python spine host **`p0_semantic_execute_ast_component_listen_step`** failed (**F99**) |
| **400** | C vs Python **`p0_semantic_execute_ast_component_listen_step`** stdout mismatch (**F99**) |
| **401** | C minimal **`p0_semantic_execute_ast_listen_emit_stub`** failed, wrong stdout, or missing **`listen|…|emit|…`** stub markers — requires **`AZL_USE_VM` unset** (**F100**) |
| **402** | Python spine host **`p0_semantic_execute_ast_listen_emit_stub`** failed (**F100**) |
| **403** | C vs Python **`p0_semantic_execute_ast_listen_emit_stub`** stdout mismatch (**F100**) |
| **404** | C minimal **`p0_semantic_execute_ast_listen_set_stub`** failed, wrong stdout, or missing **`listen|…|set|::…|…`** stub markers — requires **`AZL_USE_VM` unset** (**F101**) |
| **405** | Python spine host **`p0_semantic_execute_ast_listen_set_stub`** failed (**F101**) |
| **406** | C vs Python **`p0_semantic_execute_ast_listen_set_stub`** stdout mismatch (**F101**) |
| **407** | C minimal **`p0_semantic_execute_ast_listen_emit_with_stub`** failed, wrong stdout, or missing **`listen|…|emit|…|with|…`** stub markers — requires **`AZL_USE_VM` unset** (**F102**) |
| **408** | Python spine host **`p0_semantic_execute_ast_listen_emit_with_stub`** failed (**F102**) |
| **409** | C vs Python **`p0_semantic_execute_ast_listen_emit_with_stub`** stdout mismatch (**F102**) |
| **410** | C minimal **`p0_semantic_execute_ast_listen_emit_multi_with_stub`** failed, wrong stdout, or missing multi-**`listen|…|emit|…|with|…`** stub markers — requires **`AZL_USE_VM` unset** (**F103**) |
| **411** | Python spine host **`p0_semantic_execute_ast_listen_emit_multi_with_stub`** failed (**F103**) |
| **412** | C vs Python **`p0_semantic_execute_ast_listen_emit_multi_with_stub`** stdout mismatch (**F103**) |
| **413** | C minimal **`p0_semantic_execute_ast_memory_set_step`** failed, wrong stdout, or missing **`memory|set|…`** / **`memory|say|…`** stub markers — requires **`AZL_USE_VM` unset** (**F104**) |
| **414** | Python spine host **`p0_semantic_execute_ast_memory_set_step`** failed (**F104**) |
| **415** | C vs Python **`p0_semantic_execute_ast_memory_set_step`** stdout mismatch (**F104**) |
| **416** | C minimal **`p0_semantic_execute_ast_memory_emit_step`** failed, wrong stdout, or missing **`memory|emit|…`** stub markers — requires **`AZL_USE_VM` unset** (**F105**) |
| **417** | Python spine host **`p0_semantic_execute_ast_memory_emit_step`** failed (**F105**) |
| **418** | C vs Python **`p0_semantic_execute_ast_memory_emit_step`** stdout mismatch (**F105**) |
| **419** | C minimal **`p0_semantic_execute_ast_memory_emit_with_step`** failed, wrong stdout, or missing **`memory|emit|…|with|…`** stub markers — requires **`AZL_USE_VM` unset** (**F106**) |
| **420** | Python spine host **`p0_semantic_execute_ast_memory_emit_with_step`** failed (**F106**) |
| **421** | C vs Python **`p0_semantic_execute_ast_memory_emit_with_step`** stdout mismatch (**F106**) |
| **422** | C minimal **`p0_semantic_execute_ast_memory_emit_multi_with_step`** failed, wrong stdout, or missing multi-**`memory|emit|…|with|…`** stub markers — requires **`AZL_USE_VM` unset** (**F107**) |
| **423** | Python spine host **`p0_semantic_execute_ast_memory_emit_multi_with_step`** failed (**F107**) |
| **424** | C vs Python **`p0_semantic_execute_ast_memory_emit_multi_with_step`** stdout mismatch (**F107**) |
| **425** | C minimal **`p0_semantic_execute_ast_memory_multi_row_order`** failed, wrong stdout, or missing multi-**`memory|say|…`** order markers — requires **`AZL_USE_VM` unset** (**F108**) |
| **426** | Python spine host **`p0_semantic_execute_ast_memory_multi_row_order`** failed (**F108**) |
| **427** | C vs Python **`p0_semantic_execute_ast_memory_multi_row_order`** stdout mismatch (**F108**) |
| **428** | C minimal **`p0_semantic_execute_ast_memory_mixed_order`** failed, wrong stdout, or missing mixed **`memory|set|…`** / **`memory|emit|…`** / **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F109**) |
| **429** | Python spine host **`p0_semantic_execute_ast_memory_mixed_order`** failed (**F109**) |
| **430** | C vs Python **`p0_semantic_execute_ast_memory_mixed_order`** stdout mismatch (**F109**) |
| **431** | C minimal **`p0_semantic_execute_ast_memory_mixed_emit_with_order`** failed, wrong stdout, or missing mixed **`memory|set|…`** / **`memory|emit|…|with|…`** / **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F110**) |
| **432** | Python spine host **`p0_semantic_execute_ast_memory_mixed_emit_with_order`** failed (**F110**) |
| **433** | C vs Python **`p0_semantic_execute_ast_memory_mixed_emit_with_order`** stdout mismatch (**F110**) |
| **434** | C minimal **`p0_semantic_execute_ast_memory_mixed_emit_multi_with_order`** failed, wrong stdout, or missing mixed **`memory|set|…`** / multi-**`memory|emit|…|with|…`** / **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F111**) |
| **435** | Python spine host **`p0_semantic_execute_ast_memory_mixed_emit_multi_with_order`** failed (**F111**) |
| **436** | C vs Python **`p0_semantic_execute_ast_memory_mixed_emit_multi_with_order`** stdout mismatch (**F111**) |
| **437** | C minimal **`p0_semantic_execute_ast_preloop_then_memory_say`** failed, wrong stdout, or missing preloop + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F112**) |
| **438** | Python spine host **`p0_semantic_execute_ast_preloop_then_memory_say`** failed (**F112**) |
| **439** | C vs Python **`p0_semantic_execute_ast_preloop_then_memory_say`** stdout mismatch (**F112**) |
| **440** | C minimal **`p0_semantic_execute_ast_preloop_say_then_memory_say`** failed, wrong stdout, or missing preloop + **`say|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F113**) |
| **441** | Python spine host **`p0_semantic_execute_ast_preloop_say_then_memory_say`** failed (**F113**) |
| **442** | C vs Python **`p0_semantic_execute_ast_preloop_say_then_memory_say`** stdout mismatch (**F113**) |
| **443** | C minimal **`p0_semantic_execute_ast_preloop_emit_then_memory_say`** failed, wrong stdout, or missing preloop + **`emit|…|with|…`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F114**) |
| **444** | Python spine host **`p0_semantic_execute_ast_preloop_emit_then_memory_say`** failed (**F114**) |
| **445** | C vs Python **`p0_semantic_execute_ast_preloop_emit_then_memory_say`** stdout mismatch (**F114**) |
| **446** | C minimal **`p0_semantic_execute_ast_memory_listen_emit_say`** failed, wrong stdout, or missing **`memory|listen|…`** + **`memory|emit|…`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F115**) |
| **447** | Python spine host **`p0_semantic_execute_ast_memory_listen_emit_say`** failed (**F115**) |
| **448** | C vs Python **`p0_semantic_execute_ast_memory_listen_emit_say`** stdout mismatch (**F115**) |
| **449** | C minimal **`p0_semantic_execute_ast_memory_listen_emit_with_say`** failed, wrong stdout, or missing **`memory|listen|…|emit|…|with|…`** + **`memory|emit|…`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F116**) |
| **450** | Python spine host **`p0_semantic_execute_ast_memory_listen_emit_with_say`** failed (**F116**) |
| **451** | C vs Python **`p0_semantic_execute_ast_memory_listen_emit_with_say`** stdout mismatch (**F116**) |
| **452** | C minimal **`p0_semantic_execute_ast_memory_listen_emit_multi_with_say`** failed, wrong stdout, or missing multi-**`memory|listen|…|emit|…|with|…`** + **`memory|emit|…`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F117**) |
| **453** | Python spine host **`p0_semantic_execute_ast_memory_listen_emit_multi_with_say`** failed (**F117**) |
| **454** | C vs Python **`p0_semantic_execute_ast_memory_listen_emit_multi_with_say`** stdout mismatch (**F117**) |
| **455** | C minimal **`p0_semantic_execute_ast_preloop_memory_listen_emit_multi_with_say`** failed, wrong stdout, or missing preloop + multi-**`memory|listen|…|emit|…|with|…`** + **`memory|emit|…`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F118**) |
| **456** | Python spine host **`p0_semantic_execute_ast_preloop_memory_listen_emit_multi_with_say`** failed (**F118**) |
| **457** | C vs Python **`p0_semantic_execute_ast_preloop_memory_listen_emit_multi_with_say`** stdout mismatch (**F118**) |
| **458** | C minimal **`p0_semantic_execute_ast_memory_listen_stack_say`** failed, wrong stdout, or missing stacked **`memory|listen|…|say|…`** + dual **`memory|emit|…`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F119**) |
| **459** | Python spine host **`p0_semantic_execute_ast_memory_listen_stack_say`** failed (**F119**) |
| **460** | C vs Python **`p0_semantic_execute_ast_memory_listen_stack_say`** stdout mismatch (**F119**) |
| **461** | C minimal **`p0_semantic_execute_ast_preloop_memory_listen_stack_say`** failed, wrong stdout, or missing preloop + stacked **`memory|listen|…|say|…`** + dual **`memory|emit|…`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F120**) |
| **462** | Python spine host **`p0_semantic_execute_ast_preloop_memory_listen_stack_say`** failed (**F120**) |
| **463** | C vs Python **`p0_semantic_execute_ast_preloop_memory_listen_stack_say`** stdout mismatch (**F120**) |
| **464** | C minimal **`p0_semantic_execute_ast_preloop_say_then_memory_listen_stack_say`** failed, wrong stdout, or missing preloop + **`say|`** + stacked **`memory|listen|…`** markers — requires **`AZL_USE_VM` unset** (**F121**) |
| **465** | Python spine host **`p0_semantic_execute_ast_preloop_say_then_memory_listen_stack_say`** failed (**F121**) |
| **466** | C vs Python **`p0_semantic_execute_ast_preloop_say_then_memory_listen_stack_say`** stdout mismatch (**F121**) |
| **467** | C minimal **`p0_semantic_execute_ast_preloop_emit_then_memory_listen_stack_say`** failed, wrong stdout, or missing preloop + **`emit|…|with|…`** + stacked **`memory|listen|…`** markers — requires **`AZL_USE_VM` unset** (**F122**) |
| **468** | Python spine host **`p0_semantic_execute_ast_preloop_emit_then_memory_listen_stack_say`** failed (**F122**) |
| **469** | C vs Python **`p0_semantic_execute_ast_preloop_emit_then_memory_listen_stack_say`** stdout mismatch (**F122**) |
| **470** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_set_listen_stack`** failed, wrong stdout, or missing preloop + **`component|`** + dual **`memory|set|…`** + stacked **`memory|listen|…`** markers — requires **`AZL_USE_VM` unset** (**F123**) |
| **471** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_set_listen_stack`** failed (**F123**) |
| **472** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_set_listen_stack`** stdout mismatch (**F123**) |
| **473** | C minimal **`p0_semantic_execute_ast_preloop_two_component_memory_say`** failed, wrong stdout, or missing preloop + dual **`component|`** + **`memory|say|…`** interleave markers — requires **`AZL_USE_VM` unset** (**F124**) |
| **474** | Python spine host **`p0_semantic_execute_ast_preloop_two_component_memory_say`** failed (**F124**) |
| **475** | C vs Python **`p0_semantic_execute_ast_preloop_two_component_memory_say`** stdout mismatch (**F124**) |
| **476** | C minimal **`p0_semantic_execute_ast_preloop_three_component_memory_say`** failed, wrong stdout, or missing preloop + triple **`component|`** + **`memory|say|…`** interleave markers — requires **`AZL_USE_VM` unset** (**F125**) |
| **477** | Python spine host **`p0_semantic_execute_ast_preloop_three_component_memory_say`** failed (**F125**) |
| **478** | C vs Python **`p0_semantic_execute_ast_preloop_three_component_memory_say`** stdout mismatch (**F125**) |
| **479** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **`memory|emit|…|with|…`** + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F126**) |
| **480** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_emit_component_say`** failed (**F126**) |
| **481** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_emit_component_say`** stdout mismatch (**F126**) |
| **482** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_dual_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **two** **`memory|emit|…|with|…`** + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F127**) |
| **483** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_dual_emit_component_say`** failed (**F127**) |
| **484** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_dual_emit_component_say`** stdout mismatch (**F127**) |
| **485** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_triple_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **three** **`memory|emit|…|with|…`** + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F128**) |
| **486** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_triple_emit_component_say`** failed (**F128**) |
| **487** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_triple_emit_component_say`** stdout mismatch (**F128**) |
| **488** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_bare_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **bare** **`memory|emit|…`** (no **`|with|…`**) + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F129**) |
| **489** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_bare_emit_component_say`** failed (**F129**) |
| **490** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_bare_emit_component_say`** stdout mismatch (**F129**) |
| **491** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_dual_bare_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **two** bare **`memory|emit|…`** + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F130**) |
| **492** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_dual_bare_emit_component_say`** failed (**F130**) |
| **493** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_dual_bare_emit_component_say`** stdout mismatch (**F130**) |
| **494** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_triple_bare_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **three** bare **`memory|emit|…`** + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F131**) |
| **495** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_triple_bare_emit_component_say`** failed (**F131**) |
| **496** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_triple_bare_emit_component_say`** stdout mismatch (**F131**) |
| **497** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_mixed_bare_with_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **bare** **`memory|emit|…`** + **`memory|emit|…|with|…`** + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F132**) |
| **498** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_mixed_bare_with_emit_component_say`** failed (**F132**) |
| **499** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_mixed_bare_with_emit_component_say`** stdout mismatch (**F132**) |
| **500** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_mixed_with_bare_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **`memory|emit|…|with|…`** + **bare** **`memory|emit|…`** + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F133**) |
| **501** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_mixed_with_bare_emit_component_say`** failed (**F133**) |
| **502** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_mixed_with_bare_emit_component_say`** stdout mismatch (**F133**) |
| **503** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_triple_mixed_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **`memory|emit|…|with|…`** + **bare** **`memory|emit|…`** + **`memory|emit|…|with|…`** + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F134**) |
| **504** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_triple_mixed_emit_component_say`** failed (**F134**) |
| **505** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_triple_mixed_emit_component_say`** stdout mismatch (**F134**) |
| **506** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_triple_mixed_bare_with_bare_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **bare** **`memory|emit|…`** + **`memory|emit|…|with|…`** + **bare** **`memory|emit|…`** + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F135**) |
| **507** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_triple_mixed_bare_with_bare_emit_component_say`** failed (**F135**) |
| **508** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_triple_mixed_bare_with_bare_emit_component_say`** stdout mismatch (**F135**) |
| **509** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_quad_mixed_bare_with_with_bare_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **bare** + **two** **`memory|emit|…|with|…`** + **bare** **`memory|emit|…`** + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F136**) |
| **510** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_quad_mixed_bare_with_with_bare_emit_component_say`** failed (**F136**) |
| **511** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_quad_mixed_bare_with_with_bare_emit_component_say`** stdout mismatch (**F136**) |
| **512** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_quad_mixed_with_bare_bare_with_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **`memory|emit|…|with|…`** + **two** **bare** **`memory|emit|…`** + **`memory|emit|…|with|…`** + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F137**) |
| **513** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_quad_mixed_with_bare_bare_with_emit_component_say`** failed (**F137**) |
| **514** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_quad_mixed_with_bare_bare_with_emit_component_say`** stdout mismatch (**F137**) |
| **515** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_quad_mixed_bare_with_bare_with_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **bare** **`memory|emit|…`** + **`memory|emit|…|with|…`** + **bare** **`memory|emit|…`** + **`memory|emit|…|with|…`** + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F138**) |
| **516** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_quad_mixed_bare_with_bare_with_emit_component_say`** failed (**F138**) |
| **517** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_quad_mixed_bare_with_bare_with_emit_component_say`** stdout mismatch (**F138**) |
| **518** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_quad_mixed_with_with_bare_bare_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **two** **`memory|emit|…|with|…`** + **two** **bare** **`memory|emit|…`** + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F139**) |
| **519** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_quad_mixed_with_with_bare_bare_emit_component_say`** failed (**F139**) |
| **520** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_quad_mixed_with_with_bare_bare_emit_component_say`** stdout mismatch (**F139**) |
| **521** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_penta_mixed_bare_with_bare_with_bare_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **five** **`memory|emit|…`** rows (**bare** / **`with`** / **bare** / **`with`** / **bare**) + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F140**) |
| **522** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_penta_mixed_bare_with_bare_with_bare_emit_component_say`** failed (**F140**) |
| **523** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_penta_mixed_bare_with_bare_with_bare_emit_component_say`** stdout mismatch (**F140**) |
| **524** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_penta_mixed_with_bare_with_bare_with_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **five** **`memory|emit|…`** rows (**`with`** / **bare** / **`with`** / **bare** / **`with`**) + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F141**) |
| **525** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_penta_mixed_with_bare_with_bare_with_emit_component_say`** failed (**F141**) |
| **526** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_penta_mixed_with_bare_with_bare_with_emit_component_say`** stdout mismatch (**F141**) |
| **527** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_hexa_mixed_bare_with_bare_with_bare_with_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **six** **`memory|emit|…`** rows (**bare** / **`with`** / **bare** / **`with`** / **bare** / **`with`**) + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F142**) |
| **528** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_hexa_mixed_bare_with_bare_with_bare_with_emit_component_say`** failed (**F142**) |
| **529** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_hexa_mixed_bare_with_bare_with_bare_with_emit_component_say`** stdout mismatch (**F142**) |
| **530** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_hexa_mixed_with_bare_with_bare_with_bare_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **six** **`memory|emit|…`** rows (**`with`** / **bare** / **`with`** / **bare** / **`with`** / **bare**) + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F143**) |
| **531** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_hexa_mixed_with_bare_with_bare_with_bare_emit_component_say`** failed (**F143**) |
| **532** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_hexa_mixed_with_bare_with_bare_with_bare_emit_component_say`** stdout mismatch (**F143**) |
| **533** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_hepta_bare_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **seven** bare **`memory|emit|…`** rows + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F144**) |
| **534** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_hepta_bare_emit_component_say`** failed (**F144**) |
| **535** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_hepta_bare_emit_component_say`** stdout mismatch (**F144**) |
| **536** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_octa_bare_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **eight** bare **`memory|emit|…`** rows + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F145**) |
| **537** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_octa_bare_emit_component_say`** failed (**F145**) |
| **538** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_octa_bare_emit_component_say`** stdout mismatch (**F145**) |
| **539** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_nona_bare_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **nine** bare **`memory|emit|…`** rows + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F146**) |
| **540** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_nona_bare_emit_component_say`** failed (**F146**) |
| **541** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_nona_bare_emit_component_say`** stdout mismatch (**F146**) |
| **542** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_deca_bare_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **ten** bare **`memory|emit|…`** rows + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F147**) |
| **543** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_deca_bare_emit_component_say`** failed (**F147**) |
| **544** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_deca_bare_emit_component_say`** stdout mismatch (**F147**) |
| **545** | C minimal **`p0_semantic_execute_ast_preloop_component_memory_undeca_bare_emit_component_say`** failed, wrong stdout, or missing preloop + **`component|`** + **eleven** bare **`memory|emit|…`** rows + **`component|`** + **`memory|say|…`** markers — requires **`AZL_USE_VM` unset** (**F148**) |
| **546** | Python spine host **`p0_semantic_execute_ast_preloop_component_memory_undeca_bare_emit_component_say`** failed (**F148**) |
| **547** | C vs Python **`p0_semantic_execute_ast_preloop_component_memory_undeca_bare_emit_component_say`** stdout mismatch (**F148**) |
| **560** | C minimal **`p0_semantic_parse_tokens_say_identifier`** failed, wrong stdout, or missing **`say|F149_PAYLOAD`** / **`P0_SEM_F149_OK`** — requires **`AZL_USE_VM` unset** (**F149**) |
| **561** | Python spine host **`p0_semantic_parse_tokens_say_identifier`** failed (**F149**) |
| **562** | C vs Python **`p0_semantic_parse_tokens_say_identifier`** stdout mismatch (**F149**) |
| **563** | C minimal **`p0_semantic_parse_tokens_multi_statements`** failed, wrong stdout, or missing **`say|A`** / **`set|::f|z`** / **`emit|e`** / **`P0_SEM_F150_OK`** — requires **`AZL_USE_VM` unset** (**F150**) |
| **564** | Python spine host **`p0_semantic_parse_tokens_multi_statements`** failed (**F150**) |
| **565** | C vs Python **`p0_semantic_parse_tokens_multi_statements`** stdout mismatch (**F150**) |
| **566** | C minimal **`p0_semantic_parse_tokens_import_link_say`** failed, wrong stdout, or missing **`import|m`** / **`link|::l`** / **`say|Z`** / **`P0_SEM_F151_OK`** — requires **`AZL_USE_VM` unset** (**F151**) |
| **567** | Python spine host **`p0_semantic_parse_tokens_import_link_say`** failed (**F151**) |
| **568** | C vs Python **`p0_semantic_parse_tokens_import_link_say`** stdout mismatch (**F151**) |
| **569** | C minimal **`p0_semantic_parse_tokens_emit_with_brace`** failed, wrong stdout, or missing **`emit|w|with|k|a`** / **`P0_SEM_F152_OK`** — requires **`AZL_USE_VM` unset** (**F152**) |
| **570** | Python spine host **`p0_semantic_parse_tokens_emit_with_brace`** failed (**F152**) |
| **571** | C vs Python **`p0_semantic_parse_tokens_emit_with_brace`** stdout mismatch (**F152**) |
| **572** | C minimal **`p0_semantic_parse_tokens_emit_with_multi`** failed, wrong stdout, or missing **`emit|w|with|a|b|c|d`** / **`P0_SEM_F153_OK`** — requires **`AZL_USE_VM` unset** (**F153**) |
| **573** | Python spine host **`p0_semantic_parse_tokens_emit_with_multi`** failed (**F153**) |
| **574** | C vs Python **`p0_semantic_parse_tokens_emit_with_multi`** stdout mismatch (**F153**) |
| **575** | C minimal **`p0_semantic_parse_tokens_component`** failed, wrong stdout, or missing **`component|::c154`** / **`P0_SEM_F154_OK`** — requires **`AZL_USE_VM` unset** (**F154**) |
| **576** | Python spine host **`p0_semantic_parse_tokens_component`** failed (**F154**) |
| **577** | C vs Python **`p0_semantic_parse_tokens_component`** stdout mismatch (**F154**) |
| **578** | C minimal **`p0_semantic_parse_tokens_listen_say`** failed, wrong stdout, or missing **`listen|e155|say|PAY155`** / **`P0_SEM_F155_OK`** — requires **`AZL_USE_VM` unset** (**F155**) |
| **579** | Python spine host **`p0_semantic_parse_tokens_listen_say`** failed (**F155**) |
| **580** | C vs Python **`p0_semantic_parse_tokens_listen_say`** stdout mismatch (**F155**) |
| **581** | C minimal **`p0_semantic_parse_tokens_listen_then_say`** failed, wrong stdout, or missing **`listen|f156|say|PAY156`** / **`P0_SEM_F156_OK`** — requires **`AZL_USE_VM` unset** (**F156**) |
| **582** | Python spine host **`p0_semantic_parse_tokens_listen_then_say`** failed (**F156**) |
| **583** | C vs Python **`p0_semantic_parse_tokens_listen_then_say`** stdout mismatch (**F156**) |
| **584** | C minimal **`p0_semantic_parse_tokens_listen_emit`** failed, wrong stdout, or missing **`listen|f157|emit|E157`** / **`P0_SEM_F157_OK`** — requires **`AZL_USE_VM` unset** (**F157**) |
| **585** | Python spine host **`p0_semantic_parse_tokens_listen_emit`** failed (**F157**) |
| **586** | C vs Python **`p0_semantic_parse_tokens_listen_emit`** stdout mismatch (**F157**) |
| **587** | C minimal **`p0_semantic_parse_tokens_listen_emit_with`** failed, wrong stdout, or missing **`listen|f158|emit|em158|with|k|a`** / **`P0_SEM_F158_OK`** — requires **`AZL_USE_VM` unset** (**F158**) |
| **588** | Python spine host **`p0_semantic_parse_tokens_listen_emit_with`** failed (**F158**) |
| **589** | C vs Python **`p0_semantic_parse_tokens_listen_emit_with`** stdout mismatch (**F158**) |
| **590** | C minimal **`p0_semantic_parse_tokens_listen_set`** failed, wrong stdout, or missing **`listen|f159|set|::g159|V159`** / **`P0_SEM_F159_OK`** — requires **`AZL_USE_VM` unset** (**F159**) |
| **591** | Python spine host **`p0_semantic_parse_tokens_listen_set`** failed (**F159**) |
| **592** | C vs Python **`p0_semantic_parse_tokens_listen_set`** stdout mismatch (**F159**) |
| **593** | C minimal **`p0_semantic_parse_tokens_memory_say`** failed, wrong stdout, or missing **`memory|say|F160_LINE`** / **`P0_SEM_F160_OK`** — requires **`AZL_USE_VM` unset** (**F160**) |
| **594** | Python spine host **`p0_semantic_parse_tokens_memory_say`** failed (**F160**) |
| **595** | C vs Python **`p0_semantic_parse_tokens_memory_say`** stdout mismatch (**F160**) |
| **596** | C minimal **`p0_semantic_parse_tokens_memory_set`** failed, wrong stdout, or missing **`memory|set|::f161_slot|F161_CELL`** / **`P0_SEM_F161_OK`** — requires **`AZL_USE_VM` unset** (**F161**) |
| **597** | Python spine host **`p0_semantic_parse_tokens_memory_set`** failed (**F161**) |
| **598** | C vs Python **`p0_semantic_parse_tokens_memory_set`** stdout mismatch (**F161**) |
| **599** | C minimal **`p0_semantic_parse_tokens_memory_emit`** failed, wrong stdout, or missing **`memory|emit|F162_EVT`** / **`P0_SEM_F162_OK`** — requires **`AZL_USE_VM` unset** (**F162**) |
| **600** | Python spine host **`p0_semantic_parse_tokens_memory_emit`** failed (**F162**) |
| **601** | C vs Python **`p0_semantic_parse_tokens_memory_emit`** stdout mismatch (**F162**) |
| **602** | C minimal **`p0_semantic_parse_tokens_memory_emit_with`** failed, wrong stdout, or missing **`memory|emit|f163|with|pk|pv`** / **`P0_SEM_F163_OK`** — requires **`AZL_USE_VM` unset** (**F163**) |
| **603** | Python spine host **`p0_semantic_parse_tokens_memory_emit_with`** failed (**F163**) |
| **604** | C vs Python **`p0_semantic_parse_tokens_memory_emit_with`** stdout mismatch (**F163**) |
| **605** | C minimal **`p0_semantic_parse_tokens_memory_emit_multi_with`** failed, wrong stdout, or missing **`memory|emit|m164|with|a|b|c|d`** / **`P0_SEM_F164_OK`** — requires **`AZL_USE_VM` unset** (**F164**) |
| **606** | Python spine host **`p0_semantic_parse_tokens_memory_emit_multi_with`** failed (**F164**) |
| **607** | C vs Python **`p0_semantic_parse_tokens_memory_emit_multi_with`** stdout mismatch (**F164**) |
| **608** | C minimal **`p0_semantic_parse_tokens_listen_emit_multi_with`** failed, wrong stdout, or missing **`listen|f165|emit|em165|with|a|b|c|d`** / **`P0_SEM_F165_OK`** — requires **`AZL_USE_VM` unset** (**F165**) |
| **609** | Python spine host **`p0_semantic_parse_tokens_listen_emit_multi_with`** failed (**F165**) |
| **610** | C vs Python **`p0_semantic_parse_tokens_listen_emit_multi_with`** stdout mismatch (**F165**) |
| **612** | C minimal **`p0_semantic_parse_tokens_listen_multi_say`** failed, wrong stdout, or missing **`listen|f166|say|F166_A`** / **`listen|f166|say|F166_B`** / **`P0_SEM_F166_OK`** — requires **`AZL_USE_VM` unset** (**F166**) |
| **613** | Python spine host **`p0_semantic_parse_tokens_listen_multi_say`** failed (**F166**) |
| **614** | C vs Python **`p0_semantic_parse_tokens_listen_multi_say`** stdout mismatch (**F166**) |
| **615** | C minimal **`p0_semantic_parse_tokens_listen_say_emit`** failed, wrong stdout, or missing **`listen|f167|say|F167_SAY`** / **`listen|f167|emit|F167_EMIT`** / **`P0_SEM_F167_OK`** — requires **`AZL_USE_VM` unset** (**F167**) |
| **616** | Python spine host **`p0_semantic_parse_tokens_listen_say_emit`** failed (**F167**) |
| **617** | C vs Python **`p0_semantic_parse_tokens_listen_say_emit`** stdout mismatch (**F167**) |
| **618** | C minimal **`p0_semantic_spine_structured_component_e2e`** failed, wrong stdout, or missing **`F168_INIT`** / **`F168_L`** / **`F168_M`** / **`Said: 'F168_M'`** / **`P0_SEM_F168_OK`** — requires **`AZL_USE_VM` unset** (**F168**) |
| **619** | Python spine host **`p0_semantic_spine_structured_component_e2e`** failed (**F168**) |
| **620** | C vs Python **`p0_semantic_spine_structured_component_e2e`** stdout mismatch (**F168**) |
| **621** | C minimal **`p0_semantic_spine_component_listen_say_set_emit`** failed, wrong stdout, or missing **`F169_I`** / **`F169_S`** / **`F169_M`** / **`mark`** / **`Said: ::lb169`** / **`P0_SEM_F169_OK`** — requires **`AZL_USE_VM` unset** (**F169**) |
| **622** | Python spine host **`p0_semantic_spine_component_listen_say_set_emit`** failed (**F169**) |
| **623** | C vs Python **`p0_semantic_spine_component_listen_say_set_emit`** stdout mismatch (**F169**) |
| **624** | C minimal **`p0_semantic_spine_component_listen_emit_with_payload`** failed, wrong stdout, or missing **`F170_I`** / **`F170_S`** / **`F170_CELL`** / **`F170_M`** / **`ready`** / **`Said: ::flag170`** / **`P0_SEM_F170_OK`** — requires **`AZL_USE_VM` unset** (**F170**) |
| **625** | Python spine host **`p0_semantic_spine_component_listen_emit_with_payload`** failed (**F170**) |
| **626** | C vs Python **`p0_semantic_spine_component_listen_emit_with_payload`** stdout mismatch (**F170**) |
| **627** | C minimal **`p0_semantic_parse_tokens_listen_set_emit`** failed, wrong stdout, or missing **`listen|f171|set|::g171|V171`** / **`listen|f171|emit|E171`** / **`P0_SEM_F171_OK`** — requires **`AZL_USE_VM` unset** (**F171**) |
| **628** | Python spine host **`p0_semantic_parse_tokens_listen_set_emit`** failed (**F171**) |
| **629** | C vs Python **`p0_semantic_parse_tokens_listen_set_emit`** stdout mismatch (**F171**) |
| **630** | C minimal **`p0_semantic_parse_tokens_listen_set_emit_with`** failed, wrong stdout, or missing **`listen|f172|set|::g172|V172`** / **`listen|f172|emit|E172|with|k172|v172`** / **`P0_SEM_F172_OK`** — requires **`AZL_USE_VM` unset** (**F172**) |
| **631** | Python spine host **`p0_semantic_parse_tokens_listen_set_emit_with`** failed (**F172**) |
| **632** | C vs Python **`p0_semantic_parse_tokens_listen_set_emit_with`** stdout mismatch (**F172**) |
| **768** | C minimal **`p0_semantic_parse_tokens_listen_set_emit_multi_with`** failed, wrong stdout, or missing **`listen|f173|set|::g173|V173`** / **`listen|f173|emit|E173|with|a173|b173|c173|d173`** / **`P0_SEM_F173_OK`** — requires **`AZL_USE_VM` unset** (**F173**) |
| **769** | Python spine host **`p0_semantic_parse_tokens_listen_set_emit_multi_with`** failed (**F173**) |
| **770** | C vs Python **`p0_semantic_parse_tokens_listen_set_emit_multi_with`** stdout mismatch (**F173**) |
| **771** | C minimal **`p0_semantic_parse_tokens_listen_say_set_emit`** failed, wrong stdout, or missing **`listen|f174|say|F174_A`** / **`listen|f174|set|::g174|V174`** / **`listen|f174|emit|E174`** / **`P0_SEM_F174_OK`** — requires **`AZL_USE_VM` unset** (**F174**) |
| **772** | Python spine host **`p0_semantic_parse_tokens_listen_say_set_emit`** failed (**F174**) |
| **773** | C vs Python **`p0_semantic_parse_tokens_listen_say_set_emit`** stdout mismatch (**F174**) |
| **774** | C minimal **`p0_semantic_parse_tokens_listen_emit_then_set`** failed, wrong stdout, or missing **`listen|f175|emit|E175`** / **`listen|f175|set|::g175|V175`** / **`P0_SEM_F175_OK`** — requires **`AZL_USE_VM` unset** (**F175**) |
| **775** | Python spine host **`p0_semantic_parse_tokens_listen_emit_then_set`** failed (**F175**) |
| **776** | C vs Python **`p0_semantic_parse_tokens_listen_emit_then_set`** stdout mismatch (**F175**) |
| **777** | C minimal **`p0_semantic_parse_tokens_listen_set_emit_quoted_event`** failed, wrong stdout, or missing **`listen|f179|set|::g179|V179`** / **`listen|f179|emit|E179Q|with|k179|v179`** / **`P0_SEM_F179_OK`** — requires **`AZL_USE_VM` unset** (**F179**) |
| **778** | Python spine host **`p0_semantic_parse_tokens_listen_set_emit_quoted_event`** failed (**F179**) |
| **779** | C vs Python **`p0_semantic_parse_tokens_listen_set_emit_quoted_event`** stdout mismatch (**F179**) |
| **780** | C minimal **`p0_semantic_parse_tokens_listen_set_emit_with_global_rhs`** failed, wrong stdout, or missing **`listen|f180|set|::g180|V180`** / **`listen|f180|emit|E180|with|k180|::gv180`** / **`P0_SEM_F180_OK`** — requires **`AZL_USE_VM` unset** (**F180**) |
| **781** | Python spine host **`p0_semantic_parse_tokens_listen_set_emit_with_global_rhs`** failed (**F180**) |
| **782** | C vs Python **`p0_semantic_parse_tokens_listen_set_emit_with_global_rhs`** stdout mismatch (**F180**) |
| **783** | C minimal **`p0_semantic_parse_tokens_listen_if_say`** failed, wrong stdout, or missing **`listen|f176|say|F176_INNER`** / **`P0_SEM_F176_OK`** — requires **`AZL_USE_VM` unset** (**F176**) |
| **784** | Python spine host **`p0_semantic_parse_tokens_listen_if_say`** failed (**F176**) |
| **785** | C vs Python **`p0_semantic_parse_tokens_listen_if_say`** stdout mismatch (**F176**) |
| **786** | C minimal **`p0_semantic_parse_tokens_listen_return`** failed, wrong stdout, or missing **`listen|f177|return|F177_MARK`** / **`P0_SEM_F177_OK`** — requires **`AZL_USE_VM` unset** (**F177**) |
| **787** | Python spine host **`p0_semantic_parse_tokens_listen_return`** failed (**F177**) |
| **788** | C vs Python **`p0_semantic_parse_tokens_listen_return`** stdout mismatch (**F177**) |
| **789** | C minimal **`p0_semantic_parse_tokens_memory_then_listen`** failed, wrong stdout, or missing **`memory|say|F178_MEM`** / **`listen|f178|say|F178_INNER`** / **`P0_SEM_F178_OK`** — requires **`AZL_USE_VM` unset** (**F178**) |
| **790** | Python spine host **`p0_semantic_parse_tokens_memory_then_listen`** failed (**F178**) |
| **791** | C vs Python **`p0_semantic_parse_tokens_memory_then_listen`** stdout mismatch (**F178**) |
| **792** | C minimal **`p0_semantic_execute_ast_memory_listen_return_stack`** failed, wrong stdout, or missing **`F181_WITH_PAY`** / **`F181_MEM`** / **`P0_SEM_F181_OK`** — requires **`AZL_USE_VM` unset** (**F181** `memory|listen|…|return` execute_ast stub) |
| **793** | Python spine host **`p0_semantic_execute_ast_memory_listen_return_stack`** failed (**F181**) |
| **794** | C vs Python **`p0_semantic_execute_ast_memory_listen_return_stack`** stdout mismatch (**F181**) |
| **795** | C minimal **`p0_semantic_parse_tokens_listen_nested_say`** failed, wrong stdout, or missing **`listen|f182_in|say|F182_NEST`** / **`listen|f182_out|say|F182_OUT`** / **`P0_SEM_F182_OK`** — requires **`AZL_USE_VM` unset** (**F182**) |
| **796** | Python spine host **`p0_semantic_parse_tokens_listen_nested_say`** failed (**F182**) |
| **797** | C vs Python **`p0_semantic_parse_tokens_listen_nested_say`** stdout mismatch (**F182**) |
| **798** | C minimal **`p0_semantic_parse_tokens_listen_let_say`** failed, wrong stdout, or missing **`listen|f183|let|::lv183|VAL183`** / **`listen|f183|say|F183_SAY`** / **`P0_SEM_F183_OK`** — requires **`AZL_USE_VM` unset** (**F183**) |
| **799** | Python spine host **`p0_semantic_parse_tokens_listen_let_say`** failed (**F183**) |
| **800** | C vs Python **`p0_semantic_parse_tokens_listen_let_say`** stdout mismatch (**F183**) |
| **801** | C minimal **`p0_semantic_parse_tokens_listen_call`** failed, wrong stdout, or missing **`listen|f184|call|f184_fn`** / **`P0_SEM_F184_OK`** — requires **`AZL_USE_VM` unset** (**F184**) |
| **802** | Python spine host **`p0_semantic_parse_tokens_listen_call`** failed (**F184**) |
| **803** | C vs Python **`p0_semantic_parse_tokens_listen_call`** stdout mismatch (**F184**) |
| **804** | C minimal **`p0_semantic_execute_ast_listen_call_stub`** failed, wrong stdout, or missing **`F185_TREE`** / **`F185_CALL_CB`** / **`P0_SEM_F185_OK`** — requires **`AZL_USE_VM` unset** (**F185**) |
| **805** | Python spine host **`p0_semantic_execute_ast_listen_call_stub`** failed (**F185**) |
| **806** | C vs Python **`p0_semantic_execute_ast_listen_call_stub`** stdout mismatch (**F185**) |
| **807** | C minimal **`p0_semantic_parse_tokens_listen_call_string_arg`** failed, wrong stdout, or missing **`listen|f186|call|f186_fn|F186_MARK`** / **`P0_SEM_F186_OK`** — requires **`AZL_USE_VM` unset** (**F186**) |
| **808** | Python spine host **`p0_semantic_parse_tokens_listen_call_string_arg`** failed (**F186**) |
| **809** | C vs Python **`p0_semantic_parse_tokens_listen_call_string_arg`** stdout mismatch (**F186**) |
| **810** | C minimal **`p0_semantic_execute_ast_listen_call_arg_stub`** failed, wrong stdout, or missing nine-line contract (**`F187_TREE`** … **`P0_SEM_F187_OK`**) — requires **`AZL_USE_VM` unset** (**F187** `listen|…|call|…|…` execute_ast stub) |
| **811** | Python spine host **`p0_semantic_execute_ast_listen_call_arg_stub`** failed (**F187**) |
| **812** | C vs Python **`p0_semantic_execute_ast_listen_call_arg_stub`** stdout mismatch (**F187**) |
| **813** | C minimal **`p0_semantic_parse_tokens_top_call_string_arg`** failed, wrong stdout, or missing **`call|f188_fn|F188_MARK`** / **`P0_SEM_F188_OK`** — requires **`AZL_USE_VM` unset** (**F188**) |
| **814** | Python spine host **`p0_semantic_parse_tokens_top_call_string_arg`** failed (**F188**) |
| **815** | C vs Python **`p0_semantic_parse_tokens_top_call_string_arg`** stdout mismatch (**F188**) |
| **816** | C minimal **`p0_semantic_execute_ast_top_call_arg_stub`** failed, wrong stdout, or missing nine-line contract (**`F189_TREE`** … **`P0_SEM_F189_OK`**) — requires **`AZL_USE_VM` unset** (**F189** top-level **`call|…|…`**) |
| **817** | Python spine host **`p0_semantic_execute_ast_top_call_arg_stub`** failed (**F189**) |
| **818** | C vs Python **`p0_semantic_execute_ast_top_call_arg_stub`** stdout mismatch (**F189**) |
| **819** | C minimal **`p0_semantic_parse_tokens_listen_call_ident_arg`** failed, wrong stdout, or missing **`listen|f190|call|f190_fn|::F190_ID`** / **`P0_SEM_F190_OK`** — requires **`AZL_USE_VM` unset** (**F190**) |
| **820** | Python spine host **`p0_semantic_parse_tokens_listen_call_ident_arg`** failed (**F190**) |
| **821** | C vs Python **`p0_semantic_parse_tokens_listen_call_ident_arg`** stdout mismatch (**F190**) |
| **822** | C minimal **`p0_semantic_parse_tokens_top_call_ident_arg`** failed, wrong stdout, or missing **`call|f191_fn|::F191_ID`** / **`P0_SEM_F191_OK`** — requires **`AZL_USE_VM` unset** (**F191**) |
| **823** | Python spine host **`p0_semantic_parse_tokens_top_call_ident_arg`** failed (**F191**) |
| **824** | C vs Python **`p0_semantic_parse_tokens_top_call_ident_arg`** stdout mismatch (**F191**) |
| **97** | Semantic spine owner probe failed ( **`verify_semantic_spine_owner_contract.sh`**: bad **`--semantic-owner`** exit or missing host) |
| **98** | Semantic spine owner probe stdout mismatch (expected two lines: **`AZL_SEMANTIC_SPEC_OWNER=azl/runtime/interpreter/azl_interpreter.azl`** then **`AZL_SPINE_EXEC_OWNER=minimal_runtime_python`**) |
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
| **98** | Owner stdout not exactly the two fixed **`--semantic-owner`** lines (spec path then **`AZL_SPINE_EXEC_OWNER=minimal_runtime_python`**) |
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

### Real interpreter behavior bridge on semantic spine (`scripts/verify_azl_interpreter_semantic_spine_behavior_smoke.sh`)

Tier B **P0.1c** release crumb: concatenates **`azl/tests/stubs/azl_security_for_interpreter_spine.azl`** + **`azl/tests/harness/azl_interpreter_semantic_spine_behavior_entry.azl`** + **`azl/runtime/interpreter/azl_interpreter.azl`**, runs **`tools/azl_runtime_spine_host.py`** with **`AZL_ENTRY=azl.spine.behavior.entry`**, asserts exit **0**, no **`component not found: ::azl.security`** on stderr, stdout contains **`Pure AZL Interpreter Initialized`**, **`AZL_SPINE_BEHAVIOR_ENTRY_POST_EMIT`**, substring **`Execution complete`**, at least **fifty-seven** **`Interpretation complete:`** lines (harness **`emit interpret`** ×57 — first two same **`code`** for cache exercise; third–fifth multi-line embedded **`say`**; sixth and seventh same **`say 'AZL_S6_ONLY'`** (tok_cache + ast_cache again on seven); eighth **`say 'AZL_S8_MARK'`**; ninth **`set ::…`** + **`say`** **`AZL_SPINE_P9_SET_LINE`**; tenth bare **`emit`**; eleventh **`emit … with`**; twelfth **`on`/`call`**; thirteenth **`let`**; fourteenth **`if ( true ) { say 'AZL_SPINE_P14_IF' }`** for **`::parse_if_statement`** / **`::execute_if_statement`** on the real file path; fifteenth **`if ( false ) { … } otherwise { say 'AZL_SPINE_P15_ELSE' }`**; sixteenth **`if ( false ) { … } otherwise {`** two **`say`** markers **`AZL_SPINE_P16_A`** then **`AZL_SPINE_P16_B`** in stdout order — multi-statement **`otherwise`**; seventeenth **`set ::azl_spine_p17 = true`** then **`if ( ::azl_spine_p17 ) { … } otherwise { … }`** — evaluated truthy global; eighteenth **`set ::azl_spine_p18 = false`** then **`if ( ::azl_spine_p18 ) { … } otherwise { … }`** — evaluated falsey global; nineteenth evaluated truthy **multi-statement then** (two **`say`** lines in **then**); twentieth evaluated falsey **multi-statement otherwise** (two **`say`** lines in **otherwise**); twenty-first **`if ( ::azl_spine_p21 == 1 )`** expression condition (true path); twenty-second **`if ( ::azl_spine_p22 == 2 )`** expression condition (false path → **`AZL_SPINE_P22_ELSE`**); twenty-third **`if ( ::azl_spine_p23 == 2 )`** expression **then** (two **`say`** lines, **`AZL_SPINE_P23_A`** then **`AZL_SPINE_P23_B`**); twenty-fourth **`if ( ::azl_spine_p24 == 3 )`** expression **otherwise** (two **`say`** lines, **`AZL_SPINE_P24_A`** then **`AZL_SPINE_P24_B`**); twenty-fifth two sequential **`if`** on **`::azl_spine_p25`** (**`AZL_SPINE_P25_T`** then **`AZL_SPINE_P25_F`**); twenty-sixth nested **`if`** inside **then** (**`AZL_SPINE_P26_OUTER`** then **`AZL_SPINE_P26_INNER`**, not **`BAD1`**/**`BAD2`**); twenty-seventh nested **`if`** inside **otherwise** (**`AZL_SPINE_P27_OUTER`** then **`AZL_SPINE_P27_INNER`**, not **`BAD1`**/**`BAD2`**); twenty-eighth nested **`if`** under expression outer **then** (**`::azl_spine_p28 == 2`** then inner **`== 3`** — **`AZL_SPINE_P28_OUTER`** then **`AZL_SPINE_P28_INNER`**, not **`BAD*`**); twenty-ninth three sequential **`if`** on **`::azl_spine_p29`** (**`AZL_SPINE_P29_A`** then **`B`** then **`C`**, not **`BAD1`–`BAD3`**); thirtieth multi-statement **then** on **`== 1`** plus second **`if`** **`== 2`** false → **`AZL_SPINE_P30_C`** (**`P30_A`** then **`P30_B`** then **`P30_C`**, not **`BAD*`**); thirty-first nested multi-statement **then** under evaluated outer true (**`AZL_SPINE_P31_OUTER`** then **`P31_A`** then **`P31_B`**, not **`BAD*`**); thirty-second nested multi-statement **otherwise** under evaluated outer false (**`AZL_SPINE_P32_OUTER`** then **`P32_A`** then **`P32_B`**, not **`BAD*`**); thirty-third nested **`==`** under outer **`== 1`** (**`P33_OUTER`** then **`P33_INNER`**); thirty-fourth three-level **`L1`**/**`L2`**/**`L3`**; thirty-fifth four alternating **`if`** on **`::azl_spine_p35`**; thirty-sixth expression multi-statement **then** + second **`if`** multi-statement **otherwise**; thirty-seventh **otherwise** **`OUTER`** then **`set`** inner **`INNER`**; thirty-eighth **`::azl_spine_p38`** mutation + sequential **`==`**; thirty-ninth double-nested mixed inner branches (**`P39_L1`** then **`L2`** then **`L3`**, not **`BAD1`–`BAD3`**); fortieth mixed **`==`** and **`::azl_spine_p40_flag`** (**`P40_A`** through **`D`**, not **`BAD1`–`BAD4`**); forty-first **otherwise** **`OUTER`** then **`set ::azl_spine_p41_n = 7`** + inner **`== 7`** (**`P41_OUTER`** then **`P41_INNER`**, not **`BAD1`**/**`BAD2`**); forty-second plain **`::azl_spine_p42`** then **`::azl_spine_p42_n == 8`** false → **`B`**, **`set`** false multi-statement **otherwise** (**`P42_A`** through **`D`**, not **`BAD1`–`BAD3`**); forty-third three sequential **`==`** on **`::azl_spine_p43`** with **`set`** between (**`P43_A`** then **`B`** then **`C`**, not **`BAD1`–`BAD3`**); forty-fourth outer **otherwise** **`P44_L1`** then nested **otherwise** **`L2`** then inner **then** **`L3`** (not **`BAD1`–`BAD3`**); forty-fifth outer **`== 4`** then **`set`** + inner **`== 5`** (**`P45_OUTER`** then **`P45_INNER`**, not **`BAD1`**/**`BAD2`**); forty-sixth five-way plain **`::azl_spine_p46`** alternation (**`P46_A`** through **`E`**, not **`BAD1`–`BAD5`**); forty-seventh expr true then expr false else then flag (**`P47_A`** then **`B`** then **`C`**, not **`BAD1`–`BAD3`**); forty-eighth outer **`== 8`** then inner **`== 9`** false → multi-statement **otherwise** (**`P48_OUTER`** then **`A`** then **`B`**, not **`BAD1`**/**`BAD2`**); forty-ninth outer **otherwise** **`OUTER`** then **`set`** + multi-statement **then** (**`P49_OUTER`** then **`A`** then **`B`**, not **`BAD1`**/**`BAD2`**); fiftieth three-level mixed **`==`** (**`P50_L1`** then **`L2`** then **`L3`**, not **`BAD1`–`BAD3`**); fifty-first **`P51_A`** then **`B`** then nested **otherwise** **`C`** (not **`BAD1`–`BAD3`**); fifty-second mutation flip + multi-statement **then** (**`P52_A`** through **`D`**, not **`BAD1`–`BAD3`**); fifty-third outer false **`A`**, inner true **`B`**, expr **`== 2`** false → **`C`** (not **`BAD1`–`BAD3`**); fifty-fourth long mixed five outputs (**`P54_A`** through **`E`**, not **`BAD1`–`BAD5`**); fifty-fifth embedded **`spine_component_v1`** (two **`listen`** bodies with **`say`/`set`/`emit`**, downstream listener + **`memory`** re-read of **`::azl_spine_p55_flag`**; stdout **`AZL_SPINE_P55_INIT`** then **`AZL_SPINE_P55_A`** then **`p55_chain_ok`** then **`AZL_SPINE_P55_FINAL`** then **`AZL_SPINE_P55_MEM`** then **`p55_chain_ok`**; must **not** **`AZL_SPINE_P55_BAD`**); fifty-sixth same-event multi-listener fan-out (two **`listen for 'p56_same'`** — **`P56_A`**/**`set`** then **`P56_B`**/**`say`** global/**`P56_C`**; third listener **`p56_other`** must **not** print **`AZL_SPINE_P56_BAD_OTHER`**/**`BAD_TOKEN`**; **`P56_INIT`** then **`p56_from_L1`** twice with **`memory`**); fifty-seventh **Phase E** **`spine_component_v1`** (same-event fan-out, listener **`if`** on **`::azl_spine_p57_seen`**, **`emit p57_next`**, **`memory`** re-read **`ready`**: **`AZL_SPINE_P57_INIT`** → **`A`**–**`D`** → **`MEM`** → **`ready`**, not **`P57_BAD_***`); **`if|`** + host **`execute_ast`**; stdout **`AZL_SPINE_P17_IF`**; must **not** **`AZL_SPINE_P17_BAD`**; stdout **`AZL_SPINE_P18_ELSE`**; must **not** **`AZL_SPINE_P18_BAD`**; **`AZL_SPINE_P19_A`** then **`AZL_SPINE_P19_B`**, not **`AZL_SPINE_P19_BAD`**; **`AZL_SPINE_P20_A`** then **`AZL_SPINE_P20_B`**, not **`AZL_SPINE_P20_BAD`**; stdout **`AZL_SPINE_P21_IF`**, not **`AZL_SPINE_P21_BAD`**; stdout **`AZL_SPINE_P22_ELSE`**, not **`AZL_SPINE_P22_BAD`**; **`AZL_SPINE_P23_A`** then **`AZL_SPINE_P23_B`**, not **`AZL_SPINE_P23_BAD`**; **`AZL_SPINE_P24_A`** then **`AZL_SPINE_P24_B`**, not **`AZL_SPINE_P24_BAD`**; **`AZL_SPINE_P25_T`** before **`AZL_SPINE_P25_F`**, not **`AZL_SPINE_P25_BAD1`** or **`AZL_SPINE_P25_BAD2`**; **`AZL_SPINE_P26_OUTER`** before **`AZL_SPINE_P26_INNER`**, not **`AZL_SPINE_P26_BAD1`** or **`AZL_SPINE_P26_BAD2`**; **`AZL_SPINE_P27_OUTER`** before **`AZL_SPINE_P27_INNER`**, not **`AZL_SPINE_P27_BAD1`** or **`AZL_SPINE_P27_BAD2`**; **`AZL_SPINE_P28_OUTER`** before **`AZL_SPINE_P28_INNER`**, not **`AZL_SPINE_P28_BAD1`** or **`AZL_SPINE_P28_BAD2`**; **`AZL_SPINE_P29_A`** then **`B`** then **`C`**, not **`AZL_SPINE_P29_BAD1`**/**`BAD2`**/**`BAD3`**; **`AZL_SPINE_P30_A`** then **`B`** then **`C`**, not **`AZL_SPINE_P30_BAD1`** or **`AZL_SPINE_P30_BAD2`**; **`AZL_SPINE_P31_OUTER`** then **`P31_A`** then **`P31_B`**, not **`AZL_SPINE_P31_BAD1`** or **`AZL_SPINE_P31_BAD2`**; **`AZL_SPINE_P32_OUTER`** then **`P32_A`** then **`P32_B`**, not **`AZL_SPINE_P32_BAD1`** or **`AZL_SPINE_P32_BAD2`**; **`AZL_SPINE_P33_OUTER`** before **`P33_INNER`**, not **`P33_BAD1`** or **`P33_BAD2`**; **`P34_L1`** then **`L2`** then **`L3`**, not **`P34_BAD1`**/**`BAD2`**/**`BAD3`**; **`P35_A`** then **`B`** then **`C`** then **`D`**, not **`P35_BAD1`**–**`BAD4`**; **`P36_A`** then **`B`** then **`C`** then **`D`**, not **`P36_BAD1`** or **`P36_BAD2`**; **`P37_OUTER`** before **`P37_INNER`**, not **`P37_BAD1`** or **`P37_BAD2`**; **`P38_A`** then **`B`** then **`C`**, not **`P38_BAD1`**/**`BAD2`**/**`BAD3`**; **`P39_L1`** then **`L2`** then **`L3`**, not **`P39_BAD1`**/**`BAD2`**/**`BAD3`**; **`P40_A`** then **`B`** then **`C`** then **`D`**, not **`P40_BAD1`**–**`BAD4`**; **`P41_OUTER`** before **`P41_INNER`**, not **`P41_BAD1`** or **`P41_BAD2`**; **`P42_A`** then **`B`** then **`C`** then **`D`**, not **`P42_BAD1`**/**`BAD2`**/**`BAD3`**; **`P43_A`** then **`P43_B`** then **`P43_C`**, not **`P43_BAD1`**/**`BAD2`**/**`BAD3`**; **`P44_L1`** then **`L2`** then **`L3`**, not **`P44_BAD1`**/**`BAD2`**/**`BAD3`**; **`P45_OUTER`** before **`P45_INNER`**, not **`P45_BAD1`** or **`P45_BAD2`**; **`P46_A`** then **`B`** then **`C`** then **`D`** then **`E`**, not **`P46_BAD1`**–**`BAD5`**; **`P47_A`** then **`B`** then **`C`**, not **`P47_BAD1`**/**`BAD2`**/**`BAD3`**; **`P48_OUTER`** then **`P48_A`** then **`P48_B`**, not **`P48_BAD1`** or **`P48_BAD2`**; **`P49_OUTER`** then **`P49_A`** then **`P49_B`**, not **`P49_BAD1`** or **`P49_BAD2`**; **`P50_L1`** then **`L2`** then **`L3`**, not **`P50_BAD1`**/**`BAD2`**/**`BAD3`**; **`P51_A`** then **`B`** then **`C`**, not **`P51_BAD1`**/**`BAD2`**/**`BAD3`**; **`P52_A`** then **`B`** then **`C`** then **`D`**, not **`P52_BAD1`**/**`BAD2`**/**`BAD3`**; **`P53_A`** then **`B`** then **`C`**, not **`P53_BAD1`**/**`BAD2`**/**`BAD3`**; **`P54_A`** then **`B`** then **`C`** then **`D`** then **`E`**, not **`P54_BAD1`**–**`BAD5`**; **`emit with`** must carry full **`tokens`** / **`code`** blobs so **`tokenize_complete`→`parse`** is not truncated at **255** bytes), at least **four** **`(cache hit)`** substrings, **`AZL_SPINE_DEPTH_A`** / **`AZL_SPINE_DEPTH_B`**, **`AZL_SPINE_TRIPLE_1`** / **`_2`** / **`_3`**, **`Q5a`**–**`Q5d`**, at least **two** stdout lines containing **`AZL_S6_ONLY`**, stdout **`AZL_S8_MARK`**, **`AZL_SPINE_P9_SET_LINE`**, **`AZL_SPINE_P14_IF`**, stdout **`AZL_SPINE_P15_ELSE`**, stdout must **not** contain **`AZL_SPINE_P15_BAD`**, stdout **`AZL_SPINE_P16_A`** and **`AZL_SPINE_P16_B`** with **A** before **B**, and stdout must **not** contain **`AZL_SPINE_P16_BAD`**. Python spine host **`MAX_LISTENERS`** is **256** (**`tools/azl_semantic_engine/minimal_runtime.py`**) so the harness plus embedded **`spine_component_v1`** synthetic listeners are not silently dropped at the C-minimal-sized cap (**64**). Same-event fan-out for **`spine_component_v1`**: **`process_events`** runs every matching **synthetic** listener for an event in list order; **`bh\\tseg`** rows delimit separate **`listen for`** blocks so the same event name can register more than once. Token-stream (non-synthetic) listeners still use the **first** match per dispatch so repeated nested registrations across **`interpret`** cycles are not all fired. Prefix **`ERROR[AZL_INTERPRETER_SEMANTIC_SPINE_BEHAVIOR_SMOKE]:`** on stderr.

| Exit | Meaning |
|------|---------|
| **40** | **`rg`** not found |
| **92** | **`python3`** not found |
| **548** | Required file missing (stub, harness, interpreter source, or spine host) |
| **549** | Failed to write temp combined AZL |
| **550** | Spine host non-zero exit |
| **551** | **`link ::azl.security`** still unresolved (stderr pattern) |
| **552** | Stdout missing interpreter init marker |
| **553** | Stdout missing **`AZL_SPINE_BEHAVIOR_ENTRY_POST_EMIT`** |
| **554** | Stdout missing **`Execution complete`** (execute listener did not finish after **`::execute_ast`**) |
| **555** | Stdout missing **`Interpretation complete:`** (**`execute_complete`** listener did not run) |
| **556** | Fewer than **fifty-seven** **`Interpretation complete:`** lines (harness **fifty-seven** **`emit interpret`**) |
| **557** | Fewer than **four** **`(cache hit)`** substrings (expect **two** duplicate-**`code`** pairs: **`say x`** then **`say 'AZL_S6_ONLY'`**) |
| **558** | Stdout missing **`AZL_SPINE_DEPTH_A`** or **`AZL_SPINE_DEPTH_B`** (third interpret two-line **`say`** path) |
| **559** | Stdout missing **`AZL_SPINE_TRIPLE_1`**, **`AZL_SPINE_TRIPLE_2`**, or **`AZL_SPINE_TRIPLE_3`** (fourth interpret three-line **`say`** path) |
| **560** | Stdout missing **`Q5a`**, **`Q5b`**, **`Q5c`**, or **`Q5d`** (fifth interpret four-line **`say`** path; compact markers for **`::ast.nodes`** **255**-byte budget) |
| **561** | Fewer than **two** stdout lines containing **`AZL_S6_ONLY`** (sixth + seventh interpret share the same literal **`say`**) |
| **562** | Stdout missing **`AZL_S8_MARK`** (eighth interpret single-line literal **`say`**) |
| **611** | Stdout missing **`AZL_SPINE_P9_SET_LINE`** (ninth interpret **`set ::…`** + **`say`** — **`::execute_ast`** **`set|…`** row on real file path) |
| **633** | Stdout missing **`AZL_SPINE_P14_IF`** (fourteenth interpret **`if ( true ) { say … }`** — **`::parse_if_statement`** / **`::execute_if_statement`**; spine **`::parse_tokens`** emits **`if|`**; host **`execute_ast`** branches) |
| **634** | Stdout contains **`AZL_SPINE_P15_BAD`** (fifteenth interpret skipped then-branch must not run) |
| **635** | Stdout missing **`AZL_SPINE_P15_ELSE`** (fifteenth interpret **`if ( false ) { … } otherwise { say … }`** — alternate branch; **`if|`** row + host **`execute_ast`**; meaning in **`::execute_if_statement`**) |
| **636** | Stdout contains **`AZL_SPINE_P16_BAD`** (sixteenth interpret skipped then-branch must not run) |
| **637** | Stdout missing **`AZL_SPINE_P16_A`** and/or **`AZL_SPINE_P16_B`** (sixteenth interpret multi-statement **`otherwise`**) |
| **638** | Stdout has **`AZL_SPINE_P16_B`** before **`AZL_SPINE_P16_A`** or markers missing order (expect **A** then **B**) |
| **639** | Stdout missing **`AZL_SPINE_P17_IF`** (seventeenth interpret **`set ::azl_spine_p17 = true`** then **`if ( ::azl_spine_p17 ) { … } otherwise { … }`** — evaluated condition; **`if|`** + host **`execute_ast`**) |
| **640** | Stdout contains **`AZL_SPINE_P17_BAD`** (seventeenth interpret **`otherwise`** branch must not run when global is truthy) |
| **641** | Stdout contains **`AZL_SPINE_P18_BAD`** (eighteenth interpret then-branch must not run when **`::azl_spine_p18`** is falsey) |
| **642** | Stdout missing **`AZL_SPINE_P18_ELSE`** (eighteenth interpret **`set ::azl_spine_p18 = false`** then **`if ( ::azl_spine_p18 ) … otherwise …`** — evaluated falsey **`if|`** + host **`execute_ast`**) |
| **643** | Stdout contains **`AZL_SPINE_P19_BAD`** (nineteenth interpret **`otherwise`** must not run — evaluated truthy then-branch) |
| **644** | Stdout missing **`AZL_SPINE_P19_A`** and/or **`AZL_SPINE_P19_B`** (nineteenth interpret multi-statement **then**) |
| **645** | Stdout order wrong: **`AZL_SPINE_P19_B`** before **`AZL_SPINE_P19_A`** (expect **A** then **B**) |
| **646** | Stdout contains **`AZL_SPINE_P20_BAD`** (twentieth interpret **then** must not run — evaluated falsey **otherwise**) |
| **647** | Stdout missing **`AZL_SPINE_P20_A`** and/or **`AZL_SPINE_P20_B`** (twentieth interpret multi-statement **otherwise**) |
| **648** | Stdout order wrong: **`AZL_SPINE_P20_B`** before **`AZL_SPINE_P20_A`** (expect **A** then **B**) |
| **649** | Stdout missing **`AZL_SPINE_P21_IF`** (twenty-first interpret **`if ( ::azl_spine_p21 == 1 )`** — expression condition, **`if|`** + host **`execute_ast`**) |
| **650** | Stdout contains **`AZL_SPINE_P21_BAD`** (twenty-first interpret **otherwise** must not run) |
| **651** | Stdout contains **`AZL_SPINE_P22_BAD`** (twenty-second interpret **then** must not run when **`::azl_spine_p22 == 2`** is false) |
| **652** | Stdout missing **`AZL_SPINE_P22_ELSE`** (twenty-second interpret expression false path — **`if|`** + host **`execute_ast`**) |
| **653** | Stdout contains **`AZL_SPINE_P23_BAD`** (twenty-third interpret **otherwise** must not run — expression true multi-statement **then**) |
| **654** | Stdout missing **`AZL_SPINE_P23_A`** and/or **`AZL_SPINE_P23_B`** (twenty-third interpret multi-statement **then** on **`==`**) |
| **655** | Stdout order wrong: **`AZL_SPINE_P23_B`** before **`AZL_SPINE_P23_A`** (expect **A** then **B**) |
| **656** | Stdout contains **`AZL_SPINE_P24_BAD`** (twenty-fourth interpret **then** must not run — expression false multi-statement **otherwise**) |
| **657** | Stdout missing **`AZL_SPINE_P24_A`** and/or **`AZL_SPINE_P24_B`** (twenty-fourth interpret multi-statement **otherwise** on **`==`**) |
| **658** | Stdout order wrong: **`AZL_SPINE_P24_B`** before **`AZL_SPINE_P24_A`** (expect **A** then **B**) |
| **659** | Stdout contains **`AZL_SPINE_P25_BAD1`** (twenty-fifth interpret first **`if`** must take **then**) |
| **660** | Stdout contains **`AZL_SPINE_P25_BAD2`** (twenty-fifth interpret second **`if`** must take **otherwise**) |
| **661** | Stdout missing **`AZL_SPINE_P25_T`** and/or **`AZL_SPINE_P25_F`** (twenty-fifth interpret two sequential **`if`**) |
| **662** | Stdout order wrong: **`AZL_SPINE_P25_F`** before **`AZL_SPINE_P25_T`** (expect **T** then **F**) |
| **663** | Stdout missing **`AZL_SPINE_P26_OUTER`** and/or **`AZL_SPINE_P26_INNER`** (twenty-sixth interpret nested **`if`** in **then**) |
| **664** | Stdout contains **`AZL_SPINE_P26_BAD1`** and/or **`AZL_SPINE_P26_BAD2`** (nested **`if`** in **then** must not take inner **otherwise** or outer **otherwise**) |
| **665** | Stdout order wrong: **`AZL_SPINE_P26_INNER`** before **`AZL_SPINE_P26_OUTER`** (expect **OUTER** then **INNER**) |
| **666** | Stdout missing **`AZL_SPINE_P27_OUTER`** and/or **`AZL_SPINE_P27_INNER`** (twenty-seventh interpret nested **`if`** in **otherwise**) |
| **667** | Stdout contains **`AZL_SPINE_P27_BAD1`** and/or **`AZL_SPINE_P27_BAD2`** (nested **`if`** in **otherwise** must not take wrong branches) |
| **668** | Stdout order wrong: **`AZL_SPINE_P27_INNER`** before **`AZL_SPINE_P27_OUTER`** (expect **OUTER** then **INNER**) |
| **669** | Stdout missing **`AZL_SPINE_P28_OUTER`** and/or **`AZL_SPINE_P28_INNER`** (twenty-eighth interpret nested **`if`** under expression **then**) |
| **670** | Stdout contains **`AZL_SPINE_P28_BAD1`** and/or **`AZL_SPINE_P28_BAD2`** |
| **671** | Stdout order wrong: **`AZL_SPINE_P28_INNER`** before **`AZL_SPINE_P28_OUTER`** (expect **OUTER** then **INNER**) |
| **672** | Stdout contains **`AZL_SPINE_P29_BAD1`**, **`AZL_SPINE_P29_BAD2`**, and/or **`AZL_SPINE_P29_BAD3`** (twenty-ninth interpret three sequential **`if`**) |
| **673** | Stdout missing **`AZL_SPINE_P29_A`** and/or **`AZL_SPINE_P29_B`** and/or **`AZL_SPINE_P29_C`** |
| **674** | Stdout order wrong: **`AZL_SPINE_P29_*`** not **A** then **B** then **C** |
| **675** | Stdout contains **`AZL_SPINE_P30_BAD1`** and/or **`AZL_SPINE_P30_BAD2`** (thirtieth interpret mixed multi-statement + second **`if`**) |
| **676** | Stdout missing **`AZL_SPINE_P30_A`** and/or **`AZL_SPINE_P30_B`** and/or **`AZL_SPINE_P30_C`** |
| **677** | Stdout order wrong: **`AZL_SPINE_P30_*`** not **A** then **B** then **C** |
| **678** | Stdout contains **`AZL_SPINE_P31_BAD1`** and/or **`AZL_SPINE_P31_BAD2`** (thirty-first interpret nested multi-statement **then**) |
| **679** | Stdout missing **`AZL_SPINE_P31_OUTER`** and/or **`AZL_SPINE_P31_A`** and/or **`AZL_SPINE_P31_B`** |
| **680** | Stdout order wrong: **`AZL_SPINE_P31_*`** not **OUTER** then **A** then **B** |
| **681** | Stdout contains **`AZL_SPINE_P32_BAD1`** and/or **`AZL_SPINE_P32_BAD2`** (thirty-second interpret nested multi-statement **otherwise**) |
| **682** | Stdout missing **`AZL_SPINE_P32_OUTER`** and/or **`AZL_SPINE_P32_A`** and/or **`AZL_SPINE_P32_B`** |
| **683** | Stdout order wrong: **`AZL_SPINE_P32_*`** not **OUTER** then **A** then **B** |
| **684** | Stdout contains **`AZL_SPINE_P33_BAD1`** or **`AZL_SPINE_P33_BAD2`** (thirty-third interpret nested expression) |
| **685** | Stdout missing **`AZL_SPINE_P33_OUTER`** and/or **`AZL_SPINE_P33_INNER`** |
| **686** | Stdout order wrong: **`AZL_SPINE_P33_INNER`** before **`AZL_SPINE_P33_OUTER`** |
| **687** | Stdout contains **`AZL_SPINE_P34_BAD1`**, **`AZL_SPINE_P34_BAD2`**, or **`AZL_SPINE_P34_BAD3`** (three-level nesting) |
| **688** | Stdout missing **`AZL_SPINE_P34_L1`** / **`L2`** / **`L3`** |
| **689** | Stdout order wrong: **`AZL_SPINE_P34_L*`** not **L1** then **L2** then **L3** |
| **690** | Stdout contains **`AZL_SPINE_P35_BAD1`**–**`BAD4`** (four alternating outcomes) |
| **691** | Stdout missing **`AZL_SPINE_P35_A`** / **`B`** / **`C`** / **`D`** |
| **692** | Stdout order wrong: **`AZL_SPINE_P35_*`** not **A** then **B** then **C** then **D** |
| **693** | Stdout contains **`AZL_SPINE_P36_BAD1`** or **`AZL_SPINE_P36_BAD2`** (mixed then/otherwise) |
| **694** | Stdout missing **`AZL_SPINE_P36_A`** / **`B`** / **`C`** / **`D`** |
| **695** | Stdout order wrong: **`AZL_SPINE_P36_*`** not **A** then **B** then **C** then **D** |
| **696** | Stdout contains **`AZL_SPINE_P37_BAD1`** or **`AZL_SPINE_P37_BAD2`** |
| **697** | Stdout missing **`AZL_SPINE_P37_OUTER`** and/or **`AZL_SPINE_P37_INNER`** |
| **698** | Stdout order wrong: **`AZL_SPINE_P37_INNER`** before **`AZL_SPINE_P37_OUTER`** |
| **699** | Stdout contains **`AZL_SPINE_P38_BAD1`**, **`AZL_SPINE_P38_BAD2`**, or **`AZL_SPINE_P38_BAD3`** |
| **700** | Stdout missing **`AZL_SPINE_P38_A`** / **`B`** / **`C`** |
| **701** | Stdout order wrong: **`AZL_SPINE_P38_*`** not **A** then **B** then **C** |
| **702** | Stdout contains **`AZL_SPINE_P39_BAD1`**, **`BAD2`**, or **`BAD3`** (thirty-ninth interpret double-nested mixed branches) |
| **703** | Stdout missing **`AZL_SPINE_P39_L1`** / **`L2`** / **`L3`** |
| **704** | Stdout order wrong: **`AZL_SPINE_P39_L*`** not **L1** then **L2** then **L3** |
| **705** | Stdout contains **`AZL_SPINE_P40_BAD1`**–**`BAD4`** (fortieth interpret mixed **`==`** + flag) |
| **706** | Stdout missing **`AZL_SPINE_P40_A`** / **`B`** / **`C`** / **`D`** |
| **707** | Stdout order wrong: **`AZL_SPINE_P40_*`** not **A** then **B** then **C** then **D** |
| **708** | Stdout contains **`AZL_SPINE_P41_BAD1`** or **`AZL_SPINE_P41_BAD2`** (forty-first interpret **otherwise** + **`set`** + inner **`==`**) |
| **709** | Stdout missing **`AZL_SPINE_P41_OUTER`** and/or **`AZL_SPINE_P41_INNER`** |
| **710** | Stdout order wrong: **`AZL_SPINE_P41_INNER`** before **`AZL_SPINE_P41_OUTER`** (expect **OUTER** then **INNER**) |
| **711** | Stdout contains **`AZL_SPINE_P42_BAD1`**, **`BAD2`**, or **`BAD3`** (forty-second interpret ordered mix + final multi-statement **otherwise**) |
| **712** | Stdout missing **`AZL_SPINE_P42_A`** / **`B`** / **`C`** / **`D`** |
| **713** | Stdout order wrong: **`AZL_SPINE_P42_*`** not **A** then **B** then **C** then **D** |
| **714** | Stdout contains **`AZL_SPINE_P43_BAD1`**, **`BAD2`**, or **`BAD3`** (forty-third interpret triple **`==`** after **`set`**) |
| **715** | Stdout missing **`AZL_SPINE_P43_A`** / **`B`** / **`C`** |
| **716** | Stdout order wrong: **`AZL_SPINE_P43_*`** not **A** then **B** then **C** |
| **717** | Stdout contains **`AZL_SPINE_P44_BAD1`**, **`BAD2`**, or **`BAD3`** (forty-fourth interpret nested **otherwise**/**otherwise**/**then**) |
| **718** | Stdout missing **`AZL_SPINE_P44_L1`** / **`L2`** / **`L3`** |
| **719** | Stdout order wrong: **`AZL_SPINE_P44_L*`** not **L1** then **L2** then **L3** |
| **720** | Stdout contains **`AZL_SPINE_P45_BAD1`** or **`AZL_SPINE_P45_BAD2`** (forty-fifth interpret outer then + inner **`==`** after **`set`**) |
| **721** | Stdout missing **`AZL_SPINE_P45_OUTER`** and/or **`AZL_SPINE_P45_INNER`** |
| **722** | Stdout order wrong: **`AZL_SPINE_P45_INNER`** before **`AZL_SPINE_P45_OUTER`** (expect **OUTER** then **INNER**) |
| **723** | Stdout contains **`AZL_SPINE_P46_BAD1`**–**`BAD5`** (forty-sixth interpret five-way plain alternation) |
| **724** | Stdout missing **`AZL_SPINE_P46_A`** / **`B`** / **`C`** / **`D`** / **`E`** |
| **725** | Stdout order wrong: **`AZL_SPINE_P46_*`** not **A** then **B** then **C** then **D** then **E** |
| **726** | Stdout contains **`AZL_SPINE_P47_BAD1`**, **`BAD2`**, or **`BAD3`** (forty-seventh interpret expr + flag mix) |
| **727** | Stdout missing **`AZL_SPINE_P47_A`** / **`B`** / **`C`** |
| **728** | Stdout order wrong: **`AZL_SPINE_P47_*`** not **A** then **B** then **C** |
| **729** | Stdout contains **`AZL_SPINE_P48_BAD1`** or **`AZL_SPINE_P48_BAD2`** (forty-eighth interpret outer true + inner expr false → multi-statement **otherwise**) |
| **730** | Stdout missing **`AZL_SPINE_P48_OUTER`** / **`P48_A`** / **`P48_B`** |
| **731** | Stdout order wrong: **`AZL_SPINE_P48_*`** not **OUTER** then **A** then **B** |
| **732** | Stdout contains **`AZL_SPINE_P49_BAD1`** or **`AZL_SPINE_P49_BAD2`** (forty-ninth interpret outer **otherwise** + **`set`** + multi-statement **then**) |
| **733** | Stdout missing **`AZL_SPINE_P49_OUTER`** / **`P49_A`** / **`P49_B`** |
| **734** | Stdout order wrong: **`AZL_SPINE_P49_*`** not **OUTER** then **A** then **B** |
| **735** | Stdout contains **`AZL_SPINE_P50_BAD1`**, **`BAD2`**, or **`BAD3`** (fiftieth interpret three-level mixed **`==`**) |
| **736** | Stdout missing **`AZL_SPINE_P50_L1`** / **`L2`** / **`L3`** |
| **737** | Stdout order wrong: **`AZL_SPINE_P50_L*`** not **L1** then **L2** then **L3** |
| **738** | Stdout contains **`AZL_SPINE_P51_BAD1`**, **`BAD2`**, or **`BAD3`** (fifty-first interpret ordered mix + nested **otherwise**) |
| **739** | Stdout missing **`AZL_SPINE_P51_A`** / **`B`** / **`C`** |
| **740** | Stdout order wrong: **`AZL_SPINE_P51_*`** not **A** then **B** then **C** |
| **741** | Stdout contains **`AZL_SPINE_P52_BAD1`**, **`BAD2`**, or **`BAD3`** (fifty-second interpret mutation flip + multi-statement **then**) |
| **742** | Stdout missing **`AZL_SPINE_P52_A`** / **`B`** / **`C`** / **`D`** |
| **743** | Stdout order wrong: **`AZL_SPINE_P52_*`** not **A** then **B** then **C** then **D** |
| **744** | Stdout contains **`AZL_SPINE_P53_BAD1`**, **`BAD2`**, or **`BAD3`** (fifty-third interpret outer false + inner true + expr **else**) |
| **745** | Stdout missing **`AZL_SPINE_P53_A`** / **`B`** / **`C`** |
| **746** | Stdout order wrong: **`AZL_SPINE_P53_*`** not **A** then **B** then **C** |
| **747** | Stdout contains **`AZL_SPINE_P54_BAD1`**–**`BAD5`** (fifty-fourth interpret long mixed five outputs) |
| **748** | Stdout missing **`AZL_SPINE_P54_A`** / **`B`** / **`C`** / **`D`** / **`E`** |
| **749** | Stdout order wrong: **`AZL_SPINE_P54_*`** not **A** then **B** then **C** then **D** then **E** |
| **750** | Stdout missing **`AZL_SPINE_P55_INIT`**, **`AZL_SPINE_P55_A`**, **`AZL_SPINE_P55_FINAL`**, and/or **`AZL_SPINE_P55_MEM`** (fifty-fifth interpret **`spine_component_v1`** chain on real file path) |
| **751** | Stdout contains **`AZL_SPINE_P55_BAD`** (fifty-fifth interpret wrong-path marker must not run) |
| **752** | Stdout order wrong for fifty-fifth interpret: expect **`AZL_SPINE_P55_INIT`** then **`AZL_SPINE_P55_A`** then first **`p55_chain_ok`** then **`AZL_SPINE_P55_FINAL`** then **`AZL_SPINE_P55_MEM`** then second **`p55_chain_ok`** |
| **753** | Stdout missing **`AZL_SPINE_P56_INIT`** / **`P56_A`** / **`P56_B`** / **`P56_C`** / **`P56_MEM`** (fifty-sixth interpret same-event **`spine_component_v1`** fan-out) |
| **754** | Stdout contains **`AZL_SPINE_P56_BAD_OTHER`** and/or **`AZL_SPINE_P56_BAD_TOKEN`** (wrong-event listener must not run) |
| **755** | Stdout order wrong for fifty-sixth interpret: **`P56_INIT`** → **`P56_A`** → **`P56_B`** → first **`p56_from_L1`** → **`P56_C`** → **`P56_MEM`** → second **`p56_from_L1`** |
| **756** | Stdout missing **`AZL_SPINE_P57_INIT`** / **`P57_A`** / **`P57_B`** / **`P57_C`** / **`P57_D`** / **`P57_MEM`** (fifty-seventh interpret **`spine_component_v1`** Phase **E** slice) |
| **757** | Stdout contains **`AZL_SPINE_P57_BAD_BRANCH`** and/or **`P57_BAD_OTHER`** / **`P57_BAD_TOKEN`** (wrong branch or wrong-event listener must not run) |
| **758** | Stdout order wrong for fifty-seventh interpret: **`P57_INIT`** → **`P57_A`** → **`P57_B`** → **`P57_C`** → **`P57_D`** → **`P57_MEM`** → line **`ready`** |

### Enterprise POST /v1/chat benchmark (`scripts/benchmark_enterprise_v1_chat.sh`)

Optional latency benchmark against the **enterprise** HTTP stack (**`azl/system/http_server.azl`**), not the C **`azl-native-engine`** Ollama proxy (**`/api/ollama/generate`**). Invoked from **`scripts/run_product_benchmark_suite.sh`** and, when a token is present and **`POST /v1/chat`** is not **404**, from **`scripts/run_full_repo_verification.sh`** (**`RUN_OPTIONAL_BENCHES=1`**). Prefix **`ERROR[AZL_ENTERPRISE_V1_CHAT_BENCH]:`** on stderr.

**Bash exit codes are 0–255.** Exits **91**–**95** here reuse the same integers as **gate G** (**`verify_runtime_spine_contract.sh`**) — always use **stderr** (**`ERROR[AZL_ENTERPRISE_V1_CHAT_BENCH]`**) and **which script ran** to interpret **`$?`**.

| Exit | Meaning |
|------|---------|
| **2** | **`AZL_API_TOKEN`** unset and no **`.azl/local_api_token`** (first line) |
| **91** | **`GET /healthz`** unreachable on **`127.0.0.1:${AZL_ENTERPRISE_PORT}`** (default **8080**) |
| **93** | Wrong surface: **`healthz`** is C **`azl-native-engine`**, or **`GET /api/llm/capabilities`** looks like the C engine |
| **94** | One or more benchmark **`curl`** requests failed (auth, timeout, or daemon error) |
| **95** | **`POST /v1/chat`** probe returned **404** (enterprise route not mounted on that port) |

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


