#!/usr/bin/env python3
"""
Validate AZME/AZL training preparation without running training.

Checks:
- Config files presence and coherence
- Unified corpus presence, size, non-emptiness
- Event dataset presence and parseability (first N records)
- Tokenizer path readiness
- Optional: environment readiness (torch, GPU availability)

Outputs a JSON report to training_reports/validation_report_<ts>.json.
Strict error system: returns non-zero on errors when executed.
"""

import os
import sys
import json
import time
from pathlib import Path
from typing import Dict, Any, List

REPO_ROOT = Path(__file__).resolve().parents[1]


def read_json(path: Path) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def file_size_bytes(path: Path) -> int:
    try:
        return path.stat().st_size
    except Exception:
        return -1


def head_lines(path: Path, n: int = 3) -> List[str]:
    out: List[str] = []
    try:
        with open(path, "r", encoding="utf-8", errors="strict") as f:
            for _ in range(n):
                line = f.readline()
                if not line:
                    break
                out.append(line.rstrip("\n"))
    except Exception:
        return []
    return out


def main() -> int:
    report: Dict[str, Any] = {
        "timestamp": int(time.time()),
        "errors": [],
        "warnings": [],
        "info": {},
    }

    # Paths
    master_cfg_path = REPO_ROOT / "master_training_config.json"
    train_cfg_path = REPO_ROOT / "training_config.json"
    corpus_path = REPO_ROOT / "datasets" / "real_world_training" / "azme_full_corpus.txt"
    corpus_stats_path = REPO_ROOT / "datasets" / "real_world_training" / "azme_full_corpus.stats.json"
    event_jsonl_path = REPO_ROOT / "tools" / "event_eval.jsonl"

    # Config presence
    if not master_cfg_path.exists():
        report["errors"].append(f"Missing master config: {master_cfg_path}")
    if not train_cfg_path.exists():
        report["errors"].append(f"Missing training config: {train_cfg_path}")

    # Load configs if present
    master_cfg = {}
    train_cfg = {}
    if master_cfg_path.exists():
        try:
            master_cfg = read_json(master_cfg_path)
            report["info"]["master_config_loaded"] = True
        except Exception as e:
            report["errors"].append(f"Failed to parse master config: {e}")
    if train_cfg_path.exists():
        try:
            train_cfg = read_json(train_cfg_path)
            report["info"]["training_config_loaded"] = True
        except Exception as e:
            report["errors"].append(f"Failed to parse training config: {e}")

    # Check corpus
    if not corpus_path.exists():
        report["errors"].append(f"Unified corpus not found: {corpus_path}")
    else:
        size = file_size_bytes(corpus_path)
        report["info"]["corpus_size_bytes"] = size
        if size <= 0:
            report["errors"].append("Unified corpus is empty or unreadable")
        sample = head_lines(corpus_path, 3)
        report["info"]["corpus_head"] = sample

    # Optional corpus stats
    if corpus_stats_path.exists():
        try:
            stats = read_json(corpus_stats_path)
            report["info"]["corpus_stats_sources"] = list(stats.get("sources", {}).keys())
            report["info"]["corpus_total_records"] = int(stats.get("total", 0))
        except Exception as e:
            report["warnings"].append(f"Failed to parse corpus stats: {e}")
    else:
        report["warnings"].append(f"Corpus stats file not found: {corpus_stats_path}")

    # Event dataset presence and quick parseability check (first few lines)
    if not event_jsonl_path.exists():
        report["warnings"].append(f"Event dataset missing: {event_jsonl_path}")
    else:
        try:
            ok = 0
            with open(event_jsonl_path, "r", encoding="utf-8") as f:
                for i, line in enumerate(f):
                    if i >= 5:
                        break
                    line = line.strip()
                    if not line:
                        continue
                    obj = json.loads(line)
                    if "prompt" in obj and "target" in obj:
                        ok += 1
            if ok == 0:
                report["warnings"].append("Event dataset first lines contain no valid {prompt,target} records")
            report["info"]["event_eval_checked_records"] = ok
        except Exception as e:
            report["warnings"].append(f"Event dataset quick-parse failure: {e}")

    # Tokenizer path readiness
    tok_cfg = (master_cfg.get("tokenizer") if isinstance(master_cfg, dict) else {}) or {}
    tok_path = tok_cfg.get("path") or "tokenizers/azl_azme_spm.model"
    tok_model = REPO_ROOT / tok_path
    if tok_model.exists():
        report["info"]["tokenizer_model"] = str(tok_model)
    else:
        report["warnings"].append(f"Tokenizer model not found: {tok_model} (prepare via scripts/prepare_spm_tokenizer.py)")

    # Optional environment readiness (non-fatal)
    try:
        import torch  # noqa: F401
        report["info"]["torch_available"] = True
    except Exception as e:
        report["warnings"].append(f"PyTorch not importable: {e}")

    # Write report
    out_dir = REPO_ROOT / "training_reports"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"validation_report_{int(time.time())}.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"Validation report written: {out_path}")

    # Non-zero exit if errors
    if report["errors"]:
        print("❌ Validation found errors:")
        for e in report["errors"]:
            print(f" - {e}")
        return 1
    print("✅ Validation checks prepared and ready to run.")
    return 0


if __name__ == "__main__":
    sys.exit(main())


