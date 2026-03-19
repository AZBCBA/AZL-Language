#!/usr/bin/env python3
"""
LLM benchmark: Python client calling Ollama /api/generate.
Measures end-to-end latency (Python + HTTP + Ollama inference).
Requires: Ollama running with a model (e.g. ollama run llama3.2:1b)
"""
import json
import os
import sys
import time
import urllib.request

OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")
REQS = int(os.environ.get("LLM_BENCH_REQS", "20"))
MODEL = os.environ.get("LLM_BENCH_MODEL", "llama3.2:1b")
PROMPT = os.environ.get("LLM_BENCH_PROMPT", "Say hello in one word.")
LAT_FILE = os.environ.get("LLM_BENCH_LAT_FILE", ".azl/benchmark_llm_python.lat")


def call_ollama(prompt: str, model: str) -> tuple[float, bool]:
    """Call Ollama /api/generate, return (latency_sec, success)."""
    url = f"{OLLAMA_HOST}/api/generate"
    payload = json.dumps({
        "model": model,
        "prompt": prompt,
        "stream": False,
        "options": {"num_predict": 16},
    }).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    start = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            resp.read()
        return time.perf_counter() - start, True
    except Exception:
        return time.perf_counter() - start, False


def main():
    os.makedirs(os.path.dirname(LAT_FILE) or ".", exist_ok=True)
    latencies = []
    ok = 0
    fail = 0
    for i in range(REQS):
        lat, success = call_ollama(PROMPT, MODEL)
        lat_us = int(lat * 1_000_000)
        latencies.append(lat_us)
        if success:
            ok += 1
        else:
            fail += 1
        print(f"[python-llm] req={i+1}/{REQS} lat_us={lat_us} ok={success}", file=sys.stderr)

    with open(LAT_FILE, "w") as f:
        for u in latencies:
            f.write(f"generate,{u}\n")

    n = len(latencies)
    if n == 0:
        mean = p50 = p95 = 0
    else:
        s = sorted(latencies)
        mean = sum(latencies) / n
        p50 = s[(n * 50) // 100] if n > 0 else 0
        p95 = s[(n * 95) // 100] if n > 0 else 0

    print(f"generate,{n},{mean:.2f},{p50},{p95}")
    print(f"ok={ok} fail={fail}", file=sys.stderr)
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
