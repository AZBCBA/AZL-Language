#!/usr/bin/env python3
"""
Deduplicate and shard the unified corpus for efficient training.

Inputs:
- datasets/real_world_training/azme_full_corpus.txt

Outputs:
- datasets/real_world_training/shards/corpus_shard_00000.txt ...
- datasets/real_world_training/shards/manifest.json

Behavior:
- Deduplicate by exact line match (memory-friendly streaming with reservoir)
- Create N shards with approximately equal line counts
- Strict: fails if input missing or empty
"""

import os
import sys
import json
from pathlib import Path
from typing import List


def write_shard(lines: List[str], out_path: Path) -> int:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        for line in lines:
            f.write(line + "\n")
    return len(lines)


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    src = repo / "datasets" / "real_world_training" / "azme_full_corpus.txt"
    shards_dir = repo / "datasets" / "real_world_training" / "shards"
    manifest = shards_dir / "manifest.json"
    num_shards = int(os.environ.get("AZME_SHARDS", "8"))

    if not src.exists() or src.stat().st_size <= 0:
        print(f"❌ Unified corpus missing or empty: {src}")
        return 1

    # Deduplicate using a set; for very large corpora this can be adapted to a disk-backed filter
    unique: List[str] = []
    seen = set()
    with open(src, "r", encoding="utf-8") as f:
        for line in f:
            s = line.rstrip("\n")
            if not s:
                continue
            if s in seen:
                continue
            seen.add(s)
            unique.append(s)

    if not unique:
        print("❌ No usable lines after deduplication.")
        return 1

    # Shard
    total = len(unique)
    per = max(1, total // num_shards)
    shards = []
    idx = 0
    for i in range(num_shards):
        start = i * per
        end = (i + 1) * per if i < num_shards - 1 else total
        part = unique[start:end]
        if not part:
            continue
        out = shards_dir / f"corpus_shard_{i:05d}.txt"
        n = write_shard(part, out)
        shards.append({"path": str(out.relative_to(repo)), "lines": n})
        idx += n

    # Manifest
    with open(manifest, "w", encoding="utf-8") as f:
        json.dump({"total_lines": total, "shards": shards}, f, indent=2)
    print(f"✅ Sharded corpus written under {shards_dir} (total_lines={total}, shards={len(shards)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())


