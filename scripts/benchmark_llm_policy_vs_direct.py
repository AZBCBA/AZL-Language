#!/usr/bin/env python3
import json
import os
import time
import urllib.request
import urllib.error


def env_int(name: str, default: int) -> int:
    v = (os.environ.get(name) or "").strip()
    if not v:
        return default
    try:
        return int(v)
    except ValueError:
        return default


def call(base: str, token: str, path: str, prompt: str, n_predict: int):
    body = json.dumps({"prompt": prompt, "n_predict": n_predict}).encode("utf-8")
    req = urllib.request.Request(
        f"{base.rstrip('/')}{path}",
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
        return True, dt, raw
    except urllib.error.HTTPError as e:
        dt = (time.perf_counter() - t0) * 1e6
        try:
            msg = e.read().decode("utf-8", errors="replace")
        except Exception:
            msg = str(e)
        return False, dt, msg
    except Exception as e:
        dt = (time.perf_counter() - t0) * 1e6
        return False, dt, str(e)


def summarize(xs):
    if not xs:
        return 0.0, 0.0, 0.0
    s = sorted(xs)
    n = len(s)
    mean = sum(s) / n
    p50 = s[max(0, (n * 50 + 99) // 100 - 1)]
    p95 = s[max(0, (n * 95 + 99) // 100 - 1)]
    return mean, p50, p95


def main() -> int:
    base = (os.environ.get("AZL_BENCH_GGUF_URL") or "").strip()
    token = ((os.environ.get("AZL_BENCH_TOKEN") or "").strip() or (os.environ.get("AZL_API_TOKEN") or "").strip())
    reqs = env_int("LLM_BENCH_REQS", 10)
    warmup = env_int("LLM_BENCH_WARMUP", 2)
    n_predict = env_int("LLM_BENCH_NUM_PREDICT", 24)
    prompt = os.environ.get("LLM_BENCH_PROMPT", "Explain vector databases in one short paragraph.")
    if not base or not token:
        print("ERROR: set AZL_BENCH_GGUF_URL and AZL_BENCH_TOKEN (or AZL_API_TOKEN)")
        return 2

    for _ in range(warmup):
        call(base, token, "/api/llm/gguf_infer", prompt, n_predict)
        call(base, token, "/api/llm/policy_infer", prompt, n_predict)

    direct_us = []
    policy_us = []
    direct_ok = 0
    policy_ok = 0

    for i in range(reqs):
        ok1, t1, _ = call(base, token, "/api/llm/gguf_infer", prompt, n_predict)
        direct_us.append(t1)
        if ok1:
            direct_ok += 1
        print(f"[direct] {i+1}/{reqs} ok={ok1} us={t1:.0f}", flush=True)

        ok2, t2, out2 = call(base, token, "/api/llm/policy_infer", prompt, n_predict)
        policy_us.append(t2)
        if ok2:
            policy_ok += 1
        print(f"[policy] {i+1}/{reqs} ok={ok2} us={t2:.0f}", flush=True)
        if not ok2:
            print(f"policy_error_sample={out2[:240]}", flush=True)

    dm, d50, d95 = summarize(direct_us)
    pm, p50, p95 = summarize(policy_us)
    print("")
    print("Client               ok/n      mean(us)    p50(us)    p95(us)")
    print("------               ----      --------    -------    -------")
    print(f"direct_gguf_infer    {direct_ok}/{reqs}   {dm:10.2f}  {d50:10.0f}  {d95:10.0f}")
    print(f"policy_gguf_infer    {policy_ok}/{reqs}   {pm:10.2f}  {p50:10.0f}  {p95:10.0f}")
    if dm > 0:
        print(f"overhead (policy/direct) mean={pm/dm:.4f}  p50={p50/d50 if d50 else 0:.4f}")

    return 0 if direct_ok == reqs and policy_ok == reqs else 1


if __name__ == "__main__":
    raise SystemExit(main())

