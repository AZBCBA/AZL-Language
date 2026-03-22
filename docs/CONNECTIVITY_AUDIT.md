# AZL connectivity audit (top → bottom)

This document maps **what is actually wired and verified** versus **alternate entry surfaces** that assume different tools, paths, or scope. It is the single place to answer “connected vs not connected” without treating marketing copy or large `.azl` trees as proof of runtime.

---

## 1. Release truth (what CI / `RELEASE_READY` proves)

**Command:** `RUN_OPTIONAL_BENCHES=0 bash scripts/run_full_repo_verification.sh`

**Order (must all exit 0):**

| Step | Script | What it proves |
|------|--------|----------------|
| 0 | `scripts/verify_documentation_pieces.sh --promoted-only` | **`release/doc_verification_pieces.json`**: each **promoted** entry’s **`doc`** exists and its **`shell`** succeeds (Makefile **`verify`** dry-run, **`bash -n`** on listed scripts, related-doc files on disk). See **`docs/INTEGRATION_VERIFY.md`** § Trusting documentation. |
| 1 | `scripts/enforce_canonical_stack.sh` | Repo layout / stack policy |
| 2 | `scripts/check_azl_native_gates.sh` | **Gate 0:** **`scripts/self_check_release_helpers.sh`** (**`rg`**, **`jq`**, **`bash -n`**, **`azl_release_tag_policy`**, **`release/native/manifest.json`** paths). Then native-only defaults, engine build, C minimal + Python parity (F2–F165), VM tokens, spine resolver + semantic owner G2, tokenizer/brace gate, legacy-host defaults; **executable** `verify_enterprise_native_http_live.sh` |
| 3 | `scripts/verify_azl_interpreter_semantic_spine_smoke.sh` | Tier B **P0.1b**: **`azl_interpreter.azl`** **`init`** on **`minimal_runtime`** (stub **`::azl.security`**); **`docs/ERROR_SYSTEM.md`** **286–290** |
| 4 | `scripts/verify_azl_interpreter_semantic_spine_behavior_smoke.sh` | Tier B **P0.1c**: stub + harness + interpreter; **nine** **`emit interpret`** (two duplicate-**`code`** cache pairs + multi-line **`say`** + duplicate **`AZL_S6_ONLY`** + **`AZL_S8_MARK`** + **`set`+`say`** **`AZL_SPINE_P9_SET_LINE`**); **548–562**, **611** |
| 5 | `scripts/enforce_legacy_entrypoint_blocklist.sh` | Blocked legacy entrypoints stay blocked |
| 6 | `scripts/verify_native_runtime_live.sh` | **`azl-native-engine`** + **minimal** bootstrap bundle (`azl/tests/c_minimal_link_ping.azl`), HTTP **`/healthz`**, **`/readyz`**, **`/status`**, **`/api/exec_state`**, LLM honesty surface, native-only `scripts/azl` block. Default: builds engine via **`build_azl_native_engine.sh`**. **CI lcov** sets **`AZL_NATIVE_ENGINE_BIN`** to the **`gcc --coverage`** binary (required — verify otherwise replaces it and **`lcov --capture`** fails). |
| 7 | `scripts/run_all_tests.sh` | Invokes **`scripts/run_tests.sh`**: repeats minimal live verify, then **`verify_enterprise_native_http_live.sh`**, **`verify_quantum_lha3_stack.sh`** (runs **`verify_lha3_compression_honesty_contract.sh`** first — [LHA3_COMPRESSION_HONESTY.md](LHA3_COMPRESSION_HONESTY.md)), **`verify_azl_grammar_conformance.sh`**, then VM/azlpack/LSP checks |

**Layering:** Step **6** is a **fast** regression signal before the long suite. Enterprise HTTP runs inside step **7** (`run_tests.sh`) so it is not duplicated in `run_full_repo_verification.sh`. The **`start_azl_native_mode.sh`** sysproxy/wire/FIFO launcher remains validated via **`verify_azl_grammar_conformance.sh`**.

