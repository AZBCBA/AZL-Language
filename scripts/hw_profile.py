#!/usr/bin/env python3
"""
Report current hardware profile and suggested training parameters (no training).
Outputs a small JSON file with CPU, RAM, and GPU info to training_reports/hw_profile.json.
"""

import json
from pathlib import Path


def main() -> int:
    info = {"cpu": {}, "memory": {}, "gpus": []}
    try:
        import psutil
        vm = psutil.virtual_memory()
        info["memory"] = {
            "total_gb": round(vm.total / 1024**3, 2),
            "available_gb": round(vm.available / 1024**3, 2),
        }
        info["cpu"] = {
            "cores": psutil.cpu_count(logical=False) or 0,
            "threads": psutil.cpu_count(logical=True) or 0,
            "load_percent": psutil.cpu_percent(interval=0.5),
        }
    except Exception as e:
        info["cpu"]["error"] = str(e)

    try:
        import torch  # noqa: F401
        if torch.cuda.is_available():
            for i in range(torch.cuda.device_count()):
                props = torch.cuda.get_device_properties(i)
                free, total = torch.cuda.mem_get_info()
                info["gpus"].append({
                    "index": i,
                    "name": props.name,
                    "total_gb": round(total / 1024**3, 2),
                    "free_gb": round(free / 1024**3, 2),
                })
        else:
            info["gpus"] = []
    except Exception as e:
        info["gpus"] = [{"error": str(e)}]

    repo = Path(__file__).resolve().parents[1]
    out_dir = repo / "training_reports"
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / "hw_profile.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(info, f, indent=2)
    print(f"Hardware profile written: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


