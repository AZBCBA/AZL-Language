#!/usr/bin/env python3
"""
Prepare a SentencePiece tokenizer for the unified AZME corpus.

Inputs:
- datasets/real_world_training/azme_full_corpus.txt

Outputs:
- tokenizers/azl_azme_spm.model
- tokenizers/azl_azme_spm.vocab

Strict error system: fails fast on missing corpus or training error.
"""

import os
import sys
from pathlib import Path


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    corpus = repo / "datasets" / "real_world_training" / "azme_full_corpus.txt"
    tok_dir = repo / "tokenizers"
    tok_dir.mkdir(parents=True, exist_ok=True)
    model_path = tok_dir / "azl_azme_spm.model"

    if not corpus.exists() or corpus.stat().st_size <= 0:
        print(f"❌ Corpus missing or empty: {corpus}")
        return 1

    try:
        import sentencepiece as spm
    except Exception as e:
        print(f"❌ sentencepiece not installed: {e}")
        return 1

    try:
        print(f"🛠️ Training SentencePiece at {model_path} (vocab=32000)")
        spm.SentencePieceTrainer.Train(
            input=str(corpus),
            model_prefix=str(model_path.with_suffix("")),
            vocab_size=32000,
            character_coverage=1.0,
            model_type="bpe",
            input_sentence_size=0,
            shuffle_input_sentence=False,
        )
        print("✅ Tokenizer prepared.")
        return 0
    except Exception as e:
        print(f"❌ Failed to train tokenizer: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())


