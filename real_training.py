#!/usr/bin/env python3
"""
Real AZL/AZME GPU Training (PyTorch, CUDA, Multi-GPU)

- Loads dataset from master_training_config.json
- Byte-level tokenizer (UTF-8 → 0..255)
- Small Transformer LM with real gradients
- Multi-GPU via DataParallel if >1 GPU
- Saves real .pt checkpoints and logs

Run (sanity test):
  source training_env/bin/activate && python3 real_training.py --steps 300 --seq-len 256 --batch-size 32
"""

import os
import json
import math
import time
import argparse
import random
from pathlib import Path

import torch
import torch.nn as nn
import torch.nn.functional as F
from contextlib import nullcontext
from typing import Optional
import warnings
try:
    import requests  # Optional, used only if quantum hook is enabled
except Exception:
    requests = None  # type: ignore


def set_seed(seed: int = 42):
    random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)


def load_master_config(config_path: str = "master_training_config.json") -> dict:
    if not os.path.exists(config_path):
        # Minimal defaults if not found
        return {
            "dataset": {
                "path": "datasets/real_world_training/azme_full_corpus.txt",
                "preprocessing": {"val_split": 0.1},
            },
            "model": {
                "config": {
                    "hidden_size": 512,
                    "num_layers": 6,
                    "num_heads": 8,
                    "dropout": 0.1,
                    "max_seq_length": 512,
                }
            },
            "training": {
                "steps_per_epoch": 1000,
                "batch_size": 16,
                "learning_rate": 3e-4,
                "checkpoint_every": 200,
                "gpu_acceleration": True,
                "multi_gpu": True,
            },
            "paths": {
                "checkpoints_dir": "checkpoints/real_training",
                "logs_dir": "logs/real_training",
            }
        }
    with open(config_path, "r", encoding="utf-8") as f:
        cfg = json.load(f)
    # Backward-compat for minimal continuous_training config
    # Ensure expected keys exist with sane defaults
    cfg.setdefault("dataset", {})
    cfg.setdefault("model", {})
    cfg.setdefault("training", {})
    cfg.setdefault("paths", {})
    # If top-level training params are under training_params, mirror some fields
    tp = cfg.get("training_params") or cfg.get("training", {}).get("training_params")
    if isinstance(tp, dict):
        cfg["training"].setdefault("batch_size", tp.get("batch_size", 4))
        cfg["training"].setdefault("learning_rate", tp.get("learning_rate", 3e-4))
        cfg["training"].setdefault("steps_per_epoch", tp.get("max_steps_per_run", 1000))
        cfg["training"].setdefault("checkpoint_every", tp.get("checkpoint_every", 200))
    return cfg


def read_text_file(path: str) -> str:
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        return f.read()


def bytes_encode(text: str) -> torch.Tensor:
    # UTF-8 bytes → [0..255]
    b = text.encode("utf-8", errors="ignore")
    return torch.tensor(list(b), dtype=torch.long)


def ensure_dir(path: str):
    os.makedirs(path, exist_ok=True)


def maybe_build_sentencepiece(cfg: dict, dataset_path: str) -> tuple[callable, int]:
    """If cfg.tokenizer is sentencepiece, ensure model exists, return encode fn and vocab size.
    Fallback to bytes on failure.
    """
    tok_cfg = cfg.get("tokenizer") or {}
    if not tok_cfg:
        return (bytes_encode, 256)
    if str(tok_cfg.get("type", "")).lower() not in ("sp", "sentencepiece", "bpe"):
        return (bytes_encode, 256)

    try:
        import sentencepiece as spm  # type: ignore
    except Exception as e:
        print(f"⚠️ sentencepiece not available ({e}); using byte-level tokens.")
        return (bytes_encode, 256)

    model_path = tok_cfg.get("path") or "tokenizers/azl_azme_spm.model"
    vocab_size = int(tok_cfg.get("vocab_size", 8000))
    model_dir = os.path.dirname(model_path) or "."
    ensure_dir(model_dir)

    if not os.path.exists(model_path):
        # Train new tokenizer on dataset
        print(f"🛠️ Training SentencePiece tokenizer at {model_path} (vocab={vocab_size})")
        try:
            spm.SentencePieceTrainer.Train(
                input=dataset_path,
                model_prefix=os.path.splitext(model_path)[0],
                vocab_size=vocab_size,
                character_coverage=1.0,
                model_type="bpe",
                input_sentence_size=0,
                shuffle_input_sentence=False,
            )
        except Exception as e:
            print(f"❌ Failed to train sentencepiece tokenizer: {e}. Falling back to bytes.")
            return (bytes_encode, 256)

    try:
        import sentencepiece as spm  # type: ignore
        sp = spm.SentencePieceProcessor()
        sp.load(model_path)

        def sp_encode(text: str) -> torch.Tensor:
            ids = sp.encode(text, out_type=int)
            return torch.tensor(ids, dtype=torch.long)

        actual_vocab = sp.get_piece_size()
        return (sp_encode, int(actual_vocab))
    except Exception as e:
        print(f"❌ Failed to load sentencepiece model: {e}. Using bytes.")
        return (bytes_encode, 256)


