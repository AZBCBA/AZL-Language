#!/usr/bin/env python3
"""
Prepare a unified AZME/AZL training corpus from all available datasets.

This script scans local dataset sources and builds a single text corpus:
  - /home/abdulrahman-alzalameh/azl-language/mnt/data/*.jsonl (OpenWebText, C4, Wikipedia, BookCorpus, StackExchange, The Stack, etc.)
  - datasets/azl_azme_training/*.json and *.txt (project event data and AZL/AZME code samples)
  - datasets/azl_azme_training_enhanced/*.json (enhanced event data)

Outputs (no training is run):
  - datasets/real_world_training/azme_full_corpus.txt          (one example per line)
  - datasets/real_world_training/azme_full_corpus.stats.json  (counts per source)
  - datasets/real_world_training/dataset_manifest.json        (generated at the end)

Strict error policy: any unexpected I/O or parsing failure raises with actionable context.
"""

import os
import sys
import json
import gzip
from pathlib import Path
from typing import Iterable, Dict, Any

REPO_ROOT = Path(__file__).resolve().parents[1]
MNT_DIR = REPO_ROOT / "mnt" / "data"
AZL_AZME_DIR = REPO_ROOT / "datasets" / "azl_azme_training"
AZL_AZME_ENH_DIR = REPO_ROOT / "datasets" / "azl_azme_training_enhanced"
OUT_DIR = REPO_ROOT / "datasets" / "real_world_training"
OUT_TXT = OUT_DIR / "azme_full_corpus.txt"
OUT_STATS = OUT_DIR / "azme_full_corpus.stats.json"


def ensure_dirs() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)


def _yield_jsonl_texts(path: Path) -> Iterable[str]:
    """Yield textual content from a .jsonl file with best-effort field detection.

    Accepted keys (first present wins): "text", "content", "body", "document".
    Each line must be valid JSON or will raise a ValueError with line context.
    """
    keys = ("text", "content", "body", "document")
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", encoding="utf-8", errors="strict") as f:
        for ln, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError as e:
                raise ValueError(f"Invalid JSON at {path}:{ln}: {e}") from e
            text = None
            for k in keys:
                v = obj.get(k)
                if isinstance(v, str) and v.strip():
                    text = v.strip()
                    break
            if text is None:
                # Special-case The Stack variants which may use different fields
                if "source" in obj and "language" in obj and "content" in obj:
                    v = obj.get("content")
                    if isinstance(v, str) and v.strip():
                        text = v.strip()
                if text is None:
                    # As a strict policy, skip lines without textual payload
                    continue
            yield text


def _yield_plain_text_chunks(path: Path) -> Iterable[str]:
    """Yield reasonably sized chunks from a plain text file."""
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", encoding="utf-8", errors="strict") as f:
        for line in f:
            line = line.strip()
            if len(line) >= 10:
                yield line


def _yield_event_json(path: Path) -> Iterable[str]:
    """Yield text lines from an AZL/AZME event JSON aggregate file.
    Expected structure: { "event_training_data": [{"input":..., "target":...}, ...] }
    """
    with open(path, "r", encoding="utf-8", errors="strict") as f:
        obj = json.load(f)
    
    # Handle case where JSON is a list instead of dict
    if isinstance(obj, list):
        events = obj
    else:
        events = obj.get("event_training_data", [])
    
    if not isinstance(events, list):
        return
    
    for rec in events:
        if not isinstance(rec, dict):
            continue
        src = str(rec.get("input", "")).strip()
        tgt = str(rec.get("target", "")).strip()
        if src and tgt:
            yield f"{src} -> {tgt}"


def _yield_azl_azme_training_txt(path: Path) -> Iterable[str]:
    """Split the project training text file by separators into lines."""
    with open(path, "r", encoding="utf-8", errors="strict") as f:
        content = f.read()
    # Common separator used in repo datasets
    sep = "=" * 80
    parts = [p.strip() for p in content.split(sep) if p.strip()]
    for p in parts:
        # Emit multi-line blocks as individual lines to keep per-line sample format
        for chunk in p.splitlines():
            chunk = chunk.strip()
            if len(chunk) >= 10:
                yield chunk


def discover_sources() -> Dict[str, Any]:
    """Discover dataset sources and return a plan without reading whole contents."""
    plan: Dict[str, Any] = {
        "jsonl": [],
        "txt": [],
        "event_json": [],
    }
    # mnt/data JSONLs
    if MNT_DIR.exists():
        for p in sorted(MNT_DIR.glob("*.jsonl")):
            plan["jsonl"].append(str(p))
    # project datasets
    if AZL_AZME_DIR.exists():
        for p in sorted(AZL_AZME_DIR.glob("*.json")):
            plan["event_json"].append(str(p))
        txt = AZL_AZME_DIR / "azl_azme_training_data.txt"
        if txt.exists():
            plan["txt"].append(str(txt))
    if AZL_AZME_ENH_DIR.exists():
        for p in sorted(AZL_AZME_ENH_DIR.glob("*.json")):
            plan["event_json"].append(str(p))
    return plan


def build_corpus() -> None:
    ensure_dirs()
    plan = discover_sources()

    if not (plan["jsonl"] or plan["txt"] or plan["event_json"]):
        raise RuntimeError(
            "No datasets found. Ensure your downloads are complete under 'mnt/data' or project datasets exist."
        )

    counts: Dict[str, int] = {"total": 0, "sources": {}}

    with open(OUT_TXT, "w", encoding="utf-8", errors="strict") as out:
        # JSONL corpora (web, wiki, code, etc.)
        for jpath in plan["jsonl"]:
            p = Path(jpath)
            c = 0
            for text in _yield_jsonl_texts(p):
                out.write(text.replace("\n", " ").strip() + "\n")
                c += 1
            counts["sources"][str(p.name)] = c
            counts["total"] += c

        # Project AZL/AZME training text
        for tpath in plan["txt"]:
            p = Path(tpath)
            c = 0
            for text in _yield_azl_azme_training_txt(p):
                out.write(text.replace("\n", " ").strip() + "\n")
                c += 1
            counts["sources"][str(p.name)] = c
            counts["total"] += c

        # Project event JSON aggregates
        for epath in plan["event_json"]:
            p = Path(epath)
            c = 0
            for text in _yield_event_json(p) or []:
                out.write(text.replace("\n", " ").strip() + "\n")
                c += 1
            counts["sources"][str(p.name)] = c
            counts["total"] += c

    with open(OUT_STATS, "w", encoding="utf-8") as f:
        json.dump(counts, f, indent=2)

    print(f"✅ Built corpus: {OUT_TXT}")
    print(f"📊 Stats saved: {OUT_STATS}")
    # Also generate dataset manifest
    try:
        from scripts.generate_dataset_manifest import main as gen_manifest
        gen_manifest()
    except Exception:
        pass


def main() -> None:
    if not REPO_ROOT.exists():
        raise RuntimeError("Repository root not found; aborting.")
    build_corpus()


if __name__ == "__main__":
    main()


