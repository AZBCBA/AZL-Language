#!/usr/bin/env python3
"""
Pre-encode event dataset to speed up supervised losses during training.

Inputs:
- tools/event_eval.jsonl (JSONL with {"prompt","target"})
- Optional tokenizer: tokenizers/azl_azme_spm.model (if present and force_bytes=False)

Outputs:
- datasets/cache/event_tokens.pt (list of (prompt_ids, target_ids) tensors)

No training or models are run. This is a pure data preprocessing step.
"""

import os
import json
from pathlib import Path
from typing import List, Tuple

import torch


def bytes_encode(text: str) -> torch.Tensor:
    b = text.encode("utf-8", errors="ignore")
    return torch.tensor(list(b), dtype=torch.long)


def maybe_load_spm(repo: Path):
    model_path = repo / "tokenizers" / "azl_azme_spm.model"
    if not model_path.exists():
        return None
    try:
        import sentencepiece as spm
        sp = spm.SentencePieceProcessor()
        sp.load(str(model_path))
        return sp
    except Exception:
        return None


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    event_path = repo / "tools" / "event_eval.jsonl"
    out_path = repo / "datasets" / "cache" / "event_tokens.pt"
    out_path.parent.mkdir(parents=True, exist_ok=True)

    if not event_path.exists():
        print(f"❌ Event dataset not found: {event_path}")
        return 1

    sp = maybe_load_spm(repo)
    def sp_encode(text: str) -> torch.Tensor:
        ids = sp.encode(text, out_type=int)  # type: ignore[union-attr]
        return torch.tensor(ids, dtype=torch.long)

    # If SPM exists, use it; else use bytes
    encode_fn = sp_encode if sp is not None else bytes_encode

    pairs: List[Tuple[torch.Tensor, torch.Tensor]] = []
    with open(event_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            prompt = str(obj.get("prompt", ""))
            target = str(obj.get("target", ""))
            if not prompt or not target:
                continue
            p = encode_fn(prompt)
            t = encode_fn(target)
            pairs.append((p, t))

    if not pairs:
        print("❌ No encodable pairs found in event dataset.")
        return 1

    torch.save(pairs, out_path)
    print(f"✅ Pre-encoded {len(pairs)} event pairs to {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