def load_corpus(cfg: dict) -> tuple[torch.Tensor, torch.Tensor, int]:
    ds = cfg.get("dataset", {})
    processed = ds.get("processed", {})

    # Prefer processed train/validation if available, else use single path and split
    train_path = processed.get("train") or ds.get("path") or cfg.get("dataset_path")
    val_path = processed.get("validation")

    # Determine tokenizer and vocab
    encode_fn, vocab_size = maybe_build_sentencepiece(cfg, dataset_path=train_path)

    text = read_text_file(train_path)
    train_ids = encode_fn(text)

    if val_path and os.path.exists(val_path):
        val_text = read_text_file(val_path)
        val_ids = encode_fn(val_text)
    else:
        # Split
        val_split = float(ds.get("preprocessing", {}).get("val_split", 0.1))
        n = len(train_ids)
        n_val = max(1, int(n * val_split))
        val_ids = train_ids[-n_val:]
        train_ids = train_ids[:-n_val]

    return train_ids, val_ids, vocab_size


class ByteDataset:
    def __init__(self, data: torch.Tensor, seq_len: int):
        self.data = data
        self.seq_len = seq_len

    def sample_batch(self, batch_size: int, device: torch.device):
        # Random contiguous chunks for next-token prediction
        max_start = len(self.data) - (self.seq_len + 1)
        idx = torch.randint(0, max_start, (batch_size,))
        x = torch.stack([self.data[i:i+self.seq_len] for i in idx])
        y = torch.stack([self.data[i+1:i+self.seq_len+1] for i in idx])
        return x.to(device), y.to(device)


class EventDataset:
    def __init__(
        self,
        examples: list[dict],
        encode_fn,
        seq_len: int,
        preencoded: Optional[list[tuple[torch.Tensor, torch.Tensor]]] = None,
        lha3_memory: Optional["LHA3Memory"] = None,
        lha3_max_support: int = 0,
        lha3_sep: str = "\n\n",
    ):
        self.examples = examples
        self.encode_fn = encode_fn
        self.seq_len = seq_len
        self.lha3_memory = lha3_memory
        self.lha3_max_support = int(max(0, lha3_max_support))
        self.lha3_sep = lha3_sep
        # Pre-encode to reduce CPU/tokenizer overhead
        self.preencoded = preencoded or []
        if not self.preencoded:
            enc: list[tuple[torch.Tensor, torch.Tensor]] = []
            for rec in self.examples:
                prompt = rec.get("prompt", "")
                target = rec.get("target", "")
                try:
                    pids = self.encode_fn(prompt)
                    tids = self.encode_fn(target)
                    enc.append((pids, tids))
                except Exception:
                    continue
            self.preencoded = enc

    def sample_batch(self, batch_size: int, device: torch.device):
        # Build token sequences and labels with prompt masked (-100) and target supervised
        idxs = torch.randint(0, len(self.examples), (batch_size,))
        batch_x: list[torch.Tensor] = []
        batch_labels: list[torch.Tensor] = []
        for i in idxs:
            rec = self.examples[int(i)]
            prompt_txt = rec.get("prompt", "")
            target_txt = rec.get("target", "")
            if self.preencoded and int(i) < len(self.preencoded):
                prompt_ids, target_ids = self.preencoded[int(i)]
            else:
                prompt_ids = self.encode_fn(prompt_txt)
                target_ids = self.encode_fn(target_txt)

            # Optional LHA3 support: prepend few-shot supports as context
            support_concat = None
            if self.lha3_memory is not None and self.lha3_max_support > 0:
                try:
                    supports = self.lha3_memory.get_supports(target_txt, max_k=self.lha3_max_support)
                    chunks: list[torch.Tensor] = []
                    if supports:
                        sep_ids = self.encode_fn(self.lha3_sep)
                        for sp in supports:
                            s_prompt, s_target = sp.get("prompt", ""), sp.get("target", "")
                            s_pids = self.encode_fn(s_prompt)
                            s_tids = self.encode_fn(s_target)
                            chunks.extend([s_pids, sep_ids, s_tids, sep_ids])
                    if chunks:
                        support_concat = torch.cat(chunks, dim=0)
                except Exception:
                    support_concat = None

            if support_concat is not None and support_concat.numel() > 0:
                ids = torch.cat([support_concat, prompt_ids, target_ids], dim=0)
                support_len = support_concat.numel()
                prompt_len_effective = support_len + prompt_ids.numel()
            else:
                ids = torch.cat([prompt_ids, target_ids], dim=0)
                support_len = 0
                prompt_len_effective = prompt_ids.numel()
            # pad/truncate
            if ids.numel() < self.seq_len:
                pad = torch.zeros(self.seq_len - ids.numel(), dtype=torch.long)
                ids = torch.cat([ids, pad], dim=0)
            else:
                ids = ids[: self.seq_len]
            # Build next-token labels and mask to supervise ONLY target tokens
            # y = next-token targets for each position
            y = torch.full((self.seq_len,), -100, dtype=torch.long)
            y[:-1] = ids[1:]
            # Compute prompt/target boundaries (accounting for optional support)
            start = min(prompt_len_effective, self.seq_len - 1)
            end = min(prompt_len_effective + target_ids.numel(), self.seq_len)
            labels = torch.full((self.seq_len,), -100, dtype=torch.long)
            if end > start:
                # positions t where predicted token (t+1) lies within target region [start, end)
                t_start = max(0, start - 1)
                t_end = max(t_start, end - 1)
                if t_end > t_start:
                    labels[t_start:t_end] = y[t_start:t_end]
            batch_x.append(ids)
            batch_labels.append(labels)
        return torch.stack(batch_x, dim=0).to(device), torch.stack(batch_labels, dim=0).to(device)


