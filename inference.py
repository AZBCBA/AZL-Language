#!/usr/bin/env python3
"""
AZL/AZME Inference CLI

- Loads latest .pt checkpoint saved by real_training.py
- Generates byte-level AZL/AZME code continuations from a prompt

Usage examples:
  source training_env/bin/activate && \
  python3 inference.py --prompt "component ::neural.core {" --max-new-tokens 200 --temperature 0.9 --top-k 50
"""

import os
import re
import glob
import argparse
import torch

from typing import Optional

import real_training as rt


def bytes_decode(ids: torch.Tensor) -> str:
    # ids: (T,) int64 in [0..255]
    b = bytes(ids.tolist())
    return b.decode('utf-8', errors='ignore')


@torch.no_grad()
def sample_tokens(
    model: torch.nn.Module,
    idx: torch.Tensor,  # (1, T)
    max_new_tokens: int = 200,
    temperature: float = 1.0,
    top_k: Optional[int] = None,
    top_p: Optional[float] = None,
) -> torch.Tensor:
    model.eval()
    device = idx.device
    # Determine model's maximum positional length
    try:
        max_pos = int(model.module.pos_enc.pe.size(1)) if isinstance(model, torch.nn.DataParallel) else int(model.pos_enc.pe.size(1))
    except Exception:
        max_pos = 1024

    for _ in range(max_new_tokens):
        # Feed last max_pos tokens
        idx_cond = idx[:, -max_pos:]
        logits = model(idx_cond)
        logits = logits[:, -1, :] / max(1e-6, temperature)
        probs = torch.softmax(logits, dim=-1)
        if top_k is not None and top_k > 0:
            k = min(top_k, probs.size(-1))
            vals, inds = torch.topk(probs, k, dim=-1)
            probs_fill = torch.zeros_like(probs).scatter(1, inds, vals)
            probs = probs_fill / torch.sum(probs_fill, dim=-1, keepdim=True)
        if top_p is not None and 0.0 < top_p < 1.0:
            sorted_probs, sorted_idx = torch.sort(probs, descending=True, dim=-1)
            cumsum = torch.cumsum(sorted_probs, dim=-1)
            mask = cumsum > top_p
            # keep the first token above threshold
            mask[..., 0] = False
            filtered = sorted_probs.masked_fill(mask, 0.0)
            probs = torch.zeros_like(probs).scatter(1, sorted_idx, filtered)
            probs = probs / torch.sum(probs, dim=-1, keepdim=True)
        next_id = torch.multinomial(probs, num_samples=1)
        idx = torch.cat([idx, next_id], dim=1)
    return idx[0]


def find_latest_checkpoint(ckpt_dir: str) -> Optional[str]:
    paths = glob.glob(os.path.join(ckpt_dir, 'step_*.pt'))
    if not paths:
        return None
    def step_num(p: str) -> int:
        m = re.search(r'step_(\d+)\.pt', os.path.basename(p))
        return int(m.group(1)) if m else -1
    paths.sort(key=step_num)
    return paths[-1]


def main():
    parser = argparse.ArgumentParser(description="AZL/AZME Inference")
    parser.add_argument('--config', default='training_config.json', help='config file used during training')
    parser.add_argument('--prompt', required=True, help='initial prompt text')
    parser.add_argument('--max-new-tokens', type=int, default=200)
    parser.add_argument('--temperature', type=float, default=0.8)
    parser.add_argument('--top-k', type=int, default=50)
    parser.add_argument('--top-p', type=float, default=None)
    parser.add_argument('--ckpt', default=None, help='path to a checkpoint .pt (optional)')
    args = parser.parse_args()

    cfg = rt.load_master_config(args.config)
    ckpt_dir = cfg.get('paths', {}).get('checkpoints_dir', 'checkpoints/azl_azme_gpu_training')
    if args.ckpt is not None:
        ckpt_path = args.ckpt
    else:
        ckpt_path = find_latest_checkpoint(ckpt_dir)
    if ckpt_path is None or not os.path.exists(ckpt_path):
        print(f"❌ No checkpoint found in {ckpt_dir}")
        return

    # Device selection (prefer GPU if available)
    want_gpu = bool(cfg.get('training', {}).get('gpu_acceleration', True)) and torch.cuda.is_available()
    device = torch.device('cuda' if want_gpu else 'cpu')
    if want_gpu:
        prefer_idx = cfg.get('training', {}).get('prefer_gpu_index', None)
        if prefer_idx is not None:
            try:
                torch.cuda.set_device(int(prefer_idx))
                device = torch.device(f'cuda:{int(prefer_idx)}')
            except Exception:
                pass

    # Build model matching training defaults/config
    seq_len = 256
    vocab_size = 256
    model = rt.build_model(cfg, vocab_size=vocab_size, seq_len=seq_len)
    model.to(device)

    # Load checkpoint
    ckpt = torch.load(ckpt_path, map_location=device)
    state = ckpt.get('model_state', ckpt)
    try:
        model.load_state_dict(state)
    except Exception as e:
        print(f"⚠️  Failed to load state dict strictly: {e}. Trying non-strict...")
        model.load_state_dict(state, strict=False)

    # Encode prompt to bytes
    prompt_ids = rt.bytes_encode(args.prompt)
    prompt_ids = prompt_ids.view(1, -1).to(device)

    # Generate
    out = sample_tokens(
        model,
        prompt_ids,
        max_new_tokens=args.max_new_tokens,
        temperature=args.temperature,
        top_k=args.top_k,
        top_p=args.top_p,
    )

    # Decode and show
    print("\n===== GENERATED START =====\n")
    print(bytes_decode(out.detach().cpu()))
    print("\n===== GENERATED END =====\n")


if __name__ == '__main__':
    main()