**Optional tail** (`RUN_OPTIONAL_BENCHES=1`): Ollama at `127.0.0.1:11434`, enterprise `POST /v1/chat` only if a daemon is already up and the probe is not 404/000.

### 1.1 GitHub Release automation (not in `run_full_repo_verification`)

**Out of band** on GitHub only: push tag **`v*.*.*`** or **Actions → Release → Run workflow** (input **`tag`**). Workflow **`.github/workflows/release.yml`** runs **`scripts/gh_verify_remote_tag.sh`** (dispatch only: **`jq @uri`** on **`refs/tags/<tag>`** + **`gh api`**, **`gh` stderr** on failure; **`jq`** installed on that step) → checkout → **`scripts/gh_assert_checkout_matches_tag.sh`** (**`HEAD`** = peeled **`refs/tags/<tag>^{commit}`**) → **`dist/`** → **`scripts/gh_create_sample_release.sh`** (**`gh release create`**, **`gh` stderr** on failure). Shared tag shape: **`scripts/azl_release_tag_policy.sh`**. See **`RELEASE_READY.md`** § GitHub Release, **`docs/CI_CD_PIPELINE.md`**, **`docs/ERROR_SYSTEM.md`** (shell helpers + release checkout assertion).

---

## 2. Canonical native product startup (full enterprise composition)

**Entry:** `bash scripts/start_azl_native_mode.sh`

**Chain:**

1. Sets `AZL_NATIVE_ONLY=1`, `AZL_ENABLE_LEGACY_HOST=0`, token, strict flags.
2. Resolves `AZL_NATIVE_RUNTIME_CMD` via `scripts/azl_resolve_native_runtime_cmd.sh`.
3. Builds and exports `AZL_NATIVE_EXEC_CMD` via `scripts/build_azl_native_engine.sh` if unset.
4. Optionally stops user `azme-24h.service` (Python control-plane ambiguity).
5. `exec bash scripts/start_enterprise_daemon.sh` → `exec bash scripts/run_enterprise_daemon.sh`.

**Enterprise runner** (`scripts/run_enterprise_daemon.sh`):

- Sources `scripts/azl_local_layout.sh` (logs/run dirs under `.azl/`).
- Ensures **`AZL_NATIVE_EXEC_CMD`** is set and executable (builds engine if unset — same contract as native mode starter).
- Ensures **sysproxy** on `127.0.0.1:9099` (builds `.azl/sysproxy` from `tools/sysproxy.c` if needed).
- Creates FIFOs, starts **`scripts/azl_syswire.sh`** (managed wire: `AZL_WIRE_MANAGED=1`).
- Writes a **temporary combined** `.azl` file listing many modules, then:
  - `scripts/azl_bootstrap.sh` → `scripts/build_azl_bootstrap_bundle.sh` → **`scripts/azl_seed_runner.sh`**
  - Seed runner **`exec`**s: `"${AZL_NATIVE_EXEC_CMD}" "$BUNDLE" "::boot.entry"`

**Connected:** C engine + bootstrap bundle + syscall wire + sysproxy + large AZL graph (as far as that graph parses and runs).

**Release block overlap:** **`verify_enterprise_native_http_live.sh`** (invoked from **`scripts/run_tests.sh`**, which **`run_all_tests.sh`** runs) proves the **same fat combined list** as `build_enterprise_combined.sh` reaches **C-engine HTTP** (`healthz` / `readyz` / `status` / `exec_state` / `capabilities`) with `::build.daemon.enterprise`. The **`start_azl_native_mode.sh`** path adds **sysproxy + FIFO + seed `::boot.entry`**; that variant is still exercised by **`verify_azl_grammar_conformance.sh`** (starts `start_azl_native_mode.sh` in the background).

---

## 3. Runtime spine split (two different “runtimes”)

