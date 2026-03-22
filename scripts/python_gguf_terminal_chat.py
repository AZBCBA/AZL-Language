#!/usr/bin/env python3
"""
Terminal chat using the **same** local GGUF + **llama-cli** subprocess path as
`tools/azl_native_engine.c` (no HTTP, no azl-native-engine).

Why each reply is slow
  Every line you send starts a **new** `llama-cli` process. That reloads the
  GGUF from disk, rebuilds the context, runs generation, then exits. The
  native AZL chat uses the same pattern, so Python will not be faster—only
  easier to experiment with. For low latency, run **llama-server** with the
  model kept loaded and call it from Python or use `scripts/benchmark_llm_llama_server.py`.

Why answers can still be "wrong"
  Same weights and same plain-text prompt wrapper as `/api/llm/chat_session`;
  small models (e.g. TinyLlama) and `-no-cnv` file prompts are not the model's
  native chat template, so quality varies.

Keep `CHAT_WRAP_*` in sync with `kChatWrapPrefix` / `kChatWrapSuffix` in
`tools/azl_native_engine.c`.

Env (same conventions as the C engine / `scripts/benchmark_llm_gguf_direct.py`):
  AZL_GGUF_PATH          path to .gguf (default: .azl/tmp/bench_tinyllama.Q4_K_M.gguf if present)
  AZL_LLAMA_CLI          llama-cli binary (default: llama-cli on PATH)
  AZL_LLAMA_SIMPLE_IO    default 1 → pass --simple-io
  AZL_LLAMA_SKIP_NO_CNV  set to 1 to omit -no-cnv
  AZL_LLAMA_NGL / AZL_LLM_GPU_LAYERS  GPU layers for -ngl
  AZL_CHAT_N_PREDICT     max new tokens per turn (default 512)
  AZL_LLAMA_CLI_TIMEOUT_SEC  subprocess timeout (default 600)

Usage:
  python3 scripts/python_gguf_terminal_chat.py
  AZL_GGUF_PATH=/path/model.gguf python3 scripts/python_gguf_terminal_chat.py
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# Sync with tools/azl_native_engine.c (handle_chat_session).
CHAT_WRAP_PREFIX = (
    "System: You are a helpful assistant in AZL terminal chat. Respond naturally to what the user wrote "
    "(including greetings and typos). Follow safety/policy; do not leak secrets. Prefer clear, complete "
    "sentences—do not stop mid-phrase.\n"
    "Conversation:\n"
)
CHAT_WRAP_SUFFIX = "\nAssistant:"

HIST_MAX = 96 * 1024
READ_MAX = 192 * 1024


def _repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def _default_gguf() -> str | None:
    p = _repo_root() / ".azl/tmp/bench_tinyllama.Q4_K_M.gguf"
    if p.is_file():
        return str(p)
    return None


def _env_int(name: str, default: int) -> int:
    v = (os.environ.get(name) or "").strip()
    if not v:
        return default
    try:
        return int(v)
    except ValueError:
        return default


def _ngl_from_env() -> int:
    a = (os.environ.get("AZL_LLAMA_NGL") or "").strip()
    if a:
        try:
            return max(0, int(a))
        except ValueError:
            return 0
    b = (os.environ.get("AZL_LLM_GPU_LAYERS") or "").strip()
    if b:
        try:
            return max(0, int(b))
        except ValueError:
            return 0
    return 0


def trim_llama_cli_stdout_prefix(s: str) -> str:
    if not s:
        return s
    pa = s.find("\n> ")
    if pa < 0:
        return s
    rest = s[pa + 2 :]
    nl = rest.find("\n")
    if nl < 0:
        return s
    body = rest[nl + 1 :].lstrip("\n")
    return body if body else s


def trim_llama_cli_stdout_noise(s: str) -> str:
    if not s:
        return s
    last = -1
    start = 0
    while True:
        j = s.find("[ Prompt:", start)
        if j < 0:
            break
        last = j
        start = j + 1
    if last >= 0:
        line_start = s.rfind("\n", 0, last)
        if line_start < 0:
            s = s[:last].rstrip()
        else:
            s = s[:line_start].rstrip()
    ex = s.find("Exiting...")
    if ex >= 0:
        line_start = s.rfind("\n", 0, ex)
        if line_start < 0:
            s = s[:ex].rstrip()
        else:
            s = s[:line_start].rstrip()
    return s.rstrip()


def trim_ascii_whitespace(s: str) -> str:
    return s.strip()


def trim_end_of_text_marker(s: str) -> str:
    s = s.rstrip()
    m = "[end of text]"
    if s.endswith(m):
        s = s[: -len(m)].rstrip()
    return s


def sanitize_chat_answer(prompt: str, answer: str) -> str:
    if not answer:
        return answer
    answer = trim_ascii_whitespace(answer)
    if prompt and answer.startswith(prompt):
        answer = answer[len(prompt) :]
    if "Conversation:" in answer and ("System:" in answer or "User:" in answer):
        last_pos = -1
        start = 0
        needle = "\nAssistant:"
        while True:
            j = answer.find(needle, start)
            if j < 0:
                break
            last_pos = j
            start = j + len(needle)
        if last_pos >= 0:
            body = answer[last_pos + len(needle) :]
            body = body.lstrip("\n\r")
            if body.startswith("Assistant:"):
                body = body[10:].lstrip()
            answer = body
    answer = trim_ascii_whitespace(answer)
    if answer.startswith("Assistant:"):
        answer = answer[10:].lstrip()
    answer = trim_end_of_text_marker(answer)
    return answer


def run_llama_cli_infer(prompt: str, n_predict: int) -> tuple[int, str, str]:
    """
    Returns (returncode, stdout_trimmed, stderr_or_error_tag).
    On success returncode is 0 and stderr_or_error_tag is "".
    """
    gguf = (os.environ.get("AZL_GGUF_PATH") or "").strip()
    if not gguf:
        d = _default_gguf()
        if d:
            gguf = d
        else:
            return 2, "", "ERROR: set AZL_GGUF_PATH to a .gguf file (or place TinyLlama at .azl/tmp/bench_tinyllama.Q4_K_M.gguf)."

    if not os.path.isfile(gguf):
        return 2, "", f"ERROR: AZL_GGUF_PATH is not a file: {gguf}"

    cli = (os.environ.get("AZL_LLAMA_CLI") or "llama-cli").strip()
    if not os.path.isfile(cli) and not shutil.which(cli):
        return 2, "", f"ERROR: llama-cli not found ({cli}). Install llama.cpp or set AZL_LLAMA_CLI."

    skip_no_cnv = (os.environ.get("AZL_LLAMA_SKIP_NO_CNV") or "").strip() == "1"
    simple_io = (os.environ.get("AZL_LLAMA_SIMPLE_IO") or "1").strip() == "1"
    ngl = _ngl_from_env()
    timeout = float(_env_int("AZL_LLAMA_CLI_TIMEOUT_SEC", 600))

    n_predict = max(1, min(n_predict, 8192))

    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", delete=False, suffix=".txt") as f:
        f.write(prompt)
        pfile = f.name
    try:
        cmd: list[str] = [cli, "-m", gguf, "-f", pfile, "-n", str(n_predict)]
        if ngl > 0:
            cmd.extend(["-ngl", str(ngl)])
        if not skip_no_cnv:
            cmd.append("-no-cnv")
        if simple_io:
            cmd.append("--simple-io")
        cmd.extend(["--single-turn", "--no-display-prompt", "--no-warmup"])
        try:
            r = subprocess.run(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=timeout,
            )
        except subprocess.TimeoutExpired:
            return 124, "", f"ERROR: llama-cli exceeded AZL_LLAMA_CLI_TIMEOUT_SEC={int(timeout)}s"

        raw = r.stdout or ""
        if len(raw) > READ_MAX:
            raw = raw[:READ_MAX]
        raw = trim_llama_cli_stdout_prefix(raw)
        raw = trim_llama_cli_stdout_noise(raw)
        if r.returncode != 0:
            err = (r.stderr or "").strip() or "llama_cli_failed"
            return r.returncode, raw, f"ERROR: llama-cli exit {r.returncode}: {err[:800]}"
        return 0, raw, ""
    finally:
        try:
            os.unlink(pfile)
        except OSError:
            pass


def main() -> int:
    n_predict = _env_int("AZL_CHAT_N_PREDICT", 512)
    gguf_disp = (os.environ.get("AZL_GGUF_PATH") or "").strip() or (_default_gguf() or "(unset)")
    cli_disp = (os.environ.get("AZL_LLAMA_CLI") or "llama-cli").strip()

    print("Python GGUF chat (same llama-cli stack as azl-native-engine).", file=sys.stderr)
    print(f"  GGUF={gguf_disp}", file=sys.stderr)
    print(f"  CLI={cli_disp}", file=sys.stderr)
    print("  Each message spawns a new llama-cli (slow). Commands: /exit /quit /reset", file=sys.stderr)
    print(file=sys.stderr)

    history = ""

    while True:
        try:
            line = input("You> ")
        except EOFError:
            print()
            return 0

        user_msg = line.strip()
        if not user_msg:
            continue
        if user_msg in ("/exit", "/quit"):
            print("Bye.")
            return 0
        if user_msg == "/reset":
            history = ""
            print("History cleared.\n")
            continue

        chunk = f"\nUser: {user_msg}"
        if len(history) + len(chunk) + len(CHAT_WRAP_PREFIX) + len(CHAT_WRAP_SUFFIX) > HIST_MAX:
            keep = HIST_MAX // 2
            history = history[-keep:] if len(history) > keep else ""

        history += chunk
        prompt = f"{CHAT_WRAP_PREFIX}{history}{CHAT_WRAP_SUFFIX}"

        rc, raw, err = run_llama_cli_infer(prompt, n_predict)
        if rc != 0:
            print(err, file=sys.stderr)
            # Do not poison history with failed turns
            history = history[: -len(chunk)] if history.endswith(chunk) else history
            continue

        answer = sanitize_chat_answer(prompt, raw)
        history += f"\nAssistant: {answer}\n"
        print(f"PY> {answer}\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
