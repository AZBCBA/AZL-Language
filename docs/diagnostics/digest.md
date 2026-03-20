# AZL diagnostics digest

This folder holds **redacted, repo-safe** snapshots of runtime diagnostics.  
**Do not** copy raw `.azl/daemon.run.log` or live tokens into git without redaction.

## Source files under `.azl/` (live machine)

| Artifact | Approx. size / lines | Role |
|----------|----------------------|------|
| `daemon.err` | **~2.0 GB** | Runtime stderr; dominated by repeated lines |
| `daemon.out` | 0 bytes (when last checked) | Runtime stdout |
| `daemon.run.log` | ~1.7 KB | Enterprise runner banner; **may contain API token in plaintext** |
| `policy_infer_audit.jsonl` | 101 lines | Policy decisions for `/api/llm/policy_infer` (no full prompts in sampled lines) |
| `native_engine_runs.jsonl` | 199 lines | Native engine bundle paths, ports, combined-file hints |

## Dominant signals in `daemon.err` (from sampled head/tail)

1. **`[runtime:err] listen error: sysproxy timeout for op=listen id=2`** — repeated very heavily; drives log growth.  
   **Mitigation (repo):** `azl/system/azl_system_interface.azl` `sysproxy_call` uses **longer tick budgets** for `listen`, `accept`, `keepalive`, `read`, and `write` (default short budget unchanged for other ops). Rebuild enterprise combined bundles so the running interpreter picks up the change.
2. **Node `MODULE_NOT_FOUND` for `scripts/azl_runtime.js`** — some launchers still pointed at a Node entry that was absent.  
   **Mitigation (repo):** `scripts/azl_runtime.js` now **delegates** to `tools/azl_runtime_spine_host.py` (same as `scripts/azl_azl_interpreter_runtime.sh`), with structured stderr on hard failures.

Low unique information per megabyte: safe to **truncate** `daemon.err` after archiving a sanitized tail if you need disk space. Use **`bash scripts/azl_truncate_daemon_err.sh`** (optional `AZL_DAEMON_ERR_BACKUP_TAIL_LINES=500` for a raw tail under `.azl/archive/`). This only touches the log file — **no AZL source components are removed.**

## Files in this directory (committed snapshots)

| File | Contents |
|------|----------|
| `digest.md` | This summary |
| `daemon_err_sanitized_tail.txt` | Last **400** lines of `.azl/daemon.err`, sanitized |
| `daemon_err_sanitized_sample.txt` | First **120** lines + last **250** lines (labeled sections), sanitized |
| `daemon_run_log_sanitized.txt` | Full `.azl/daemon.run.log` with token-like lines redacted |
| `policy_infer_audit.jsonl` | Copy of audit trail (no prompt bodies in typical lines) |
| `native_engine_runs.jsonl` | Copy of native engine run metadata |

## Sanitization rules applied

Applied to text exports from `daemon.err` and `daemon.run.log`:

- Hex-like tokens **≥ 40** characters → `[REDACTED_HEX]`
- JWT-shaped strings (`eyJ…`) → `[REDACTED_JWT]`
- Lines matching `API Token:`, `Token:`, `Authorization:` assignments → value replaced with `[REDACTED]`
- Email-shaped strings → `[REDACTED_EMAIL]`

**Residual risk:** uncommon secret formats may still appear; review before sharing externally.

## Operational notes (native LLM / chat spine)

- **Native HTTP + policy + GGUF** use the **`azl-native-engine`** listener (not the generic AZL HTTP server on 8080) for routes like `chat_session`.
- **`AZL_LLAMA_CLI`** + **`AZL_LLAMA_SIMPLE_IO=1`** when using `llama-completion` instead of `llama-cli`.
- Chat session history: **`.azl/chat_sessions/<id>.txt`** (durable); sanitize before persist is handled in the native engine for echoed prompts.

## Cleanup recommendations (local disk, not automated here)

1. After retaining a sanitized tail (this folder or your archive), run **`bash scripts/azl_truncate_daemon_err.sh`** (see above). Prefer this over deleting random repo files.
2. Clear **`.azl/tmp/`** and old combined bundles under **`/tmp/azl_enterprise_*.azl`** when not debugging.
3. Do not commit **`.azl/live_chat.env`** or raw runner logs containing tokens.

## Regenerating sanitized exports

From repo root (adjust line counts as needed):

```bash
tail -n 400 .azl/daemon.err | python3 -c "
import re, sys
d = sys.stdin.read()
d = re.sub(r'\\b[0-9a-fA-F]{40,}\\b', '[REDACTED_HEX]', d)
d = re.sub(r'eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+', '[REDACTED_JWT]', d)
d = re.sub(r'(?i)(API\\s*Token|Token|Authorization)\\s*[:=]\\s*\\S+', r'\\1: [REDACTED]', d)
d = re.sub(r'\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}\\b', '[REDACTED_EMAIL]', d)
sys.stdout.write(d)
" > docs/diagnostics/daemon_err_sanitized_tail.txt
```

Redact `daemon.run.log` similarly before any copy to a shared location.