| Role | Variable / path | Used where |
|------|-------------------|------------|
| **Executor of bootstrap bundle** | `AZL_NATIVE_EXEC_CMD` → `azl-native-engine` | `azl_seed_runner.sh` (required) |
| **Interpreter spine inside / beside the engine** | `AZL_NATIVE_RUNTIME_CMD` | Resolved by `azl_resolve_native_runtime_cmd.sh`; consumed by C engine / spine scripts per `docs/AZL_NATIVE_RUNTIME_CONTRACT.md` |

Both must be consistent with native mode; confusing them is a documented footgun (see `docs/AZL_DOCUMENTATION_CANON.md` §1.3 / bootstrap notes).

---

## 4. Python semantic spine (parity and tooling, not the enterprise foreground)

- **`tools/azl_runtime_spine_host.py`** (+ `tools/azl_semantic_engine/`) — used heavily in **gate F2/F3/F4** for **byte-identical** output vs C minimal on fixed fixtures.
- **Not** the same path as `azl_seed_runner.sh` → native engine for production daemon startup.

**Connected to quality:** yes (gates). **Connected to** `start_azl_native_mode.sh` **foreground:** no.

---

## 5. Alternate launchers (different contracts — not release-gated as a whole)

### 5.1 `launch_azme_complete.sh` (repo root)

- **Thin wrapper:** `exec bash scripts/start_azl_native_mode.sh` from repo root; **`ERROR[LAUNCH_AZME_COMPLETE]`** exit **64** if the canonical script is missing.
- Same contract as §2 (native enterprise daemon); no global **`azl`** CLI required.

### 5.2 `scripts/launch_agi_system.sh`, `scripts/launch_working_agi.sh`

- Compose their own combined files and environment (weights paths, feature flags).
- **Not** part of the documented **`run_full_repo_verification.sh`** release block (steps **0–7**) unless individually referenced by a test or gate.

### 5.3 `scripts/start_registry_server.sh`

- **`exec python3 tools/registry_server.py`** — orthogonal HTTP helper, not the native engine daemon.

---

## 6. External backends (conditional)

| Backend | When connected |
|---------|----------------|
| **Ollama** | `127.0.0.1:11434` reachable — optional benches / proxy routes in C engine |
| **llama-server / GGUF** | Binaries and env as documented in LLM audit / native engine |
| **Enterprise `/v1/chat`** | Daemon already running + token + route registered — optional bench only |

If absent, behavior should be **explicit errors or skipped optional steps**, not silent success of unrelated claims.

---

## 7. `project/` tree

- **`project/entries/`** — entry AZME material, docs, configs; human and tooling inputs.
- **`project/repo_root/`** — organized artifacts from the repo hygiene scripts.
- **Default native daemon** does not automatically load `project/entries/azl/...` unless a combined file or custom launcher includes those paths.

---

## 8. How to use this audit

1. **Ship / assert “release quality”** → only statements backed by **`run_full_repo_verification.sh`** (with optional benches called out).
2. **Run full native enterprise stack** → **`start_azl_native_mode.sh`**; inspect **`${AZL_LOGS_DIR}/daemon.out`** (or user-specific fallback) on failure.
3. **Do not** treat ad-hoc AGI `launch_*.sh` scripts under `scripts/` as release-gated unless a gate references them; **`launch_azme_complete.sh`** is an alias for **`start_azl_native_mode.sh`** only.

---

## 9. Related canonical docs

- `RELEASE_READY.md` — gate commands and environment.
- `release/native/manifest.json` — manifest entrypoints and API contract list.
- `docs/AZL_NATIVE_RUNTIME_CONTRACT.md` — runtime env and spine rules.
- `docs/AZL_DOCUMENTATION_CANON.md` — shipped vs exploratory doc index.
- `docs/LANGUAGE_REUSE_MAP.md` — what other language ecosystems inform AZL design (not runtime wiring).
