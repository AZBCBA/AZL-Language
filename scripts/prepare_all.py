#!/usr/bin/env python3
"""
Run the full AZME/AZL preparation pipeline without training:

1) Build unified corpus and stats
2) Train SentencePiece tokenizer (optional; skips if not installed)
3) Deduplicate and shard corpus; generate dataset manifest
4) Pre-encode event tokens cache
5) Generate hardware profile
6) Validate setup

Each step is isolated and failures are reported clearly. No training is started.
"""

import subprocess
import sys
from pathlib import Path


def run(cmd: list[str]) -> None:
    print("→", " ".join(cmd))
    res = subprocess.run(cmd)
    if res.returncode != 0:
        raise SystemExit(res.returncode)


def main() -> int:
    repo = Path(__file__).resolve().parents[1]

    # 1) Build corpus and stats
    run(["python3", str(repo / "scripts" / "prepare_azme_full_corpus.py")])

    # 2) Train tokenizer (optional; skip failure)
    try:
        run(["python3", str(repo / "scripts" / "prepare_spm_tokenizer.py")])
    except SystemExit as e:
        print(f"Tokenizer step skipped/failed with code {e.code}")

    # 3) Deduplicate and shard, then dataset manifest
    run(["python3", str(repo / "scripts" / "dedupe_and_shard_corpus.py")])
    run(["python3", str(repo / "scripts" / "generate_dataset_manifest.py")])

    # 4) Pre-encode event tokens cache (optional, but recommended)
    try:
        run(["python3", str(repo / "scripts" / "preencode_event_tokens.py")])
    except SystemExit as e:
        print(f"Pre-encode step skipped/failed with code {e.code}")

    # 5) Hardware profile
    run(["python3", str(repo / "scripts" / "hw_profile.py")])

    # 6) Validate
    run(["python3", str(repo / "scripts" / "validate_training_setup.py")])

    print("\n✅ Preparation pipeline completed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


