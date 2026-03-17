# Migration Mapping (Rust/Python → AZL)

## Principles
- Replace IO with Virtual OS (fs/http via `azl/system/azl_system_interface.azl` and stdlib wrappers)
- Replace concurrency with event-driven behaviors and deterministic queues
- Enforce AzlError propagation and strict policy (AZL_STRICT=1)
- No partial ports: module enters only when tested and integrated

## Wave 1 (P1)
- azme-core (Rust) → `azme/core/agi_core.azl` extensions and `azme/core/azme_aba_bridge.azl` surfaces
- azme-azl (Rust) → `azme/core/azme_azl_bridge.azl` utility functions and adapters

## Wave 2 (P2)
- azme-memory (Rust) → `azme/neural/azme_model_registry.azl` + `azme/core/autonomous_brain.azl` memory interfaces
- azme-optimization (Rust) → `azme/optimizer/azme_execution_optimizer.azl` refinements and PGO data ingestion

## Wave 3 (P3)
- azme-quantum (Rust) → `azme/specialized/azme_quantum_optimizer.azl` & `azl/quantum/processor` integration points
- deepseek-finetune (Python) → `azme/learning/azme_deepseek_pipeline.azl` using virtual FS/HTTP

## Deletions (post-verify)
- Remove original Rust/Python sources from this repo only after AZL equivalents pass tests and are referenced by runtime; keep external backups indexed in `migration/INVENTORY.csv`.

