#!/usr/bin/env python3
"""
Proof point: identical LLM requests — Python (direct Ollama) vs AZL native engine
(POST /api/ollama/generate). Same payload, same N iterations each.

Outputs latency stats and mean/p95 ratios (AZL / Python). Intended for external
review (e.g. OpenAI): ~1–3x is a modest proxy tax; ~10–15x+ is a different story.

Env:
  OLLAMA_HOST          default http://127.0.0.1:11434
  AZL_BASE_URL         e.g. http://127.0.0.1:18080 (required)
  AZL_API_TOKEN        Bearer for AZL (required if engine enforces auth)
  LLM_BENCH_MODEL      default llama3.2:1b
  LLM_BENCH_PROMPT     default short fixed string
  LLM_BENCH_NUM_PREDICT default 16
  PROOF_REQS           default 1000
  PROOF_WARMUP         default 5 (per path, before timed loop)
  PROOF_HTTP_TIMEOUT_SEC default 120
"""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


def percentile(sorted_vals: list[int], pct: int) -> int:
    n = len(sorted_vals)
    if n == 0:
        return 0
    idx = max(0, (n * pct + 99) // 100 - 1)
    return sorted_vals[idx]


def stats_us(lat_us: list[int]) -> dict:
    """Percentiles over successful request latencies only."""
    if not lat_us:
        return {"n_ok": 0, "mean": 0.0, "p50": 0, "p95": 0, "p99": 0}
    s = sorted(lat_us)
    n = len(s)
    mean = sum(s) / n
    return {
        "n_ok": n,
        "mean": mean,
        "p50": percentile(s, 50),
        "p95": percentile(s, 95),
        "p99": percentile(s, 99),
    }


def call_timed(
    url: str,
    payload: bytes,
    headers: dict[str, str],
    timeout: float,
) -> tuple[int, bool]:
    req = urllib.request.Request(url, data=payload, headers=headers, method="POST")
    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            resp.read()
        dt = time.perf_counter() - t0
        return int(dt * 1_000_000), True
    except (urllib.error.URLError, urllib.error.HTTPError, OSError, TimeoutError):
        dt = time.perf_counter() - t0
        return int(dt * 1_000_000), False


def main() -> int:
    ollama = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434").rstrip("/")
    azl_base = os.environ.get("AZL_BASE_URL", "").rstrip("/")
    token = os.environ.get("AZL_API_TOKEN", "")
    model = os.environ.get("LLM_BENCH_MODEL", "llama3.2:1b")
    prompt = os.environ.get("LLM_BENCH_PROMPT", "Say hello in one word.")
    num_predict = int(os.environ.get("LLM_BENCH_NUM_PREDICT", "16"))
    n_req = int(os.environ.get("PROOF_REQS", "1000"))
    warmup = int(os.environ.get("PROOF_WARMUP", "5"))
    timeout = float(os.environ.get("PROOF_HTTP_TIMEOUT_SEC", "120"))

    if not azl_base:
        print("ERROR: AZL_BASE_URL is required (e.g. http://127.0.0.1:18080)", file=sys.stderr)
        return 2
    if not token:
        print("ERROR: AZL_API_TOKEN is required for /api/ollama/generate (engine auth)", file=sys.stderr)
        return 2

    body_obj = {
        "model": model,
        "prompt": prompt,
        "stream": False,
        "options": {"num_predict": num_predict},
    }
    payload = json.dumps(body_obj).encode("utf-8")
    direct_url = f"{ollama}/api/generate"
    azl_url = f"{azl_base}/api/ollama/generate"
    h_json = {"Content-Type": "application/json"}
    h_azl = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {token}",
    }

    # Ollama reachable
    try:
        urllib.request.urlopen(
            urllib.request.Request(f"{ollama}/api/tags", method="GET"),
            timeout=5,
        ).read()
    except Exception as e:
        print(f"ERROR: Ollama not reachable at {ollama}: {e}", file=sys.stderr)
        return 91

    root = Path(__file__).resolve().parents[1]
    out_dir = root / ".azl"
    out_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    lat_py = out_dir / f"proof_llm_python_direct_{ts}.lat"
    lat_azl = out_dir / f"proof_llm_azl_proxy_{ts}.lat"

    print(f"[proof] Ollama direct: {n_req} timed requests after {warmup} warmup", file=sys.stderr)
    for w in range(warmup):
        _, ok = call_timed(direct_url, payload, h_json, timeout)
        print(f"[proof] python warmup {w + 1}/{warmup} ok={ok}", file=sys.stderr)

    py_us: list[int] = []
    py_fail = 0
    for i in range(n_req):
        us, ok = call_timed(direct_url, payload, h_json, timeout)
        if ok:
            py_us.append(us)
        else:
            py_fail += 1
        if (i + 1) % 100 == 0:
            print(f"[proof] python {i + 1}/{n_req}", file=sys.stderr)

    lat_py.write_text("\n".join(f"generate,{u}" for u in py_us) + "\n", encoding="utf-8")

    print(f"[proof] AZL proxy: {n_req} timed requests after {warmup} warmup", file=sys.stderr)
    for w in range(warmup):
        _, ok = call_timed(azl_url, payload, h_azl, timeout)
        print(f"[proof] azl warmup {w + 1}/{warmup} ok={ok}", file=sys.stderr)

    azl_us: list[int] = []
    azl_fail = 0
    for i in range(n_req):
        us, ok = call_timed(azl_url, payload, h_azl, timeout)
        if ok:
            azl_us.append(us)
        else:
            azl_fail += 1
        if (i + 1) % 100 == 0:
            print(f"[proof] azl {i + 1}/{n_req}", file=sys.stderr)

    lat_azl.write_text("\n".join(f"generate,{u}" for u in azl_us) + "\n", encoding="utf-8")

    sp = stats_us(py_us)
    sa = stats_us(azl_us)

    ratio_mean = (sa["mean"] / sp["mean"]) if sp["mean"] > 0 else 0.0
    ratio_p95 = (sa["p95"] / sp["p95"]) if sp["p95"] > 0 else 0.0
    ratio_p50 = (sa["p50"] / sp["p50"]) if sp["p50"] > 0 else 0.0

    title = os.environ.get(
        "PROOF_REPORT_TITLE",
        "LLM latency proof: Python (direct Ollama) vs AZL native proxy",
    )
    disclaimer = (os.environ.get("PROOF_REPORT_DISCLAIMER") or "").strip()

    report = out_dir / f"proof_llm_python_vs_azl_{ts}.md"
    lines = [
        f"# {title}",
        "",
        f"- **Generated (UTC):** `{ts}`",
        f"- **Ollama:** `{ollama}`",
        f"- **AZL base:** `{azl_base}` → `POST /api/ollama/generate`",
        f"- **Model:** `{model}`",
        f"- **num_predict:** `{num_predict}`",
        f"- **Timed attempts per path:** `{n_req}` (warmup `{warmup}` each, not counted)",
        f"- **HTTP timeout:** `{timeout}` s",
        f"- **Stats below:** successful requests only (`n_ok`); `fail` = timed attempts that errored.",
        "",
    ]
    if disclaimer:
        lines.extend(["## Scope (read this)", "", disclaimer, ""])
    lines.extend(
        [
        "## Results (end-to-end latency, microseconds)",
        "",
        "| Path | n_ok | fail | mean (µs) | p50 | p95 | p99 |",
        "|------|------|------|-----------|-----|-----|-----|",
        f"| Python → Ollama | {sp['n_ok']} | {py_fail} | {sp['mean']:.2f} | {sp['p50']} | {sp['p95']} | {sp['p99']} |",
        f"| Client → AZL → Ollama | {sa['n_ok']} | {azl_fail} | {sa['mean']:.2f} | {sa['p50']} | {sa['p95']} | {sa['p99']} |",
        "",
        "## Ratios (AZL / Python)",
        "",
        f"- **mean:** `{ratio_mean:.3f}`×",
        f"- **p50:** `{ratio_p50:.3f}`×",
        f"- **p95:** `{ratio_p95:.3f}`×",
        "",
        "## How to read this (OpenAI / partner review)",
        "",
        "- **Same JSON body** to Ollama `/api/generate` whether direct or via AZL; same `num_predict`.",
        "- **~1.0–1.3×** on mean/p95: proxy overhead is a **small** additive tax on top of inference time.",
        "- **~3×**: often still explainable as **acceptable** if product value is routing, auth, or event-driven orchestration.",
        "- **~10–15×+**: investigate **before** claiming parity; usually configuration error, saturation, or a different code path.",
        "",
        "## Raw traces",
        "",
        f"- `{lat_py.relative_to(root)}`",
        f"- `{lat_azl.relative_to(root)}`",
        "",
    ]
    )
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print("\n" + "\n".join(lines))
    print(f"\n[proof] Wrote {report.relative_to(root)}", file=sys.stderr)
    if py_fail or azl_fail:
        print(
            f"[proof] WARNING: failures python={py_fail} azl={azl_fail} (latencies still recorded)",
            file=sys.stderr,
        )
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
