#!/usr/bin/env python3
"""
Evaluate event-name prediction using the trained LM:
- Reads tools/event_eval.jsonl with {prompt, target}
- Greedy token generation to complete the event name
- Computes exact match rate
"""

import os
import json
import argparse
import torch

import re
import real_training as rt


@torch.no_grad()
def sample_tokens(
    model: torch.nn.Module,
    idx: torch.Tensor,  # (1, T)
    max_new_tokens: int = 32,
    temperature: float = 0.8,
    top_k: int | None = 50,
    top_p: float | None = 0.9,
) -> torch.Tensor:
    model.eval()
    device = idx.device
    try:
        max_pos = int(model.module.pos_enc.pe.size(1)) if isinstance(model, torch.nn.DataParallel) else int(model.pos_enc.pe.size(1))
    except Exception:
        max_pos = 1024
    out = idx
    for _ in range(max_new_tokens):
        idx_cond = out[:, -max_pos:]
        logits = model(idx_cond)
        logits = logits[:, -1, :] / max(1e-6, temperature)
        probs = torch.softmax(logits, dim=-1)
        if top_k is not None and top_k > 0:
            k = min(top_k, probs.size(-1))
            vals, inds = torch.topk(probs, k, dim=-1)
            probs_masked = torch.zeros_like(probs).scatter(1, inds, vals)
            probs = probs_masked / torch.sum(probs_masked, dim=-1, keepdim=True)
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
    return out[0]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', default='master_training_config.json')
    parser.add_argument('--events', default='tools/event_eval.jsonl')
    parser.add_argument('--limit', type=int, default=100)
    parser.add_argument('--max-tokens', type=int, default=64)
    parser.add_argument('--temperature', type=float, default=0.5)
    parser.add_argument('--top-k', type=int, default=50)
    parser.add_argument('--top-p', type=float, default=0.9)
    parser.add_argument('--ckpt', default=None)
    args = parser.parse_args()

    cfg = rt.load_master_config(args.config)

    # Device
    want_gpu = bool(cfg.get('training', {}).get('gpu_acceleration', True)) and torch.cuda.is_available()
    device = torch.device('cuda' if want_gpu else 'cpu')

    # Checkpoint
    ckpt_dir = cfg.get('paths', {}).get('checkpoints_dir', 'checkpoints/azl_azme_gpu_training')
    ckpt_path = args.ckpt or None
    if ckpt_path is None:
        import glob
        def step_num(p: str) -> int:
            import os
            m = re.search(r'step_(\d+)\.pt', os.path.basename(p))
            return int(m.group(1)) if m else -1
        paths = glob.glob(os.path.join(ckpt_dir, 'step_*.pt'))
        if not paths:
            print(f"❌ No checkpoints in {ckpt_dir}")
            return
        paths.sort(key=step_num)
        ckpt_path = paths[-1]
    ckpt = torch.load(ckpt_path, map_location=device)
    state = ckpt.get('model_state', ckpt)

    # Infer model dimensions from checkpoint
    def get_shape(name: str):
        t = state.get(name)
        return tuple(t.shape) if t is not None else None

    embed_shape = get_shape('tok_embed.weight')  # (vocab, d_model)
    pe_shape = get_shape('pos_enc.pe')  # (1, max_len, d_model)
    d_model = embed_shape[1] if embed_shape else 512
    vocab_size = embed_shape[0] if embed_shape else 256
    max_len = pe_shape[1] if pe_shape else 512

    # Count layers
    layer_indices = set()
    layer_pat = re.compile(r'^encoder\.layers\.(\d+)\.')
    for k in state.keys():
        m = layer_pat.match(k)
        if m:
            layer_indices.add(int(m.group(1)))
    n_layer = (max(layer_indices) + 1) if layer_indices else 6

    # Choose n_head that divides d_model
    def choose_heads(dm: int) -> int:
        for h in (16, 12, 8, 6, 4, 2, 1):
            if dm % h == 0:
                return h
        return 1
    n_head = choose_heads(d_model)

    # Build model matching checkpoint
    model_cfg = {
        'model': {
            'config': {
                'hidden_size': d_model,
                'num_layers': n_layer,
                'num_heads': n_head,
                'dropout': 0.1,
                'max_seq_length': max_len,
            }
        }
    }
    tmp_cfg = {}
    tmp_cfg.update(cfg)
    tmp_cfg.update(model_cfg)
    model = rt.build_model(tmp_cfg, vocab_size=vocab_size, seq_len=min(256, max_len))
    model.to(device)
    model.load_state_dict(state, strict=False)

    # Encoding function consistent with training
    # Decide tokenizer based on checkpoint's vocab size
    if vocab_size <= 512:
        encode_fn = rt.bytes_encode
    else:
        encode_fn, _ = rt.maybe_build_sentencepiece(cfg, dataset_path=cfg.get('dataset', {}).get('path') or cfg.get('dataset_path'))

    # Evaluate
    total = 0
    correct = 0
    cov_sum = 0.0
    if not os.path.exists(args.events):
        print(f"❌ Missing events file: {args.events}")
        return
    with open(args.events, 'r', encoding='utf-8') as f:
        for line in f:
            if total >= args.limit:
                break
            rec = json.loads(line)
            prompt_text = rec['prompt']
            target = rec['target']
            prompt_ids = encode_fn(prompt_text).view(1, -1).to(device)
            out = sample_tokens(
                model,
                prompt_ids,
                max_new_tokens=min(args.max_tokens, 16 + len(target)),
                temperature=args.temperature,
                top_k=args.top_k,
                top_p=args.top_p,
            )
            # Decode using bytes if spm is unavailable
            try:
                # If sentencepiece: we can't decode easily without processor.
                # Compare by re-encoding target and prefix to token ids (prefix+target must appear at start of completion)
                tgt_ids = encode_fn(target)
                full_ids = torch.cat([prompt_ids[0].cpu(), tgt_ids.cpu()])
                # Exact token match directly after prompt
                gen = out.cpu()
                # predicted suffix equal to target ids
                pred_suffix = gen[prompt_ids.size(1):prompt_ids.size(1) + tgt_ids.numel()]
                match = torch.equal(pred_suffix, tgt_ids.cpu())
                
                # Debug output for first few examples
                if total <= 3:
                    print(f"\n🔍 Example {total + 1}:")
                    print(f"  Prompt: {prompt_text}")
                    print(f"  Target: {target}")
                    print(f"  Target IDs: {tgt_ids.tolist()}")
                    print(f"  Generated IDs: {pred_suffix.tolist()}")
                    print(f"  Match: {match}")
                    print(f"  Prompt length: {prompt_ids.size(1)}")
                    print(f"  Target length: {len(tgt_ids)}")
                    print(f"  Generated length: {len(pred_suffix)}")
                
                # token prefix coverage within the target span
                mlen = 0
                for i in range(min(len(pred_suffix), len(tgt_ids))):
                    if pred_suffix[i].item() == tgt_ids[i].item():
                        mlen += 1
                    else:
                        break
                cov = (mlen / max(1, len(tgt_ids))) * 100.0
                cov_sum += cov
            except Exception as e:
                if total <= 3:
                    print(f"\n❌ Error in example {total + 1}: {e}")
                match = False
            total += 1
            correct += int(match)

    acc = (correct / max(1, total)) * 100.0
    avg_cov = cov_sum / max(1, total)
    print(f"✅ Event prediction exact-match: {correct}/{total} = {acc:.2f}% | avg_prefix_token_coverage={avg_cov:.2f}%")


if __name__ == '__main__':
    main()


