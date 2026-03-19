#!/usr/bin/env python3
"""
Compare Python-orchestrated vs AZL-native-engine inference using the **same** local GGUF weights
and **llama-cli** (llama.cpp) — **no Ollama**.

Requires:
  - llama.cpp `llama-cli` on PATH (or AZL_LLAMA_CLI)
  - AZL_GGUF_PATH pointing at a .gguf file
  - Running azl-native-engine with Bearer auth and POST /api/llm/gguf_infer (set AZL_GGUF_PATH on engine too)

Env:
  AZL_GGUF_PATH, AZL_LLAMA_CLI (default llama-cli), AZL_LLAMA_SKIP_NO_CNV=1 if needed
  AZL_BENCH_GGUF_URL (e.g. http://127.0.0.1:18080), AZL_API_TOKEN / AZL_BENCH_TOKEN
  LLM_BENCH_REQS, LLM_BENCH_WARMUP, LLM_BENCH_NUM_PREDICT, LLM_BENCH_PROMPT
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request


def env_int(name: str, default: int) -> int:
    v = (os.environ.get(name) or "").strip()
    if not v:
        return default
    try:
        return int(v)
    except ValueError:
        return default


def run_llama_cli(prompt: str, n_predict: int) -> tuple[bool, float, str]:
    gguf = (os.environ.get("AZL_GGUF_PATH") or "").strip()
    cli = (os.environ.get("AZL_LLAMA_CLI") or "llama-cli").strip()
    if not gguf or not os.path.isfile(gguf):
        return False, 0.0, "AZL_GGUF_PATH missing or not a file"

    skip_no_cnv = (os.environ.get("AZL_LLAMA_SKIP_NO_CNV") or "").strip() == "1"
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", delete=False, suffix=".txt") as f:
        f.write(prompt)
        pfile = f.name
    try:
        cmd = [cli, "-m", gguf, "-f", pfile, "-n", str(n_predict)]
        if not skip_no_cnv:
            cmd.append("-no-cnv")
        if (os.environ.get("AZL_LLAMA_SIMPLE_IO") or "").strip() == "1":
            cmd.append("--simple-io")
        t0 = time.perf_counter()
        r = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=600,
        )
        dt = (time.perf_counter() - t0) * 1e6
        ok = r.returncode == 0
        out = r.stdout or ""
        return ok, dt, out[:2000] if ok else out[:500]
    finally:
        try:
            os.unlink(pfile)
        except OSError:
            pass


def run_azl_infer(base: str, token: str, prompt: str, n_predict: int) -> tuple[bool, float, str]:
    url = f"{base.rstrip('/')}/api/llm/gguf_infer"
    body = json.dumps({"prompt": prompt, "n_predict": n_predict}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}",
        },
        method="POST",
    )
    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=600) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
        dt = (time.perf_counter() - t0) * 1e6
        j = json.loads(raw)
        if j.get("ok") and "text" in j:
            return True, dt, str(j.get("text", ""))[:2000]
        return False, dt, raw[:500]
    except urllib.error.HTTPError as e:
        dt = (time.perf_counter() - t0) * 1e6
        try:
            b = e.read().decode("utf-8", errors="replace")
        except Exception:
            b = str(e)
        return False, dt, b[:500]
    except Exception as e:
        dt = (time.perf_counter() - t0) * 1e6
        return False, dt, type(e).__name__


def summarize(us: list[float]) -> tuple[float, float, float]:
    if not us:
        return 0.0, 0.0, 0.0
    s = sorted(us)
    n = len(s)
    mean = sum(s) / n
    p50 = s[max(0, (n * 50 + 99) // 100 - 1)]
    p95 = s[max(0, (n * 95 + 99) // 100 - 1)]
    return mean, p50, p95


def main() -> int:
    gguf = (os.environ.get("AZL_GGUF_PATH") or "").strip()
    if not gguf:
        print("ERROR: set AZL_GGUF_PATH to a local .gguf file", file=sys.stderr)
        return 91
    if not os.path.isfile(gguf):
        print(f"ERROR: AZL_GGUF_PATH is not a file: {gguf}", file=sys.stderr)
        return 92

    cli = (os.environ.get("AZL_LLAMA_CLI") or "llama-cli").strip()
    if not shutil.which(cli):
        print(
            f"ERROR: {cli} not found on PATH (install llama.cpp or set AZL_LLAMA_CLI)",
            file=sys.stderr,
        )
        return 93

    base = (os.environ.get("AZL_BENCH_GGUF_URL") or "").strip()
    token = (
        (os.environ.get("AZL_API_TOKEN") or "").strip()
        or (os.environ.get("AZL_BENCH_TOKEN") or "").strip()
    )
    if not base or not token:
        print(
            "ERROR: set AZL_BENCH_GGUF_URL and AZL_API_TOKEN (or AZL_BENCH_TOKEN) for AZL path",
            file=sys.stderr,
        )
        return 94

    reqs = env_int("LLM_BENCH_REQS", 10)
    warmup = env_int("LLM_BENCH_WARMUP", 2)
    n_pred = env_int("LLM_BENCH_NUM_PREDICT", 64)
    prompt = os.environ.get(
        "LLM_BENCH_PROMPT", "Explain what a hash table is in two short sentences."
    )

    print("=== Direct GGUF benchmark (llama-cli, no Ollama) ===", file=sys.stderr)
    print(f"  GGUF={gguf} CLI={cli} REQS={reqs} WARMUP={warmup} n_predict={n_pred}", file=sys.stderr)

    for _ in range(warmup):
        run_llama_cli(prompt, n_pred)
        run_azl_infer(base, token, prompt, n_pred)

    py_us: list[float] = []
    az_us: list[float] = []
    py_ok = az_ok = 0
    for i in range(reqs):
        ok, u, _ = run_llama_cli(prompt, n_pred)
        py_us.append(u)
        if ok:
            py_ok += 1
        print(f"[python-llama-cli] {i+1}/{reqs} ok={ok} us={u:.0f}", file=sys.stderr)
        ok2, u2, _ = run_azl_infer(base, token, prompt, n_pred)
        az_us.append(u2)
        if ok2:
            az_ok += 1
        print(f"[azl-gguf_infer]   {i+1}/{reqs} ok={ok2} us={u2:.0f}", file=sys.stderr)

    pm, pp50, pp95 = summarize(py_us)
    am, ap50, ap95 = summarize(az_us)

    print("")
    print("Client               ok/n      mean(us)    p50(us)    p95(us)")
    print("------               ----      --------    -------    -------")
    print(f"python_llama_cli     {py_ok}/{reqs}   {pm:10.2f}  {pp50:10.0f}  {pp95:10.0f}")
    print(f"azl_gguf_infer       {az_ok}/{reqs}   {am:10.2f}  {ap50:10.0f}  {ap95:10.0f}")
    if pm > 0:
        print(f"ratio (AZL/Python)   mean={am/pm:.4f}  p50={ap50/pp50 if pp50 else 0:.4f}")
    return 0 if py_ok == reqs and az_ok == reqs else 1


if __name__ == "__main__":
    raise SystemExit(main())
