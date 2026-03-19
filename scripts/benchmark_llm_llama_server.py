#!/usr/bin/env python3
"""
Benchmark: Python -> llama-server /completion vs AZL -> POST /api/llm/llama_server/completion
(same JSON body; model stays loaded in llama-server).

Env:
  AZL_LLAMA_SERVER_URL   e.g. http://127.0.0.1:19110  (direct upstream)
  AZL_BENCH_ENGINE_URL   e.g. http://127.0.0.1:19120  (azl-native-engine)
  AZL_API_TOKEN / AZL_BENCH_TOKEN
  LLM_BENCH_REQS, LLM_BENCH_WARMUP, LLM_BENCH_NUM_PREDICT, LLM_BENCH_PROMPT
"""
from __future__ import annotations

import json
import os
import sys
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


def _llama_server_completion_ok(j: object) -> bool:
    """True only for a normal llama-server /completion JSON (not a fast error body)."""
    if not isinstance(j, dict):
        return False
    if j.get("error") is not None:
        return False
    tp = j.get("tokens_predicted")
    if isinstance(tp, int) and tp > 0:
        return True
    c = j.get("content")
    return isinstance(c, str) and len(c.strip()) > 0


def post_completion(base: str, path: str, payload: dict, token: str | None) -> tuple[bool, float, str]:
    url = f"{base.rstrip('/')}{path}"
    body = json.dumps(payload).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
        dt = (time.perf_counter() - t0) * 1e6
        j = json.loads(raw)
        ok = _llama_server_completion_ok(j)
        return ok, dt, raw[:500]
    except urllib.error.HTTPError as e:
        dt = (time.perf_counter() - t0) * 1e6
        try:
            b = e.read().decode("utf-8", errors="replace")
        except Exception:
            b = str(e)
        return False, dt, b[:400]
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
    upstream = (os.environ.get("AZL_LLAMA_SERVER_URL") or "").strip()
    engine = (os.environ.get("AZL_BENCH_ENGINE_URL") or "").strip()
    token = (
        (os.environ.get("AZL_API_TOKEN") or "").strip()
        or (os.environ.get("AZL_BENCH_TOKEN") or "").strip()
    )
    if not upstream:
        print("ERROR: set AZL_LLAMA_SERVER_URL (llama-server base)", file=sys.stderr)
        return 91
    if not engine or not token:
        print("ERROR: set AZL_BENCH_ENGINE_URL and AZL_API_TOKEN", file=sys.stderr)
        return 92

    reqs = env_int("LLM_BENCH_REQS", 10)
    warmup = env_int("LLM_BENCH_WARMUP", 2)
    n_pred = env_int("LLM_BENCH_NUM_PREDICT", 32)
    prompt = os.environ.get(
        "LLM_BENCH_PROMPT", "Say hello in one short sentence."
    )
    payload = {"prompt": prompt, "n_predict": n_pred}

    print("=== llama-server loaded model: direct vs AZL proxy ===", file=sys.stderr)
    print(f"  upstream={upstream} engine={engine} REQS={reqs} WARMUP={warmup}", file=sys.stderr)

    for _ in range(warmup):
        post_completion(upstream, "/completion", payload, None)
        post_completion(engine, "/api/llm/llama_server/completion", payload, token)

    d_us: list[float] = []
    z_us: list[float] = []
    d_ok = z_ok = 0
    for i in range(reqs):
        ok, u, _ = post_completion(upstream, "/completion", payload, None)
        d_us.append(u)
        if ok:
            d_ok += 1
        print(f"[direct llama-server] {i+1}/{reqs} ok={ok} us={u:.0f}", file=sys.stderr)
        ok2, u2, _ = post_completion(
            engine, "/api/llm/llama_server/completion", payload, token
        )
        z_us.append(u2)
        if ok2:
            z_ok += 1
        print(f"[azl proxy]           {i+1}/{reqs} ok={ok2} us={u2:.0f}", file=sys.stderr)

    dm, dp50, dp95 = summarize(d_us)
    zm, zp50, zp95 = summarize(z_us)

    print("")
    print("Client               ok/n      mean(us)    p50(us)    p95(us)")
    print("------               ----      --------    -------    -------")
    print(f"direct_llama_server  {d_ok}/{reqs}   {dm:10.2f}  {dp50:10.0f}  {dp95:10.0f}")
    print(f"azl_llama_proxy      {z_ok}/{reqs}   {zm:10.2f}  {zp50:10.0f}  {zp95:10.0f}")
    if dm > 0:
        print(f"ratio (AZL/direct)   mean={zm/dm:.4f}  p50={zp50/dp50 if dp50 else 0:.4f}")
    return 0 if d_ok == reqs and z_ok == reqs else 1


if __name__ == "__main__":
    raise SystemExit(main())
