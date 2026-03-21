# Related workspaces (outside this repository)

**Doc contract (verified in CI):** `RUST_OFFTREE_CONTRACT_V1` — see **`scripts/verify_rust_offtree_doc_contract.sh`**.

**AZL Language** ships **no** Rust at repo root: there is **no** canonical `Cargo.toml` / `src/lib.rs` here. Some experiments and sibling trees live on **separate disks or workspaces** on developer machines. This page records **where those paths usually are** so you do not hunt blindly.

**Adjust every path** for your host. Nothing below is required for **`make verify`** ([INTEGRATION_VERIFY.md](INTEGRATION_VERIFY.md)). **Do not** add machine-only paths to **`release/doc_verification_pieces.json`** as promoted **`shell`** lines — CI cannot see your disks; keep off-repo notes in prose here only.

---

## Why this doc exists (minimal honest scope)

- **Including Rust inside this git repo** (submodule, copy-paste) is **not** minimal until a single crate is **buildable** and **owned** (versioning, CI contract, error exits).
- **What *does* work with minimal effort:** one **in-repo index** of external locations + links to **migration inventory** that already maps Rust → AZL bridge ideas.

---

## Rust: `azme-azl` (stub; two copies observed)

On a typical AZME layout, the **same crate name** appears in at least two places:

| Role | Example path (Linux) |
|------|----------------------|
| **Primary workspace tree** | `/mnt/ssd4t/azme-workspace/rust/azme-azl` |
| **Finetune workspace (duplicate crate dir)** | `/mnt/ssd4t/azme-workspace/project/deepseek-finetune/crates/azme-azl` |

**Reality check (as of last inspection):** both trees contained an almost-empty `src/lib.rs` and **identical** `Cargo.toml` fragments. The **`azme-core`** dependency in that manifest used a **non-path string** (path-sanitization artifact), so **`cargo build` is expected to fail** until the manifest is repaired and `azme-core` resolves to a real directory or registry crate.

**Canonical rule until someone diffs and promotes one tree:** treat **`/mnt/ssd4t/azme-workspace/rust/azme-azl`** as the *nominal* primary location; verify the finetune copy before deleting either.

---

## Rust: `quantum_engine` / finetune workspace

Heavier Rust (e.g. **`quantum_engine`**, **`quantum-test-standalone`**) may live under:

`/mnt/ssd4t/azme-workspace/project/deepseek-finetune/`

That workspace is **not** wired into **`make verify`**. Integrating it belongs to a deliberate **CI + error-contract** decision, not a drive-by copy.

---

## Data and weights (do not commit)

Large artifacts (weights, datasets) are expected on **data disks**, for example under **`/mnt/ssd2t`** (names like `azl_weights`, `azl-data`, `azl_datasets`). **Do not** add multi-gigabyte trees to this git repository. Document **environment variables** and **mount points** in deployment runbooks instead.

---

## In-repo mapping (already tracked)

| Asset | Purpose |
|-------|---------|
| [migration/INVENTORY.csv](../migration/INVENTORY.csv) | Machine-local path → kind → priority → suggested AZL bridge path |
| [migration/MAPPING.md](../migration/MAPPING.md) | Conceptual map (e.g. **azme-azl** → `azme/core/azme_azl_bridge.azl`) |
| [migration/inventories/rust_azme_workspace.txt](../migration/inventories/rust_azme_workspace.txt) | Captured list of Rust `Cargo.toml` paths |

---

## Related audits

- [AZL_ENGINEERING_REALITY_AUDIT.md](AZL_ENGINEERING_REALITY_AUDIT.md) — Rust **not** in-tree; what is real vs narrative.
- [AZL_GPU_NEURAL_SURFACE_MAP.md](AZL_GPU_NEURAL_SURFACE_MAP.md) — **RepertoireField** / legacy `azl/quantum/` surface vs default runtime.