class QuantumHook:
    """Strict optional quantum offload hook.

    If enabled in config and an endpoint is provided, this hook will emit
    lightweight telemetry around forward/backward phases. It does not
    replace compute. If the remote call fails, an exception is raised
    to comply with the error policy (no silent fallbacks).
    """

    def __init__(self, cfg: dict):
        q = cfg.get("quantum", {}) or {}
        self.enabled: bool = bool(q.get("enabled", False))
        self.endpoint: str = str(q.get("endpoint", ""))
        self.timeout_s: float = float(q.get("timeout_ms", 1000)) / 1000.0
        self.session = None
        if self.enabled:
            if not self.endpoint:
                raise RuntimeError("QuantumHook enabled but no endpoint provided")
            if requests is None:
                raise RuntimeError("QuantumHook requires 'requests' installed")
            self.session = requests.Session()

    def _post(self, route: str, payload: dict):
        if not self.enabled:
            return
        url = self.endpoint.rstrip('/') + '/' + route.lstrip('/')
        try:
            r = self.session.post(url, json=payload, timeout=self.timeout_s)  # type: ignore[attr-defined]
        except Exception as e:
            raise RuntimeError(f"QuantumHook POST failed: {e}")
        if not (200 <= r.status_code < 300):  # type: ignore[union-attr]
            raise RuntimeError(f"QuantumHook non-2xx status: {getattr(r,'status_code', 'NA')}")

    def on_forward_pre(self, batch_shape: tuple[int, ...]):
        self._post("forward_pre", {"batch_shape": list(batch_shape)})

    def on_forward_post(self, logits_shape: tuple[int, ...]):
        self._post("forward_post", {"logits_shape": list(logits_shape)})

    def on_backward_pre(self, step: int):
        self._post("backward_pre", {"step": int(step)})

    def on_step_post(self, step: int, loss: float):
        self._post("step_post", {"step": int(step), "loss": float(loss)})


class PositionalEncoding(nn.Module):
    def __init__(self, d_model: int, max_len: int = 4096):
        super().__init__()
        pe = torch.zeros(max_len, d_model)
        position = torch.arange(0, max_len, dtype=torch.float).unsqueeze(1)
        div_term = torch.exp(torch.arange(0, d_model, 2).float() * (-math.log(10000.0) / d_model))
        pe[:, 0::2] = torch.sin(position * div_term)
        pe[:, 1::2] = torch.cos(position * div_term)
        self.register_buffer('pe', pe.unsqueeze(0))  # (1, max_len, d_model)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x: (B, T, C)
        T = x.size(1)
        return x + self.pe[:, :T]


class TinyTransformerLM(nn.Module):
    def __init__(self, vocab_size: int, d_model: int, n_head: int, n_layer: int, dropout: float, max_seq_len: int):
        super().__init__()
        self.tok_embed = nn.Embedding(vocab_size, d_model)
        self.pos_enc = PositionalEncoding(d_model, max_len=max_seq_len)
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=d_model,
            nhead=n_head,
            dim_feedforward=d_model * 4,
            dropout=dropout,
            batch_first=True,
            activation='gelu',
        )
        self.encoder = nn.TransformerEncoder(encoder_layer, num_layers=n_layer)
        self.norm = nn.LayerNorm(d_model)
        self.head = nn.Linear(d_model, vocab_size)

    def forward(self, idx: torch.Tensor) -> torch.Tensor:
        # idx: (B, T)
        x = self.tok_embed(idx)
        x = self.pos_enc(x)
        # causal mask
        T = x.size(1)
        mask = torch.triu(torch.ones(T, T, device=x.device), diagonal=1).bool()
        x = self.encoder(x, mask)
        x = self.norm(x)
        logits = self.head(x)  # (B, T, vocab)
        return logits


def build_model(cfg: dict, vocab_size: int, seq_len: int) -> TinyTransformerLM:
    mc = cfg.get("model", {}).get("config", {})
    d_model = int(mc.get("hidden_size", 512))
    n_layer = int(mc.get("num_layers", 6))
    n_head = int(mc.get("num_heads", 8))
    dropout = float(mc.get("dropout", 0.1))
    max_seq_len = int(mc.get("max_seq_length", max(seq_len, 512)))
    max_seq_len = max(max_seq_len, seq_len)
    return TinyTransformerLM(vocab_size, d_model, n_head, n_layer, dropout, max_seq_len)


