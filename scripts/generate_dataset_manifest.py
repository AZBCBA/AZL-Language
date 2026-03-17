#!/usr/bin/env python3
"""
Generate a dataset manifest describing sources, sizes, and shard layout.

Inputs:
- datasets/real_world_training/azme_full_corpus.stats.json
- datasets/real_world_training/shards/manifest.json (optional if sharded)

Outputs:
- datasets/real_world_training/dataset_manifest.json
"""

import json
from pathlib import Path


def read_json(path: Path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    stats_path = repo / "datasets" / "real_world_training" / "azme_full_corpus.stats.json"
    shards_manifest = repo / "datasets" / "real_world_training" / "shards" / "manifest.json"
    out_path = repo / "datasets" / "real_world_training" / "dataset_manifest.json"

    manifest = {
        "sources": {},
        "total_records": 0,
        "shards": [],
    }

    if stats_path.exists():
        stats = read_json(stats_path)
        manifest["sources"] = stats.get("sources", {})
        manifest["total_records"] = int(stats.get("total", 0))

    if shards_manifest.exists():
        shards = read_json(shards_manifest)
        manifest["shards"] = shards.get("shards", [])
        manifest.setdefault("total_records", 0)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    print(f"Dataset manifest written: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


