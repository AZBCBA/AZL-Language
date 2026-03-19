# Train a Model in Pure AZL

This tutorial walks through training a model using pure AZL components—no Python or host-language dependencies in the execution path.

## Prerequisites

- AZL native runtime: `bash scripts/start_azl_native_mode.sh`
- Optional: GPU via `AZL_HAS_GPU=1`, `AZL_NUM_GPUS=1`
- Optional: PyTorch FFI for real training: `AZL_ENABLE_TORCH_FFI=1` (spawns Python helper)

## 1. Start the Runtime

```bash
export AZL_API_TOKEN="your-token"
bash scripts/start_azl_native_mode.sh
```

Verify: `curl http://127.0.0.1:8080/healthz`

## 2. Trigger Training via API

```bash
curl -X POST -H "Authorization: Bearer $AZL_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"dataset_path":"/path/to/data","device":"cpu","epochs":1}' \
  http://127.0.0.1:8080/api/train/start
```

## 3. Pure AZL Training Flow

The training stack uses these AZL components:

| Component | Role |
|-----------|------|
| `::orchestrator.comprehensive_training_controller` | Orchestrates epochs, batches |
| `::nlp.advanced_training_system` | Data processing, metrics |
| `::neural.model_loader` | Model config, weight loading |
| `::memory.lha3_quantum` | LHA3 memory for embeddings |
| `::quantum.processor.quantum_ai_pipeline` | Quantum-enhanced forward pass |
| `::azl.core.types.tensor` | Tensor ops (create_tensor, tensor_add) |

## 4. Events

Key events for custom integration:

- `training.status` — Current step, loss, epoch
- `metrics.training.phase_done` — Phase completion
- `weights.loaded` — Model weights ready
- `log_error` — Errors (no fallbacks)

## 5. Without Torch FFI

With `AZL_ENABLE_TORCH_FFI=0`, training uses pure AZL tensor ops and quantum pipeline. For real gradient descent and large models, enable Torch FFI to spawn the Python helper.

## 6. Example: Minimal Training Script

```azl
component ::my.trainer {
  init {
    link ::orchestrator.comprehensive_training_controller
    emit process_command to ::core.command_processor with "train.advanced" {
      dataset_path: "/data/train",
      device: "cpu",
      epochs: 2
    }
  }
  behavior {
    listen for "training.status" then {
      say "Step: " + ::event.data.step + " Loss: " + ::event.data.loss
    }
  }
}
```