@torch.no_grad()
def evaluate_loss(model: nn.Module, dataset: ByteDataset, device: torch.device, batch_size: int) -> float:
    model.eval()
    total_loss = 0.0
    iters = 10
    for _ in range(iters):
        x, y = dataset.sample_batch(batch_size, device)
        logits = model(x)
        loss = F.cross_entropy(logits.view(-1, logits.size(-1)), y.view(-1))
        total_loss += loss.item()
    model.train()
    return total_loss / iters


def save_checkpoint(path: str, model: nn.Module, optimizer: torch.optim.Optimizer, step: int):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    state_dict = model.module.state_dict() if isinstance(model, nn.DataParallel) else model.state_dict()
    torch.save({
        "step": step,
        "model_state": state_dict,
        "optimizer_state": optimizer.state_dict(),
    }, path)


def round_multiple_of(value: int, multiple: int) -> int:
    if multiple <= 1:
        return value
    return max(multiple, (value // multiple) * multiple)


def get_gpu_mem_info() -> list[dict]:
    if not torch.cuda.is_available():
        return []
    infos = []
    prev = torch.cuda.current_device()
    for i in range(torch.cuda.device_count()):
        torch.cuda.set_device(i)
        free, total = torch.cuda.mem_get_info()
        props = torch.cuda.get_device_properties(i)
        infos.append({
            "index": i,
            "name": props.name,
            "total": total,
            "free": free,
            "used": total - free,
            "total_gb": total / 1024**3,
            "free_gb": free / 1024**3,
            "used_gb": (total - free) / 1024**3,
        })
    torch.cuda.set_device(prev)
    return infos


def choose_devices(
    gpu_infos: list[dict],
    similarity_threshold: float = 1.5,
    prefer_gpu_index: int | None = None,
) -> tuple[torch.device, list[int]]:
    """Return primary device and device_ids for DataParallel.
    If memory imbalance > similarity_threshold x, prefer single best (or preferred) GPU.
    """
    if not gpu_infos:
        return torch.device("cpu"), []
    # Sort by free memory desc
    sorted_infos = sorted(gpu_infos, key=lambda x: x["free"], reverse=True)
    # Determine primary
    best = sorted_infos[0]
    if prefer_gpu_index is not None:
        for info in sorted_infos:
            if info["index"] == prefer_gpu_index:
                best = info
                break
    if len(sorted_infos) == 1:
        return torch.device(f"cuda:{best['index']}"), [best["index"]]
    # Compute imbalance relative to primary
    max_free = best["free"]
    min_free = min(i["free"] for i in sorted_infos)
    imbalance = float(max_free) / max(1, int(min_free))
    if imbalance > similarity_threshold:
        # Use only the primary GPU to avoid DP imbalance issues
        return torch.device(f"cuda:{best['index']}"), [best["index"]]
    # Use all GPUs in sorted order
    device_ids = [info["index"] for info in sorted_infos]
    return torch.device(f"cuda:{best['index']}"), device_ids


def calibrate_batch_and_seq(
    model: nn.Module,
    device: torch.device,
    init_batch: int,
    init_seq: int,
    vocab_size: int,
    target_fraction: float,
    use_amp: bool,
) -> tuple[int, int, int]:
    """
    Returns (batch_size, seq_len, grad_accum_steps).
    Grad accum is increased to maintain tokens/update roughly constant.
    """
    if not torch.cuda.is_available():
        return init_batch, init_seq, 1

    # Prepare context
    amp_ctx = torch.cuda.amp.autocast if use_amp else nullcontext

    # Desired tokens/update baseline
    target_tokens_per_update = init_batch * init_seq
    batch_size = max(1, int(init_batch))
    seq_len = max(32, int(init_seq))
    grad_accum = 1

    # Helper for one dry-run to measure peak memory
    def try_one_pass(b: int, t: int) -> int:
        model.train()
        torch.cuda.empty_cache()
        torch.cuda.reset_peak_memory_stats()
        x = torch.randint(0, vocab_size, (b, t), device=device)
        with amp_ctx():
            logits = model(x)
            loss = F.cross_entropy(logits.view(-1, logits.size(-1)), x.view(-1))
        loss.backward()
        peak = torch.cuda.max_memory_allocated(device)
        # Cleanup grads from dry-run
        model.zero_grad(set_to_none=True)
        del x, logits, loss
        torch.cuda.empty_cache()
        return peak

    # Compute per-GPU target in bytes
    gpu_infos = get_gpu_mem_info()
    if not gpu_infos:
        return batch_size, seq_len, grad_accum

    # DataParallel splits batch across GPUs ~ evenly
    # Target per GPU: fraction of FREE mem to avoid system OOMs
    per_gpu_targets = [int(info["free"] * float(target_fraction)) for info in gpu_infos]
    per_gpu_target = max(256 * 1024**2, min(per_gpu_targets))  # be conservative, min across GPUs

    # Iterate down until it fits
    max_attempts = 20
    attempts = 0
    last_peak = 0
    while attempts < max_attempts:
        attempts += 1
        # Ensure reasonable multiples for kernels
        seq_len = int(round_multiple_of(seq_len, 8))
        # Run dry-run
        try:
            last_peak = try_one_pass(batch_size, seq_len)
        except torch.cuda.OutOfMemoryError:
            last_peak = per_gpu_target * 2  # force reduction path

        if last_peak <= per_gpu_target:
            # Fits
            break

        # Reduce in this order: batch -> seq_len -> increase grad_accum
        if batch_size > 1:
            batch_size = max(1, batch_size // 2)
            continue
        if seq_len > 64:
            seq_len = max(64, int(seq_len * 0.75))
            continue
        # Last resort: increase grad accumulation to reduce per-step memory
        grad_accum = min(32, grad_accum * 2)
        if grad_accum >= 32:
            break

    # Adjust grad_accum to approach target tokens/update
    tokens_now = batch_size * seq_len
    if tokens_now > 0 and target_tokens_per_update > tokens_now:
        need = math.ceil(target_tokens_per_update / tokens_now)
        grad_accum = max(grad_accum, min(32, need))

    return batch_size, seq_len, grad_accum


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="master_training_config.json")
    parser.add_argument("--steps", type=int, default=None)
    parser.add_argument("--batch-size", type=int, default=None)
    parser.add_argument("--seq-len", type=int, default=256)
    parser.add_argument("--lr", type=float, default=None)
    parser.add_argument("--eval-every", type=int, default=200)
    parser.add_argument("--ckpt-every", type=int, default=None)
    parser.add_argument("--outdir", default=None)
    args = parser.parse_args()

    set_seed(42)
    cfg = load_master_config(args.config)

    # Paths
    paths = cfg.get("paths", {})
    ckpt_dir = args.outdir or paths.get("checkpoints_dir", "checkpoints/real_training")
    logs_dir = paths.get("logs_dir", "logs/real_training")
    os.makedirs(ckpt_dir, exist_ok=True)
    os.makedirs(logs_dir, exist_ok=True)

    # Training params
    tr = cfg.get("training", {})
    steps = args.steps or int(tr.get("steps_per_epoch", 1000))
    batch_size = args.batch_size or int(tr.get("batch_size", 16))
    lr = args.lr or float(tr.get("learning_rate", 3e-4))
    ckpt_every = args.ckpt_every or int(tr.get("checkpoint_every", 200))
    seq_len = int(args.seq_len)
    use_compile = bool(tr.get("use_torch_compile", False))
    compile_mode = str(tr.get("compile_mode", "max-autotune"))
    amp_pref = str(tr.get("amp_dtype", "auto"))

    # Data
    train_ids, val_ids, vocab_size = load_corpus(cfg)
    # Respect config flags
    tr_cfg = cfg.get("training", {})
    want_gpu = bool(tr_cfg.get("gpu_acceleration", True))
    allow_multi = bool(tr_cfg.get("multi_gpu", True))
    device = torch.device("cuda" if (want_gpu and torch.cuda.is_available()) else "cpu")

    train_ds = ByteDataset(train_ids, seq_len)
    val_ds = ByteDataset(val_ids, seq_len)

    # CUDA heuristics and perf flags
    if torch.cuda.is_available():
        torch.backends.cuda.matmul.allow_tf32 = True
        torch.backends.cudnn.allow_tf32 = True
        torch.backends.cudnn.benchmark = True
        try:
            # Favor FlashAttention/SDPA where available
            from torch.backends.cuda import sdp_kernel  # type: ignore
            sdp_kernel(enable_flash=True, enable_math=True, enable_mem_efficient=True)
            torch.set_float32_matmul_precision('medium')
        except Exception:
            pass

    # Choose devices before model is moved
    gpu_infos = get_gpu_mem_info() if (want_gpu and torch.cuda.is_available()) else []
    if want_gpu and torch.cuda.is_available():
        # Similarity threshold can be configured; default 1.5x
        sim_th = float(cfg.get("training", {}).get(
            "multi_gpu_similarity_threshold",
            float(os.environ.get("AZL_MGPU_SIM_THRESH", 1.5))
        ))
        prefer_idx = cfg.get("training", {}).get("prefer_gpu_index", None)
        try:
            prefer_idx = int(prefer_idx) if prefer_idx is not None else None
        except Exception:
            prefer_idx = None
        primary_device, device_ids = choose_devices(gpu_infos, similarity_threshold=sim_th, prefer_gpu_index=prefer_idx)
        device = primary_device
        if device.index is not None:
            torch.cuda.set_device(device.index)
    else:
        device_ids = []

    # Model
    model = build_model(cfg, vocab_size=vocab_size, seq_len=seq_len)
    model.to(device)

    # Optional compile (Torch 2+). Does not change weights/layout.
    compiled = False
    if use_compile and hasattr(torch, "compile"):
        try:
            model = torch.compile(model, mode=compile_mode, fullgraph=False)  # type: ignore[attr-defined]
            compiled = True
        except Exception as e:
            warnings.warn(f"torch.compile failed ({e}); continuing without compile.")
            compiled = False

    # Mixed precision (AMP) for memory reduction
    use_amp = torch.cuda.is_available()
    amp_dtype = None
    if use_amp:
        if amp_pref.lower() == "bf16" and torch.cuda.is_bf16_supported():
            amp_dtype = torch.bfloat16
        elif amp_pref.lower() == "fp16":
            amp_dtype = torch.float16
        else:
            # auto: prefer bf16 if supported, else fp16
            amp_dtype = torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16

    # GPU autoscale: adjust batch/seq and grad_accum to fit into safe memory (single-device calibration)
    gpu_fraction = float(cfg.get("training", {}).get("gpu_memory_fraction", 0.8))
    if want_gpu and torch.cuda.is_available():
        batch_size, seq_len, grad_accum = calibrate_batch_and_seq(
            model, device, batch_size, seq_len, vocab_size, gpu_fraction, use_amp
        )
    else:
        grad_accum = 1

    # Respect multi_gpu policy
    if not allow_multi and device_ids:
        device_ids = [device.index] if device.index is not None else []
    # Wrap with DataParallel if we decided to use >1 device
    if want_gpu and torch.cuda.is_available() and len(device_ids) > 1:
        model = nn.DataParallel(model, device_ids=device_ids)

    # Optimizer (fused AdamW where available)
    fused_opt = bool(tr.get("optimizer", {}).get("fused", True)) if isinstance(tr.get("optimizer", {}), dict) else True
    betas = tuple(tr.get("optimizer", {}).get("betas", [0.9, 0.95])) if isinstance(tr.get("optimizer", {}), dict) else (0.9, 0.95)
    weight_decay = float(tr.get("optimizer", {}).get("weight_decay", 0.01)) if isinstance(tr.get("optimizer", {}), dict) else 0.01
    optimizer = None
    if fused_opt and torch.cuda.is_available():
        try:
            optimizer = torch.optim.AdamW(model.parameters(), lr=lr, betas=betas, weight_decay=weight_decay, fused=True)  # type: ignore[call-arg]
        except TypeError:
            optimizer = torch.optim.AdamW(model.parameters(), lr=lr, betas=betas, weight_decay=weight_decay)
    else:
        optimizer = torch.optim.AdamW(model.parameters(), lr=lr, betas=betas, weight_decay=weight_decay)

    num_gpus = len(device_ids) if (want_gpu and torch.cuda.is_available()) else 0
    print(f"🚀 Real Training | device={device} | GPUs={num_gpus or torch.cuda.device_count()} | steps={steps} | batch={batch_size} | seq={seq_len} | grad_accum={grad_accum}")
    if torch.cuda.is_available():
        for i in range(torch.cuda.device_count()):
            props = torch.cuda.get_device_properties(i)
            print(f"  - GPU{i}: {props.name} | {props.total_memory/1024**3:.1f} GB")
        if num_gpus <= 1:
            print("🎯 Multi-GPU policy: single GPU (imbalance or policy)")
        else:
            print(f"🎯 Multi-GPU policy: using devices {device_ids}")
    print(f"⚙️  AMP dtype: {getattr(amp_dtype, 'dtype', amp_dtype) if hasattr(amp_dtype,'dtype') else ('bf16' if amp_dtype is torch.bfloat16 else ('fp16' if amp_dtype is torch.float16 else 'none'))} | compile: {compiled}")

    model.train()
    ema_loss = None
    t0 = time.time()
    # Use new AMP API
    try:
        from torch import amp as _amp  # noqa: F401
        scaler = torch.amp.GradScaler('cuda', enabled=use_amp)
    except Exception:
        scaler = torch.cuda.amp.GradScaler(enabled=use_amp)

    # Optional quantum hook (strict)
    quantum = QuantumHook(cfg)

    # Optional supervised Event dataset
    event_ds = None
    event_cfg = cfg.get("supervised", {})
    event_weight = float(event_cfg.get("weight", 0.0))
    event_batch_size = int(event_cfg.get("batch_size", max(1, batch_size // 2)))
    event_max_len = int(event_cfg.get("max_len", min(256, seq_len)))
    event_path = event_cfg.get("event_prediction")
    event_only = bool(event_cfg.get("only", False))
    if event_path and os.path.exists(event_path):
        try:
            ds_cfg = cfg.get("dataset", {})
            processed = ds_cfg.get("processed", {})
            train_path = processed.get("train") or ds_cfg.get("path") or cfg.get("dataset_path")
            force_bytes = bool(event_cfg.get("force_bytes", True))
            if force_bytes:
                enc_fn = bytes_encode
            else:
                enc_fn, _ = maybe_build_sentencepiece(cfg, dataset_path=train_path)
        except Exception:
            enc_fn = bytes_encode
        examples = []
        with open(event_path, 'r', encoding='utf-8') as f:
            for line in f:
                try:
                    rec = json.loads(line)
                    if rec.get("prompt") and rec.get("target"):
                        examples.append({"prompt": rec["prompt"], "target": rec["target"]})
                except Exception:
                    continue
        if len(examples) > 0:
            # Optional LHA3-like cache path for pre-encoded event tokens
            cache_path = event_cfg.get("cache_path", "datasets/cache/event_tokens.pt")
            preencoded_pairs: Optional[list[tuple[torch.Tensor, torch.Tensor]]] = None
            try:
                if cache_path and os.path.exists(cache_path):
                    obj = torch.load(cache_path)
                    if isinstance(obj, list) and obj and isinstance(obj[0], tuple):
                        preencoded_pairs = obj
                else:
                    os.makedirs(os.path.dirname(cache_path), exist_ok=True)
            except Exception:
                preencoded_pairs = None
            # If not cached, pre-encode and save
            if preencoded_pairs is None:
                tmp_ds = EventDataset(examples, encode_fn=enc_fn, seq_len=event_max_len)
                preencoded_pairs = tmp_ds.preencoded
                try:
                    torch.save(preencoded_pairs, cache_path)
                except Exception:
                    pass
            # Optional LHA3 memory retrieval integration
            class LHA3Memory:
                def __init__(self, store: list[dict]):
                    self.store = store
                def get_supports(self, key: str, max_k: int = 3) -> list[dict]:
                    # Simple frequency-based or substring match retrieval
                    if not key:
                        return []
                    matches = []
                    k_lower = key.lower()
                    for rec in self.store:
                        tgt = str(rec.get("target", ""))
                        if tgt and (tgt.lower() == k_lower or k_lower in tgt.lower()):
                            matches.append(rec)
                            if len(matches) >= max_k:
                                break
                    return matches

            lha3_max_support = int(event_cfg.get("lha3_max_support", 0))
            lha3_sep = str(event_cfg.get("lha3_sep", "\n\n"))
            lha3_mem = LHA3Memory(examples) if lha3_max_support > 0 else None
            event_ds = EventDataset(
                examples,
                encode_fn=enc_fn,
                seq_len=event_max_len,
                preencoded=preencoded_pairs,
                lha3_memory=lha3_mem,
                lha3_max_support=lha3_max_support,
                lha3_sep=lha3_sep,
            )

    # Helper: sample tokens for multi-token event eval (top-k/top-p sampling)
    @torch.no_grad()
    def sample_tokens(model: nn.Module, idx: torch.Tensor, max_new_tokens: int = 32, temperature: float = 1.0, top_k: int | None = None, top_p: float | None = None) -> torch.Tensor:
        model.eval()
        device_local = idx.device
        try:
            max_pos_local = int(model.module.pos_enc.pe.size(1)) if isinstance(model, nn.DataParallel) else int(model.pos_enc.pe.size(1))
        except Exception:
            max_pos_local = 1024
        out = idx
        for _ in range(max_new_tokens):
            idx_cond = out[:, -max_pos_local:]
            logits = model(idx_cond)
            logits = logits[:, -1, :] / max(1e-6, temperature)
            probs = torch.softmax(logits, dim=-1)
            if top_k is not None and top_k > 0:
                k = min(top_k, probs.size(-1))
                vals, inds = torch.topk(probs, k, dim=-1)
                mask = torch.zeros_like(probs)
                probs = mask.scatter(1, inds, vals)
                probs = probs / torch.sum(probs, dim=-1, keepdim=True)
            if top_p is not None and 0.0 < top_p < 1.0:
                sorted_probs, sorted_idx = torch.sort(probs, descending=True, dim=-1)
                cumsum = torch.cumsum(sorted_probs, dim=-1)
                mask = cumsum > top_p
                mask[..., 0] = False
                filtered = sorted_probs.masked_fill(mask, 0.0)
                probs = torch.zeros_like(probs).scatter(1, sorted_idx, filtered)
                probs = probs / torch.sum(probs, dim=-1, keepdim=True)
            next_id = torch.multinomial(probs, num_samples=1)
            out = torch.cat([out, next_id], dim=1)
        return out

    # Supervised eval sampling defaults
    sup_eval_max_tokens = int(event_cfg.get("eval_max_tokens", 50))
    sup_eval_temperature = float(event_cfg.get("eval_temperature", 0.8))
    sup_eval_top_k = int(event_cfg.get("eval_top_k", 50)) if event_cfg.get("eval_top_k") is not None else None
    sup_eval_top_p = float(event_cfg.get("eval_top_p", 0.9)) if event_cfg.get("eval_top_p") is not None else None

    for step in range(1, steps + 1):
        try:
            accum_loss = 0.0
            optimizer.zero_grad(set_to_none=True)
            for micro in range(grad_accum):
                with (torch.amp.autocast('cuda', dtype=amp_dtype) if use_amp else nullcontext()):
                    if event_only and event_ds is not None:
                        ex, ey = event_ds.sample_batch(max(1, event_batch_size // grad_accum), device)
                        quantum.on_forward_pre(tuple(ex.shape))
                        elogits = model(ex)
                        quantum.on_forward_post(tuple(elogits.shape))
                        loss = F.cross_entropy(elogits.view(-1, elogits.size(-1)), ey.view(-1), ignore_index=-100)
                    else:
                        x, y = train_ds.sample_batch(batch_size, device)
                        quantum.on_forward_pre(tuple(x.shape))
                        logits = model(x)
                        quantum.on_forward_post(tuple(logits.shape))
                        loss = F.cross_entropy(logits.view(-1, logits.size(-1)), y.view(-1)) / grad_accum
                        # Optional supervised event loss
                        if event_ds is not None and event_weight > 0.0:
                            ex, ey = event_ds.sample_batch(max(1, event_batch_size // grad_accum), device)
                            quantum.on_forward_pre(tuple(ex.shape))
                            elogits = model(ex)
                            quantum.on_forward_post(tuple(elogits.shape))
                            eloss = F.cross_entropy(elogits.view(-1, elogits.size(-1)), ey.view(-1), ignore_index=-100)
                            loss = loss + (event_weight * eloss / grad_accum)
                if use_amp:
                    quantum.on_backward_pre(step)
                    scaler.scale(loss).backward()
                else:
                    quantum.on_backward_pre(step)
                    loss.backward()
                accum_loss += loss.item()

            if use_amp:
                scaler.unscale_(optimizer)
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            if use_amp:
                scaler.step(optimizer)
                scaler.update()
            else:
                optimizer.step()
            loss_item = accum_loss
        except torch.cuda.OutOfMemoryError:
            # OOM safeguard: reduce runtime settings and continue
            torch.cuda.empty_cache()
            old_b, old_t, old_g = batch_size, seq_len, grad_accum
            if batch_size > 1:
                batch_size = max(1, batch_size // 2)
            elif seq_len > 64:
                seq_len = max(64, int(seq_len * 0.8))
                train_ds.seq_len = seq_len
                val_ds.seq_len = seq_len
            elif grad_accum < 32:
                grad_accum = grad_accum * 2
            else:
                raise
            print(f"⚠️ CUDA OOM: adjusted (batch, seq, accum) {old_b},{old_t},{old_g} -> {batch_size},{seq_len},{grad_accum}")
            continue

        # Report
        ema_loss = loss_item if ema_loss is None else (0.95 * ema_loss + 0.05 * loss_item)

        if step % 20 == 0 or step == 1:
            elapsed = time.time() - t0
            tok_processed = step * batch_size * seq_len * grad_accum
            toks_per_s = tok_processed / max(1e-6, elapsed)
            print(f"🔄 step {step:5d}/{steps} | loss {loss_item:.4f} | ema {ema_loss:.4f} | toks/s {toks_per_s:,.0f}")

        if step % args.eval_every == 0:
            val_loss = evaluate_loss(model, val_ds, device, batch_size=max(1, batch_size // 2))
            msg = f"📉 eval step {step} | val_loss {val_loss:.4f}"
            # Quick event accuracy sample (multi-token decoding)
            if event_ds is not None:
                try:
                    samples = min(20, len(event_ds.examples))
                    correct = 0
                    # reuse enc_fn from construction
                    for i in range(samples):
                        rec = event_ds.examples[i]
                        prompt = rec["prompt"]
                        target = rec["target"]
                        prompt_ids = event_ds.encode_fn(prompt).view(1, -1).to(device)
                        # multi-token sample with nucleus/top-k
                        out = sample_tokens(
                            model,
                            prompt_ids,
                            max_new_tokens=max(1, min(sup_eval_max_tokens, event_max_len)),
                            temperature=sup_eval_temperature,
                            top_k=sup_eval_top_k,
                            top_p=sup_eval_top_p,
                        )[0:0]  # placeholder slice to keep shape hints, immediately overwritten below
                        # Ensure we actually have tensor output
                        out = sample_tokens(
                            model,
                            prompt_ids,
                            max_new_tokens=max(1, min(sup_eval_max_tokens, event_max_len)),
                            temperature=sup_eval_temperature,
                            top_k=sup_eval_top_k,
                            top_p=sup_eval_top_p,
                        )[0:0].new_tensor(sample_tokens(
                            model,
                            prompt_ids,
                            max_new_tokens=max(1, min(sup_eval_max_tokens, event_max_len)),
                            temperature=sup_eval_temperature,
                            top_k=sup_eval_top_k,
                            top_p=sup_eval_top_p,
                        ).detach().cpu())
                        # The above ensures we have a CPU tensor instance
                        out = sample_tokens(
                            model,
                            prompt_ids,
                            max_new_tokens=max(1, min(sup_eval_max_tokens, event_max_len)),
                            temperature=sup_eval_temperature,
                            top_k=sup_eval_top_k,
                            top_p=sup_eval_top_p,
                        ).detach().cpu()
                        tgt_ids = event_ds.encode_fn(target)
                        full_ids = torch.cat([prompt_ids[0].cpu(), tgt_ids.cpu()])
                        if out[: full_ids.numel()].equal(full_ids):
                            correct += 1
                    acc = correct / max(1, samples)
                    msg += f" | event_acc@1 {acc:.2f}"
                except Exception:
                    pass
            print(msg)

        if step % ckpt_every == 0 or step == steps:
            ckpt_path = os.path.join(ckpt_dir, f"step_{step:06d}.pt")
            save_checkpoint(ckpt_path, model, optimizer, step)
            print(f"💾 saved checkpoint: {ckpt_path}")

    print("✅ Training complete")


if __name__ == "__main__":
    main()



