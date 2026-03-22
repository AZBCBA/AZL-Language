"""
Spine bootstrap engine (Python), kept in lockstep with ``tools/azl_interpreter_minimal.c`` for native F-gates.

Interpreter-shaped semantics live in ``azl/runtime/interpreter/azl_interpreter.azl``. This module hosts builtins and
pipe encodings so combined AZL runs under ``tools/azl_runtime_spine_host.py`` — it must **implement** that contract
and stay C-parity, not define divergent meaning. Rules for listeners, ``emit``/queue drain, ``&&``/``for-in``,
tokenize/parse builtins, and ``execute_ast`` row shapes: align with the AZL file and C; regressions live under
``azl/tests/p0_semantic_*.azl``.
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
from dataclasses import dataclass, field

BUF_SIZE = 2 * 1024 * 1024
MAX_TOKS = 65536
MAX_VARS = 256
# Combined interpreter + behavior-entry harness registers many top-level listeners; ``spine_component_v1``
# then adds synthetic listeners. C minimal stays at 64 (``tools/azl_interpreter_minimal.c``); Python spine
# host needs headroom so embedded components are not silently starved (harness alone reaches ~128 slots).
MAX_LISTENERS = 256
MAX_EVENTS = 32
MAX_PAYLOAD_KEYS = 8
# Bytes stored per Var.v (tz concat / ::tokens). Execute_ast pipe rows stay capped at 255 elsewhere.
MAX_VAR_VALUE_LEN = 2047
# azl_interpreter.azl serialized token/ast buffers on spine (cache round-trips, concat); not C-minimal parity surface.
INTERP_BLOB_VAR_MAX = 65536

# Bare identifier RHS in ``set`` (contract from azl_interpreter.azl; see exec_set).
_BARE_ID_FORBIDDEN = frozenset(
    {
        "if",
        "for",
        "in",
        "return",
        "listen",
        "emit",
        "with",
        "link",
        "init",
        "behavior",
        "memory",
        "component",
        "true",
        "false",
        "null",
        "then",
        "say",
        "set",
        "and",
        "or",
        "on",
        "import",
        "let",
    }
)


class SemanticEngineError(Exception):
    def __init__(self, code: int, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


def _skip_ws_comments(src: str, pos: list[int]) -> None:
    p = pos[0]
    n = len(src)
    while p < n:
        while p < n and src[p] in " \t\n\r":
            p += 1
        if p >= n:
            break
        if src[p] == "#" or (p + 1 < n and src[p : p + 2] == "//"):
            while p < n and src[p] != "\n":
                p += 1
            continue
        break
    pos[0] = p


def tokenize_source(src: str) -> list[str]:
    tokens: list[str] = []
    pos = [0]
    n = len(src)

    while len(tokens) < MAX_TOKS - 1:
        _skip_ws_comments(src, pos)
        p = pos[0]
        if p >= n:
            break
        start = p
        ch = src[p]

        if ch in "\"'":
            q = ch
            p += 1
            while p < n and src[p] != q:
                if src[p] == "\\":
                    p += 1
                p += 1
            if p < n and src[p] == q:
                p += 1
            tokens.append(src[start:p])
            pos[0] = p
            continue

        if ch.isalnum() or ch in "_:":
            p += 1
            while p < n and (src[p].isalnum() or src[p] in "_.:"):
                p += 1
            tokens.append(src[start:p])
            pos[0] = p
            continue

        if ch == "=" and p + 1 < n and src[p + 1] == "=":
            tokens.append("==")
            p += 2
            pos[0] = p
            continue
        if ch == "!" and p + 1 < n and src[p + 1] == "=":
            tokens.append("!=")
            p += 2
            pos[0] = p
            continue
        if ch == "&" and p + 1 < n and src[p + 1] == "&":
            tokens.append("&&")
            p += 2
            pos[0] = p
            continue
        if ch in "{}();=,[]!+-":
            tokens.append(ch)
            p += 1
            pos[0] = p
            continue

        p += 1
        pos[0] = p

    return tokens


@dataclass
class Listener:
    event: str
    block_start: int
    block_end: int
    # When set, dispatch runs this token slice (real listener body) instead of ``self.tok[block_*]``.
    synthetic_toks: list[str] | None = None


@dataclass
class Var:
    k: str
    v: str


@dataclass
class MinimalAZLRuntime:
    tok: list[str]
    ntok: int = field(init=False)
    vars: list[Var] = field(default_factory=list)
    listeners: list[Listener] = field(default_factory=list)
    queue: list[tuple[str, list[tuple[str, str]]]] = field(default_factory=list)
    _listener_nesting: int = field(default=0, repr=False)
    _listener_break: bool = field(default=False, repr=False)
    _execute_ast_listen_stubs: list[tuple[str, str, str, str]] = field(
        default_factory=list, repr=False
    )  # (event, "say"|"emit"|"set", arg1, arg2)
    # Host backing for ::perf.* maps from azl_interpreter.azl (literal "{}" aggregates on spine).
    _perf_tok_cache: dict[str, str] = field(default_factory=dict, repr=False)
    _perf_ast_cache: dict[str, str] = field(default_factory=dict, repr=False)

    def __post_init__(self) -> None:
        self.ntok = len(self.tok)

    @classmethod
    def from_file(cls, path: str) -> MinimalAZLRuntime:
        try:
            with open(path, "rb") as f:
                raw = f.read(BUF_SIZE - 1)
        except OSError as e:
            raise SemanticEngineError(2, f"azl_semantic_engine: cannot open {path}: {e}") from e
        try:
            src = raw.decode("utf-8")
        except UnicodeDecodeError as e:
            raise SemanticEngineError(4, f"azl_semantic_engine: utf-8 decode failed: {e}") from e
        try:
            toks = tokenize_source(src)
        except Exception as e:
            raise SemanticEngineError(4, f"azl_semantic_engine: tokenize failed: {e}") from e
        return cls(tok=toks)

    def var_get(self, k: str) -> str | None:
        for v in self.vars:
            if v.k == k:
                return v.v
        return None

    def _value_cap_for_key(self, k: str) -> int:
        if k in (
            "::tokens",
            "::ast",
            "::cached_tok",
            "::cached_ast",
            "::ast.nodes",
            "::ast.spine",
            "::lines",
        ):
            return INTERP_BLOB_VAR_MAX
        # interpret / tokenize / parse chain passes large blobs via emit payloads
        if k.startswith("::event.data.") and k in (
            "::event.data.tokens",
            "::event.data.code",
            "::event.data.ast",
        ):
            return INTERP_BLOB_VAR_MAX
        return MAX_VAR_VALUE_LEN

    def var_set(self, k: str, v: str) -> None:
        cap = self._value_cap_for_key(k)
        for i, x in enumerate(self.vars):
            if x.k == k:
                self.vars[i] = Var(k=k, v=v[:cap])
                return
        if len(self.vars) < MAX_VARS:
            self.vars.append(Var(k=k[:63], v=v[:cap]))

    def queue_push(self, ev: str, payload: list[tuple[str, str]] | None = None) -> None:
        if len(self.queue) >= MAX_EVENTS:
            return
        pl: list[tuple[str, str]] = []
        for pk, pv in (payload or [])[:MAX_PAYLOAD_KEYS]:
            kk = pk[:47]
            cap = (
                INTERP_BLOB_VAR_MAX
                if kk in ("tokens", "code", "ast")
                else 255
            )
            pl.append((kk, pv[:cap]))
        self.queue.append((ev[:63], pl))

    def queue_pop(self) -> tuple[str, list[tuple[str, str]]] | None:
        if not self.queue:
            return None
        return self.queue.pop(0)

    def register_listener(
        self,
        ev: str,
        block_start: int,
        block_end: int,
        synthetic_toks: list[str] | None = None,
    ) -> None:
        if len(self.listeners) < MAX_LISTENERS:
            self.listeners.append(
                Listener(
                    event=ev[:63],
                    block_start=block_start,
                    block_end=block_end,
                    synthetic_toks=synthetic_toks,
                )
            )

    def _exec_with_tok_swap(self, alt: list[str], start: int, end: int) -> None:
        """Run ``exec_block(start, end)`` against ``alt`` as the token stream (synthetic bodies)."""
        old_tok, old_ntok = self.tok, self.ntok
        self.tok = alt
        self.ntok = len(alt)
        try:
            self.exec_block(start, end)
        finally:
            self.tok, self.ntok = old_tok, old_ntok

    @staticmethod
    def _normalize_bare_identifier_lhs(tok0: str) -> str | None:
        if tok0.startswith("::"):
            return tok0
        if not tok0 or not (tok0[0].isalpha() or tok0[0] == "_"):
            return None
        if not all(ch.isalnum() or ch == "_" for ch in tok0):
            return None
        if tok0 in _BARE_ID_FORBIDDEN:
            return None
        return "::" + tok0

    def _format_tz_row(self, typ: str, val: str, line: str, col: str) -> str:
        parts = [
            self._tz_esc_field(typ[:32]),
            self._tz_esc_field(val[:200]),
            self._tz_esc_field(line[:20]),
            self._tz_esc_field(col[:20]),
        ]
        return "tz|" + "|".join(parts)

    @staticmethod
    def _tz_unsplit_tail_fields(tail: str) -> list[str] | None:
        """Split ``tail`` on unescaped ``|`` (tz row body after the ``tz|`` prefix)."""
        fields: list[str] = []
        cur: list[str] = []
        p = 0
        n = len(tail)
        while p < n:
            if tail[p] == "\\" and p + 1 < n:
                cur.append(tail[p + 1])
                p += 2
                continue
            if tail[p] == "|":
                fields.append("".join(cur))
                cur = []
                p += 1
                continue
            cur.append(tail[p])
            p += 1
        fields.append("".join(cur))
        return fields

    def _parse_tz_buffer_pairs(self, buf: str) -> list[tuple[str, str]]:
        rows: list[tuple[str, str]] = []
        for raw_line in buf.split("\n"):
            line = raw_line.strip()
            if not line.startswith("tz|"):
                continue
            fields = self._tz_unsplit_tail_fields(line[3:])
            if not fields or len(fields) < 4:
                continue
            rows.append((fields[0][:64], fields[1][:220]))
        return rows

    @staticmethod
    def _skip_eol_pairs(pairs: list[tuple[str, str]], i: int) -> int:
        while i < len(pairs) and pairs[i][0] == "eol":
            i += 1
        return i

    def _parse_with_brace_pairs(
        self, pairs: list[tuple[str, str]], j: int
    ) -> tuple[list[tuple[str, str]], int] | None:
        """After ``with``, parse ``{ k: v (, …)* }`` into ``(key, value)`` pairs (``execute_ast`` payload)."""
        n = len(pairs)
        j = self._skip_eol_pairs(pairs, j)
        if j >= n or pairs[j] != ("brace", "{"):
            return None
        j += 1
        kv: list[tuple[str, str]] = []
        while j < n:
            typ, val = pairs[j]
            if typ == "eol":
                j += 1
                continue
            if typ == "brace" and val == "}":
                return (kv, j + 1)
            if typ == "identifier" and val == ",":
                j += 1
                continue
            if typ != "identifier":
                return None
            if val.endswith(":") and len(val) > 1:
                key = val[:-1].strip()[:47]
                j += 1
            else:
                key = val.strip()[:47]
                j += 1
                j = self._skip_eol_pairs(pairs, j)
            if j >= n:
                return None
            vt, vv = pairs[j]
            if vt not in ("identifier", "string"):
                return None
            if not key or not all(ch.isalnum() or ch == "_" for ch in key):
                return None
            kv.append((key, vv[:80]))
            j += 1
        return None

    def _parse_listen_inner_to_row(
        self, pairs: list[tuple[str, str]], j: int, n: int, evn: str
    ) -> tuple[str, int] | None:
        """Parse one statement inside ``listen … { … }`` → ``listen|<evn>|say|…`` / ``…|emit|…`` / ``…|set|…``."""
        if j >= n:
            return None
        t0, v0 = pairs[j]
        if t0 == "identifier" and v0 == "say":
            j = self._skip_eol_pairs(pairs, j + 1)
            parts: list[str] = []
            while j < n:
                t2, v2 = pairs[j]
                if t2 == "eol":
                    if not parts:
                        j += 1
                        continue
                    j += 1
                    msg = " ".join(parts)[:199]
                    seg = ("listen|" + evn + "|say|" + msg)[:255]
                    return (seg, j)
                if t2 == "brace" and v2 == "}":
                    if not parts:
                        return None
                    j += 1
                    msg = " ".join(parts)[:199]
                    seg = ("listen|" + evn + "|say|" + msg)[:255]
                    return (seg, j)
                if t2 in ("identifier", "string"):
                    parts.append(v2)
                    j += 1
                    continue
                return None
            return None
        if t0 == "identifier" and v0 == "emit":
            j = self._skip_eol_pairs(pairs, j + 1)
            ev_parts: list[str] = []
            with_idx = -1
            while j < n:
                t2, v2 = pairs[j]
                if t2 == "eol":
                    if not ev_parts:
                        j += 1
                        continue
                    break
                if t2 == "brace" and v2 == "}":
                    break
                if t2 == "identifier" and v2 == "with":
                    with_idx = j
                    break
                if t2 in ("identifier", "string"):
                    ev_parts.append(v2)
                    j += 1
                    continue
                return None
            if not ev_parts:
                return None
            inner_ev = " ".join(ev_parts)[:120]
            if "|" in inner_ev:
                return None
            if with_idx >= 0:
                parsed = self._parse_with_brace_pairs(pairs, with_idx + 1)
                if not parsed:
                    return None
                kvs, j2 = parsed
                if kvs:
                    tail = "|".join(f"{k}|{v}" for k, v in kvs)
                    seg = ("listen|" + evn + "|emit|" + inner_ev + "|with|" + tail)[:255]
                else:
                    seg = ("listen|" + evn + "|emit|" + inner_ev)[:255]
                j = j2
                while j < n:
                    t2, v2 = pairs[j]
                    if t2 == "eol":
                        j += 1
                        continue
                    if t2 == "brace" and v2 == "}":
                        return (seg, j + 1)
                    return None
                return None
            if j < n and pairs[j][0] == "eol":
                j += 1
                seg = ("listen|" + evn + "|emit|" + inner_ev)[:255]
                return (seg, j)
            if j >= n or pairs[j] != ("brace", "}"):
                return None
            seg = ("listen|" + evn + "|emit|" + inner_ev)[:255]
            return (seg, j + 1)
        if t0 == "identifier" and v0 == "set":
            j = self._skip_eol_pairs(pairs, j + 1)
            if j >= n:
                return None
            vt, vv = pairs[j]
            if vt != "identifier" or not vv.startswith("::"):
                return None
            var_name = vv[:80]
            j += 1
            j = self._skip_eol_pairs(pairs, j)
            if j >= n or pairs[j] != ("operator", "="):
                return None
            j += 1
            rhs_parts: list[str] = []
            while j < n:
                t2, v2 = pairs[j]
                if t2 == "eol":
                    if not rhs_parts:
                        j += 1
                        continue
                    j += 1
                    rhs = " ".join(rhs_parts)[:200]
                    seg = ("listen|" + evn + "|set|" + var_name + "|" + rhs)[:255]
                    return (seg, j)
                if t2 == "brace" and v2 == "}":
                    if not rhs_parts:
                        return None
                    rhs = " ".join(rhs_parts)[:200]
                    seg = ("listen|" + evn + "|set|" + var_name + "|" + rhs)[:255]
                    return (seg, j + 1)
                if t2 in ("identifier", "string"):
                    rhs_parts.append(v2)
                    j += 1
                    continue
                return None
            return None
        return None

    def _pair_brace_close_index(
        self, pairs: list[tuple[str, str]], open_idx: int
    ) -> int | None:
        """``open_idx`` points at ``{``; return index of the matching ``}``."""
        n = len(pairs)
        if open_idx >= n or pairs[open_idx] != ("brace", "{"):
            return None
        d = 1
        j = open_idx + 1
        while j < n and d > 0:
            if pairs[j] == ("brace", "{"):
                d += 1
            elif pairs[j] == ("brace", "}"):
                d -= 1
            j += 1
        if d != 0:
            return None
        return j - 1

    @staticmethod
    def _quote_azl_single_from_inner(inner: str) -> str:
        esc = inner.replace("\\", "\\\\").replace("'", "\\'")
        return "'" + esc + "'"

    def _try_find_section_block(
        self,
        pairs: list[tuple[str, str]],
        inner_start: int,
        inner_end: int,
        label: str,
    ) -> tuple[int, int] | None:
        """``label { … }`` inside component body → ``(idx_after_open, idx_of_closing })``."""
        i = inner_start
        while i < inner_end:
            if pairs[i] == ("identifier", label):
                j = self._skip_eol_pairs(pairs, i + 1)
                if j < inner_end and pairs[j] == ("brace", "{"):
                    close = self._pair_brace_close_index(pairs, j)
                    if close is None:
                        return None
                    return (j + 1, close)
            i += 1
        return None

    def _try_parse_component_spine_v1_from_pairs(
        self, pairs: list[tuple[str, str]]
    ) -> str | None:
        """If ``pairs`` is exactly the supported component slice, return tab-separated spine text.

        Structured execution slice (not full AST): one ``listen`` whose body is one or more
        ``say`` / ``set`` / ``emit`` statements, plus ``init`` and ``memory`` as before.
        """
        n = len(pairs)

        def skip_e(i: int) -> int:
            while i < n and pairs[i][0] == "eol":
                i += 1
            return i

        i = skip_e(0)
        if i >= n or pairs[i] != ("identifier", "component"):
            return None
        i = skip_e(i + 1)
        if i >= n or pairs[i][0] != "identifier" or not pairs[i][1].startswith("::"):
            return None
        comp_name = pairs[i][1][:120]
        i = skip_e(i + 1)
        if i >= n or pairs[i] != ("brace", "{"):
            return None
        comp_open = i
        comp_close = self._pair_brace_close_index(pairs, comp_open)
        if comp_close is None:
            return None
        inner_s = comp_open + 1
        inner_e = comp_close

        bh = self._try_find_section_block(pairs, inner_s, inner_e, "behavior")
        ini = self._try_find_section_block(pairs, inner_s, inner_e, "init")
        mem = self._try_find_section_block(pairs, inner_s, inner_e, "memory")
        if bh is None or ini is None or mem is None:
            return None
        b_start, b_close = bh
        i_start, i_close = ini
        m_start, m_close = mem

        # behavior: one or more `listen for <ev> { say | set | emit | emit with { k: v } }`
        bh_lines: list[str] = []
        j = skip_e(b_start)
        while j < b_close:
            if j >= b_close or pairs[j] != ("identifier", "listen"):
                return None
            j = skip_e(j + 1)
            if j >= b_close or pairs[j] != ("identifier", "for"):
                return None
            j = skip_e(j + 1)
            if j >= b_close:
                return None
            et, ev_raw = pairs[j]
            if et not in ("string", "identifier"):
                return None
            evn = ev_raw[:63]
            if not evn or "|" in evn or "\t" in evn or "\n" in evn:
                return None
            j = skip_e(j + 1)
            if j < b_close and pairs[j] == ("identifier", "then"):
                j = skip_e(j + 1)
            if j >= b_close or pairs[j] != ("brace", "{"):
                return None
            lb = j
            l_close = self._pair_brace_close_index(pairs, lb)
            if l_close is None:
                return None
            n_bh_here = 0
            j = skip_e(lb + 1)
            while j < l_close:
                if pairs[j] == ("identifier", "say"):
                    j = skip_e(j + 1)
                    if j >= l_close:
                        return None
                    st, sv = pairs[j]
                    if st == "string":
                        bh_say_tok = self._quote_azl_single_from_inner(sv[:200])
                        bh_lines.append("bh\tlisten\t" + evn + "\tsay\t" + bh_say_tok)
                    elif st == "identifier" and sv.startswith("::"):
                        bh_lines.append("bh\tlisten\t" + evn + "\tsay\t" + sv[:96])
                    else:
                        return None
                    n_bh_here += 1
                    j = skip_e(j + 1)
                    continue
                if pairs[j] == ("identifier", "set"):
                    j = skip_e(j + 1)
                    if j >= l_close or pairs[j][0] != "identifier":
                        return None
                    vk = pairs[j][1][:80]
                    if not vk.startswith("::"):
                        return None
                    j = skip_e(j + 1)
                    if j >= l_close or pairs[j] != ("operator", "="):
                        return None
                    j = skip_e(j + 1)
                    if j >= l_close or pairs[j][0] != "identifier":
                        return None
                    val = pairs[j][1][:120]
                    if "|" in val or "\t" in val:
                        return None
                    bh_lines.append("bh\tlisten\t" + evn + "\tset\t" + vk + "\t" + val)
                    n_bh_here += 1
                    j = skip_e(j + 1)
                    continue
                if pairs[j] == ("identifier", "emit"):
                    j = skip_e(j + 1)
                    if j >= l_close or pairs[j][0] != "identifier":
                        return None
                    eev = pairs[j][1][:63]
                    if "|" in eev or "\t" in eev:
                        return None
                    j = skip_e(j + 1)
                    if j < l_close and pairs[j] == ("identifier", "with"):
                        j = skip_e(j + 1)
                        pr = self._parse_with_brace_pairs(pairs, j)
                        if pr is None:
                            return None
                        kv, j2 = pr
                        if len(kv) != 1:
                            return None
                        pk, pvv = kv[0]
                        if "|" in pk or "\t" in pk or "|" in pvv or "\t" in pvv:
                            return None
                        bh_lines.append(
                            "bh\tlisten\t"
                            + evn
                            + "\temit\t"
                            + eev
                            + "\twith\t"
                            + pk
                            + "\t"
                            + pvv[:120]
                        )
                        n_bh_here += 1
                        j = j2
                        continue
                    bh_lines.append("bh\tlisten\t" + evn + "\temit\t" + eev)
                    n_bh_here += 1
                    continue
                return None
            while j < l_close and pairs[j][0] == "eol":
                j = skip_e(j + 1)
            if j != l_close:
                return None
            if n_bh_here == 0:
                return None
            j = skip_e(l_close + 1)
            while j < b_close and pairs[j][0] == "eol":
                j = skip_e(j + 1)
        if not bh_lines:
            return None

        init_lines: list[str] = []
        j = skip_e(i_start)
        while j < i_close:
            if pairs[j] == ("identifier", "say"):
                j = skip_e(j + 1)
                if j >= i_close or pairs[j][0] != "string":
                    return None
                init_lines.append(
                    "in\tsay\t" + self._quote_azl_single_from_inner(pairs[j][1][:200])
                )
                j = skip_e(j + 1)
                continue
            if pairs[j] == ("identifier", "emit"):
                j = skip_e(j + 1)
                if j >= i_close or pairs[j][0] != "identifier":
                    return None
                eev = pairs[j][1][:63]
                if "|" in eev or "\t" in eev:
                    return None
                init_lines.append("in\temit\t" + eev)
                j = skip_e(j + 1)
                continue
            return None
        while j < i_close and pairs[j][0] == "eol":
            j = skip_e(j + 1)
        if j != i_close:
            return None

        mem_lines: list[str] = []
        j = skip_e(m_start)
        while j < m_close:
            if pairs[j] == ("identifier", "say"):
                j = skip_e(j + 1)
                if j >= m_close:
                    return None
                st, sv = pairs[j]
                if st == "string":
                    mem_lines.append(
                        "mem\tsay\t"
                        + self._quote_azl_single_from_inner(sv[:200])
                    )
                    j = skip_e(j + 1)
                    continue
                if st == "identifier" and sv.startswith("::"):
                    mem_lines.append("mem\tsay\t" + sv[:80])
                    j = skip_e(j + 1)
                    continue
                return None
            if pairs[j] == ("identifier", "set"):
                j = skip_e(j + 1)
                if j >= m_close or pairs[j][0] != "identifier":
                    return None
                vk = pairs[j][1][:80]
                if not vk.startswith("::"):
                    return None
                j = skip_e(j + 1)
                if j >= m_close or pairs[j] != ("operator", "="):
                    return None
                j = skip_e(j + 1)
                if j >= m_close or pairs[j][0] != "identifier":
                    return None
                val = pairs[j][1][:120]
                if "|" in val or "\t" in val:
                    return None
                mem_lines.append("mem\tset\t" + vk + "\t" + val)
                j = skip_e(j + 1)
                continue
            return None
        while j < m_close and pairs[j][0] == "eol":
            j = skip_e(j + 1)
        if j != m_close:
            return None

        out_lines = [
            "spine_component_v1",
            "comp\t" + comp_name,
            *bh_lines,
            *init_lines,
            *mem_lines,
        ]
        return "\n".join(out_lines)

    @staticmethod
    def _brace_close_index(
        pairs: list[tuple[str, str]], open_brace_idx: int, n: int
    ) -> int:
        depth = 0
        k = open_brace_idx
        while k < n:
            t2, v2 = pairs[k]
            if t2 == "brace" and v2 == "{":
                depth += 1
            elif t2 == "brace" and v2 == "}":
                depth -= 1
                if depth == 0:
                    return k
            k += 1
        return -1

    @staticmethod
    def _collect_if_condition(
        pairs: list[tuple[str, str]], j: int, n: int
    ) -> tuple[str, int] | None:
        depth = 1
        parts: list[str] = []
        while j < n:
            t2, v2 = pairs[j]
            if t2 == "paren" and v2 == "(":
                depth += 1
                parts.append("(")
                j += 1
                continue
            if t2 == "paren" and v2 == ")":
                depth -= 1
                if depth == 0:
                    return " ".join(parts).strip(), j + 1
                parts.append(")")
                j += 1
                continue
            if t2 in ("identifier", "string", "operator"):
                parts.append(v2)
                j += 1
                continue
            return None
        return None

    def _execute_ast_if_condition_take_then(self, cond_raw: str) -> bool:
        """``if|`` branch choice only: reuse ``eval_expr`` + ``_cond_is_true`` (same host rule as ``exec_if``)."""
        raw = (cond_raw or "").strip()
        if not raw:
            return False
        raw = raw.replace(" = = ", "==")
        try:
            toks = tokenize_source(raw)
        except Exception:
            return False
        if not toks:
            return False
        save_tok, save_ntok = self.tok, self.ntok
        try:
            self.tok = toks
            self.ntok = len(toks)
            idx = [0]
            val = self.eval_expr(idx)
            if idx[0] != self.ntok:
                return False
            return self._cond_is_true(val)
        except SemanticEngineError:
            return False
        finally:
            self.tok = save_tok
            self.ntok = save_ntok

    def _try_parse_if_spine_row(
        self, pairs: list[tuple[str, str]], i: int, n: int
    ) -> tuple[str, int] | None:
        """Serialize ``if`` / ``otherwise`` as one ``if|`` + JSON row (branch in ``_builtin_execute_ast_run_lines``)."""
        if i >= n or pairs[i] != ("identifier", "if"):
            return None
        j = self._skip_eol_pairs(pairs, i + 1)
        if j >= n or pairs[j] != ("paren", "("):
            return None
        j += 1
        j = self._skip_eol_pairs(pairs, j)
        cres = self._collect_if_condition(pairs, j, n)
        if cres is None:
            return None
        cond_raw, j = cres
        j = self._skip_eol_pairs(pairs, j)
        if j >= n or pairs[j] != ("brace", "{"):
            return None
        then_open = j
        then_close = self._brace_close_index(pairs, then_open, n)
        if then_close < 0:
            return None
        then_lo = then_open + 1
        then_hi = then_close
        j = then_close + 1
        else_lo: int | None = None
        else_hi: int | None = None
        j = self._skip_eol_pairs(pairs, j)
        if (
            j < n
            and pairs[j][0] == "identifier"
            and pairs[j][1] in ("else", "otherwise")
        ):
            j = self._skip_eol_pairs(pairs, j + 1)
            if j < n and pairs[j] == ("brace", "{"):
                e_open = j
                e_close = self._brace_close_index(pairs, e_open, n)
                if e_close < 0:
                    return None
                else_lo = e_open + 1
                else_hi = e_close
                j = e_close + 1

        then_lines = self._parse_tokens_nodes_range(pairs, then_lo, then_hi)
        else_lines: list[str] = (
            self._parse_tokens_nodes_range(pairs, else_lo, else_hi)
            if else_lo is not None and else_hi is not None
            else []
        )
        payload = {"c": cond_raw, "t": then_lines, "f": else_lines}
        line = "if|" + json.dumps(payload, separators=(",", ":"))
        if len(line) > INTERP_BLOB_VAR_MAX:
            return None
        return (line, j)

    def _parse_tokens_nodes_range(
        self, pairs: list[tuple[str, str]], lo: int, hi: int
    ) -> list[str]:
        """Half-open range ``[lo, hi)`` of tz pairs → execute_ast pipe lines."""
        out_lines: list[str] = []
        i = lo
        n = hi
        while i < n:
            typ, val = pairs[i]
            if typ == "eol":
                i += 1
                continue
            if typ == "identifier" and val == "if":
                if_row = self._try_parse_if_spine_row(pairs, i, n)
                if if_row is not None:
                    out_lines.append(if_row[0])
                    i = if_row[1]
                    continue
            if typ == "identifier" and val == "say":
                j = self._skip_eol_pairs(pairs, i + 1)
                parts: list[str] = []
                while j < n:
                    t2, v2 = pairs[j]
                    if t2 == "eol" or (t2 == "brace" and v2 == "}"):
                        break
                    if t2 in ("identifier", "string"):
                        parts.append(v2)
                        j += 1
                        continue
                    break
                if parts:
                    out_lines.append("say|" + " ".join(parts)[:200])
                    i = j
                    continue
            if typ == "identifier" and val == "set":
                j = self._skip_eol_pairs(pairs, i + 1)
                if j >= n:
                    i += 1
                    continue
                vt, vv = pairs[j]
                if vt != "identifier" or not vv.startswith("::"):
                    i += 1
                    continue
                var_name = vv[:80]
                j += 1
                j = self._skip_eol_pairs(pairs, j)
                if j >= n or pairs[j] != ("operator", "="):
                    i += 1
                    continue
                j += 1
                rhs_parts: list[str] = []
                while j < n:
                    t2, v2 = pairs[j]
                    if t2 == "eol" or (t2 == "brace" and v2 == "}"):
                        break
                    if t2 in ("identifier", "string"):
                        rhs_parts.append(v2)
                        j += 1
                        continue
                    break
                if rhs_parts:
                    rhs = " ".join(rhs_parts)[:200]
                    out_lines.append("set|" + var_name + "|" + rhs)
                i = j
                continue
            if typ == "identifier" and val == "let":
                j = self._skip_eol_pairs(pairs, i + 1)
                if j >= n:
                    i += 1
                    continue
                vt, vv = pairs[j]
                if vt != "identifier" or not vv.startswith("::"):
                    i += 1
                    continue
                var_let = vv[:80]
                j += 1
                j = self._skip_eol_pairs(pairs, j)
                if j >= n or pairs[j] != ("operator", "="):
                    i += 1
                    continue
                j += 1
                rhs_let: list[str] = []
                while j < n:
                    t2, v2 = pairs[j]
                    if t2 == "eol" or (t2 == "brace" and v2 == "}"):
                        break
                    if t2 in ("identifier", "string"):
                        rhs_let.append(v2)
                        j += 1
                        continue
                    break
                if rhs_let:
                    rhs_l = " ".join(rhs_let)[:200]
                    out_lines.append("let|" + var_let + "|" + rhs_l)
                i = j
                continue
            if typ == "identifier" and val == "emit":
                j = self._skip_eol_pairs(pairs, i + 1)
                ev_parts: list[str] = []
                with_idx = -1
                while j < n:
                    t2, v2 = pairs[j]
                    if t2 == "eol" or (t2 == "brace" and v2 == "}"):
                        break
                    if t2 == "identifier" and v2 == "with":
                        with_idx = j
                        break
                    if t2 in ("identifier", "string"):
                        ev_parts.append(v2)
                        j += 1
                        continue
                    break
                if not ev_parts:
                    i += 1
                    continue
                ev = " ".join(ev_parts)[:120]
                if "|" in ev:
                    i += 1
                    continue
                if with_idx >= 0:
                    parsed = self._parse_with_brace_pairs(pairs, with_idx + 1)
                    if parsed:
                        kvs, j2 = parsed
                        if kvs:
                            tail = "|".join(f"{k}|{v}" for k, v in kvs)
                            seg = ("emit|" + ev + "|with|" + tail)[:255]
                            out_lines.append(seg)
                        else:
                            out_lines.append("emit|" + ev)
                        i = j2
                        continue
                    out_lines.append("emit|" + ev)
                    i = with_idx + 1
                    continue
                out_lines.append("emit|" + ev)
                i = j
                continue
            if typ == "identifier" and val == "import":
                j = self._skip_eol_pairs(pairs, i + 1)
                if j < n and pairs[j][0] in ("identifier", "string"):
                    out_lines.append("import|" + pairs[j][1][:200])
                    i = j + 1
                    continue
            if typ == "identifier" and val == "link":
                j = self._skip_eol_pairs(pairs, i + 1)
                if j < n and pairs[j][0] in ("identifier", "string"):
                    out_lines.append("link|" + pairs[j][1][:200])
                    i = j + 1
                    continue
            if typ == "identifier" and val == "component":
                j = self._skip_eol_pairs(pairs, i + 1)
                if j < n:
                    ct, cv = pairs[j]
                    if ct == "identifier" and cv.startswith("::"):
                        out_lines.append("component|" + cv[:200])
                        i = j + 1
                        continue
            if typ == "identifier" and val == "memory":
                jm = self._skip_eol_pairs(pairs, i + 1)
                if jm >= n:
                    i += 1
                    continue
                tkw, vkw = pairs[jm]
                if tkw != "identifier":
                    i += 1
                    continue
                if vkw == "say":
                    j = self._skip_eol_pairs(pairs, jm + 1)
                    mem_parts: list[str] = []
                    while j < n:
                        t2, v2 = pairs[j]
                        if t2 == "eol" or (t2 == "brace" and v2 == "}"):
                            break
                        if t2 in ("identifier", "string"):
                            mem_parts.append(v2)
                            j += 1
                            continue
                        break
                    if mem_parts:
                        out_lines.append(
                            "memory|say|" + " ".join(mem_parts)[:200]
                        )
                        i = j
                        continue
                if vkw == "set":
                    j = self._skip_eol_pairs(pairs, jm + 1)
                    if j >= n:
                        i += 1
                        continue
                    vt, vv = pairs[j]
                    if vt != "identifier" or not vv.startswith("::"):
                        i += 1
                        continue
                    var_name = vv[:80]
                    j += 1
                    j = self._skip_eol_pairs(pairs, j)
                    if j >= n or pairs[j] != ("operator", "="):
                        i += 1
                        continue
                    j += 1
                    rhs_mem: list[str] = []
                    while j < n:
                        t2, v2 = pairs[j]
                        if t2 == "eol" or (t2 == "brace" and v2 == "}"):
                            break
                        if t2 in ("identifier", "string"):
                            rhs_mem.append(v2)
                            j += 1
                            continue
                        break
                    if rhs_mem:
                        rhs = " ".join(rhs_mem)[:200]
                        out_lines.append("memory|set|" + var_name + "|" + rhs)
                    i = j
                    continue
                if vkw == "emit":
                    j = self._skip_eol_pairs(pairs, jm + 1)
                    ev_m: list[str] = []
                    with_m = -1
                    while j < n:
                        t2, v2 = pairs[j]
                        if t2 == "eol" or (t2 == "brace" and v2 == "}"):
                            break
                        if t2 == "identifier" and v2 == "with":
                            with_m = j
                            break
                        if t2 in ("identifier", "string"):
                            ev_m.append(v2)
                            j += 1
                            continue
                        break
                    if not ev_m:
                        i += 1
                        continue
                    ev = " ".join(ev_m)[:120]
                    if "|" in ev:
                        i += 1
                        continue
                    if with_m >= 0:
                        parsed_m = self._parse_with_brace_pairs(
                            pairs, with_m + 1
                        )
                        if parsed_m:
                            kvs_m, j2m = parsed_m
                            if kvs_m:
                                tail_m = "|".join(f"{k}|{v}" for k, v in kvs_m)
                                seg_m = ("memory|emit|" + ev + "|with|" + tail_m)[
                                    :255
                                ]
                                out_lines.append(seg_m)
                            else:
                                out_lines.append(("memory|emit|" + ev)[:255])
                            i = j2m
                            continue
                        out_lines.append(("memory|emit|" + ev)[:255])
                        i = with_m + 1
                        continue
                    out_lines.append(("memory|emit|" + ev)[:255])
                    i = j
                    continue
                i += 1
                continue
            if typ == "identifier" and val == "listen":
                j = self._skip_eol_pairs(pairs, i + 1)
                if j >= n or pairs[j] != ("identifier", "for"):
                    i += 1
                    continue
                j = self._skip_eol_pairs(pairs, j + 1)
                if j >= n:
                    i += 1
                    continue
                et, ev = pairs[j]
                if et == "string":
                    evn = ev[:63]
                elif et == "identifier":
                    evn = ev[:63]
                else:
                    i += 1
                    continue
                if not evn or "|" in evn:
                    i += 1
                    continue
                j = self._skip_eol_pairs(pairs, j + 1)
                if j < n and pairs[j] == ("identifier", "then"):
                    j = self._skip_eol_pairs(pairs, j + 1)
                if j >= n or pairs[j] != ("brace", "{"):
                    i += 1
                    continue
                j = self._skip_eol_pairs(pairs, j + 1)
                inner_lines: list[str] = []
                inner_failed = False
                while j < n:
                    t_skip, v_skip = pairs[j]
                    if t_skip == "eol":
                        j += 1
                        continue
                    if t_skip == "brace" and v_skip == "}":
                        j += 1
                        break
                    parsed_ln = self._parse_listen_inner_to_row(pairs, j, n, evn)
                    if parsed_ln is None:
                        inner_failed = True
                        break
                    line, j2 = parsed_ln
                    inner_lines.append(line)
                    j = j2
                if inner_failed or not inner_lines:
                    i += 1
                    continue
                for line in inner_lines:
                    out_lines.append(line)
                i = j
                continue
            if typ == "identifier" and val == "on":
                j = self._skip_eol_pairs(pairs, i + 1)
                if j >= n or pairs[j][0] != "identifier":
                    i += 1
                    continue
                fname = pairs[j][1][:63]
                if not fname or "|" in fname:
                    i += 1
                    continue
                j = self._skip_eol_pairs(pairs, j + 1)
                if j >= n or pairs[j] != ("brace", "{"):
                    i += 1
                    continue
                j = self._skip_eol_pairs(pairs, j + 1)
                parsed_on = self._parse_listen_inner_to_row(
                    pairs, j, n, "__dummy_on__"
                )
                if parsed_on is None:
                    i += 1
                    continue
                ln_on, j2 = parsed_on
                prefix = "listen|__dummy_on__|say|"
                if not ln_on.startswith(prefix):
                    i += 1
                    continue
                pay_on = ln_on[len(prefix) :]
                out_lines.append(("fn|" + fname + "|say|" + pay_on)[:255])
                i = j2
                continue
            if typ == "identifier" and val not in (
                "say",
                "set",
                "let",
                "emit",
                "listen",
                "import",
                "link",
                "component",
                "memory",
                "on",
                "for",
                "then",
                "with",
                "if",
                "else",
                "otherwise",
            ):
                j = self._skip_eol_pairs(pairs, i + 1)
                if j < n and pairs[j] == ("paren", "("):
                    j += 1
                    j = self._skip_eol_pairs(pairs, j)
                    if j < n and pairs[j] == ("paren", ")"):
                        out_lines.append(("call|" + val[:63])[:255])
                        i = j + 1
                        continue
            i += 1
        return out_lines

    def _parse_tokens_nodes_from_buffer(self, buf: str) -> str:
        """Serialize tz buffer → ``::ast.nodes`` pipe text for bootstrap ``::execute_ast`` (contract vs C + AZL parse)."""
        pairs = self._parse_tz_buffer_pairs(buf)
        out_lines = self._parse_tokens_nodes_range(pairs, 0, len(pairs))
        if not out_lines:
            return "say|AZL_SPINE_SEMANTIC_PARSE_EXECUTE_BRIDGE"
        return "\n".join(out_lines)

    def _token_to_tz_row(self, tok: str, ln: str, col_s: str) -> str:
        if len(tok) >= 2 and tok[0] in "\"'":
            inner = self._unescape_azl_string_token(tok)
            return self._format_tz_row("string", inner[:200], ln, col_s)
        if tok in ("{", "}"):
            return self._format_tz_row("brace", tok[:1], ln, col_s)
        if tok in ("(", ")"):
            return self._format_tz_row("paren", tok[:1], ln, col_s)
        if tok == "=":
            return self._format_tz_row("operator", "=", ln, col_s)
        return self._format_tz_row("identifier", tok[:200], ln, col_s)

    def _builtin_tokenize_line(self, line_text: str, line_no_s: str) -> str:
        s = (line_text or "").strip()
        if not s:
            return ""
        ln = (line_no_s or "1").strip()
        if not ln.isdigit():
            ln = "1"
        try:
            toks = tokenize_source(s)
        except Exception:
            return self._format_tz_row("identifier", s[:80], ln, "1")
        if not toks:
            return ""
        n = len(s)
        p = 0
        rows: list[str] = []
        for t in toks:
            while p < n and s[p] in " \t\r":
                p += 1
            col_s = str(p + 1)
            if p + len(t) <= n and s[p : p + len(t)] == t:
                rows.append(self._token_to_tz_row(t, ln, col_s))
                p += len(t)
            else:
                rows.append(self._token_to_tz_row(t, ln, "1"))
                p = min(p + max(len(t), 1), n)
        return "\n".join(rows)

    def _try_spine_interpreter_builtin_statement(self, i: list[int]) -> bool:
        """Standalone ``::insert_cache(...)`` / ``::touch_cache_key(...)`` in listener bodies."""
        t = self.tok[i[0]]
        if t == "::insert_cache":
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != "(":
                raise SemanticEngineError(
                    5, "azl_semantic_engine: insert_cache missing ("
                )
            i[0] += 1
            if i[0] >= self.ntok or not self.tok[i[0]].startswith("::"):
                raise SemanticEngineError(
                    5, "azl_semantic_engine: insert_cache bad key arg"
                )
            key_raw = self.var_get(self.tok[i[0]]) or ""
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != ",":
                raise SemanticEngineError(
                    5, "azl_semantic_engine: insert_cache missing ,"
                )
            i[0] += 1
            if i[0] >= self.ntok:
                raise SemanticEngineError(5, "azl_semantic_engine: insert_cache eof")
            if self.tok[i[0]] == "null":
                i[0] += 1
                if i[0] >= self.ntok or self.tok[i[0]] != ",":
                    raise SemanticEngineError(
                        5, "azl_semantic_engine: insert_cache missing , after null"
                    )
                i[0] += 1
                if i[0] >= self.ntok or not self.tok[i[0]].startswith("::"):
                    raise SemanticEngineError(
                        5, "azl_semantic_engine: insert_cache bad ast arg"
                    )
                ast_v = self.var_get(self.tok[i[0]]) or ""
                i[0] += 1
                if i[0] >= self.ntok or self.tok[i[0]] != ")":
                    raise SemanticEngineError(
                        5, "azl_semantic_engine: insert_cache missing )"
                    )
                i[0] += 1
                self._perf_ast_cache[key_raw[:200]] = ast_v[:65536]
                return True
            if not self.tok[i[0]].startswith("::"):
                raise SemanticEngineError(
                    5, "azl_semantic_engine: insert_cache bad tokens arg"
                )
            toks_v = self.var_get(self.tok[i[0]]) or ""
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != ",":
                raise SemanticEngineError(
                    5, "azl_semantic_engine: insert_cache missing , (tokens)"
                )
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != "null":
                raise SemanticEngineError(
                    5, "azl_semantic_engine: insert_cache expected null after tokens"
                )
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != ")":
                raise SemanticEngineError(
                    5, "azl_semantic_engine: insert_cache missing )"
                )
            i[0] += 1
            self._perf_tok_cache[key_raw[:200]] = toks_v[:65536]
            return True
        if t == "::touch_cache_key":
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != "(":
                raise SemanticEngineError(
                    5, "azl_semantic_engine: touch_cache_key missing ("
                )
            i[0] += 1
            if i[0] >= self.ntok or not self.tok[i[0]].startswith("::"):
                raise SemanticEngineError(
                    5, "azl_semantic_engine: touch_cache_key bad arg"
                )
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != ")":
                raise SemanticEngineError(
                    5, "azl_semantic_engine: touch_cache_key missing )"
                )
            i[0] += 1
            return True
        return False

    def find_block_end(self, i: int) -> int:
        depth = 1
        while i < self.ntok:
            t = self.tok[i]
            if t == "{":
                depth += 1
            elif t == "}":
                depth -= 1
                if depth <= 0:
                    return i
            i += 1
        return self.ntok

    def _say_expand_double_quoted(self, inner: str) -> None:
        n = len(inner)
        p = 0
        while p < n:
            if p + 1 < n and inner[p] == ":" and inner[p + 1] == ":":
                path0 = p + 2
                if path0 >= n or (not inner[path0].isalpha() and inner[path0] != "_"):
                    sys.stdout.write(":")
                    p += 1
                    continue
                j = path0 + 1
                while j < n and (inner[j].isalnum() or inner[j] == "_"):
                    j += 1
                use_length = False
                end_hole = j
                parse_ok = True
                while True:
                    if j + 7 <= n and inner[j : j + 7] == ".length":
                        after = j + 7
                        if after == n or not (
                            inner[after].isalnum() or inner[after] == "_" or inner[after] == "."
                        ):
                            use_length = True
                            end_hole = after
                            break
                    if j < n and inner[j] == ".":
                        j += 1
                        if j >= n or (not inner[j].isalpha() and inner[j] != "_"):
                            parse_ok = False
                            break
                        j += 1
                        while j < n and (inner[j].isalnum() or inner[j] == "_"):
                            j += 1
                        continue
                    end_hole = j
                    break
                if not parse_ok:
                    sys.stdout.write(":")
                    p += 1
                    continue
                key = "::" + inner[path0:j]
                if len(key) >= 128:
                    raise SemanticEngineError(5, "azl_semantic_engine: say interpolation key too long")
                vv = self.var_get(key)
                if use_length:
                    sys.stdout.write(str(0 if vv is None else len(vv)))
                elif vv:
                    sys.stdout.write(vv)
                p = end_hole
            else:
                sys.stdout.write(inner[p])
                p += 1

    def exec_say(self, i: list[int]) -> None:
        i[0] += 1
        if i[0] >= self.ntok:
            return
        s = self.tok[i[0]]
        if len(s) >= 2 and s[0] == '"':
            inner = s[1:-1] if len(s) >= 2 else ""
            self._say_expand_double_quoted(inner)
            sys.stdout.write("\n")
            sys.stdout.flush()
            i[0] += 1
        elif len(s) >= 2 and s[0] == "'":
            inner = s[1:-1] if len(s) >= 2 else ""
            sys.stdout.write(inner)
            sys.stdout.write("\n")
            sys.stdout.flush()
            i[0] += 1
        elif s.startswith("::"):
            v = self.var_get(s)
            if v:
                sys.stdout.write(v)
            sys.stdout.write("\n")
            sys.stdout.flush()
            i[0] += 1
        else:
            i[0] += 1

    def _consume_agg_literal(self, i: list[int]) -> None:
        if i[0] >= self.ntok:
            return
        open_t = self.tok[i[0]]
        if open_t == "[":
            close_t = "]"
        elif open_t == "{":
            close_t = "}"
        else:
            return
        d = 1
        i[0] += 1
        while i[0] < self.ntok and d > 0:
            t = self.tok[i[0]]
            if t == open_t:
                d += 1
            elif t == close_t:
                d -= 1
            i[0] += 1

    @staticmethod
    def _tz_esc_field(s: str) -> str:
        out: list[str] = []
        for ch in s:
            if ch in "|\\":
                out.append("\\")
            out.append(ch)
        return "".join(out)

    def _parse_push_tz_object(self, i: list[int]) -> str:
        """Parse `{ type: "…", value: "…", line: N, column: M }` for .push (flat keys only)."""
        if i[0] >= self.ntok or self.tok[i[0]] != "{":
            raise SemanticEngineError(5, "azl_semantic_engine: .push object missing {")
        i[0] += 1
        fields: dict[str, str] = {
            "type": "",
            "value": "",
            "line": "",
            "column": "",
        }
        depth = 1
        allowed = frozenset(fields)
        while i[0] < self.ntok and depth > 0:
            t = self.tok[i[0]]
            if t == "{":
                raise SemanticEngineError(5, "azl_semantic_engine: .push object nested {")
            if t == "}":
                depth -= 1
                i[0] += 1
                if depth == 0:
                    break
                continue
            if depth != 1:
                raise SemanticEngineError(5, "azl_semantic_engine: .push object bad depth")
            key: str | None = None
            if len(t) >= 2 and t.endswith(":") and self._payload_key_ok(t[:-1]):
                key = t[:-1]
                i[0] += 1
            elif self._payload_key_ok(t):
                key = t
                i[0] += 1
                if i[0] >= self.ntok or self.tok[i[0]] != ":":
                    raise SemanticEngineError(5, "azl_semantic_engine: .push object key:")
                i[0] += 1
            else:
                raise SemanticEngineError(5, "azl_semantic_engine: .push object bad key")
            if key not in allowed:
                raise SemanticEngineError(5, "azl_semantic_engine: .push object unknown key")
            if i[0] >= self.ntok:
                raise SemanticEngineError(5, "azl_semantic_engine: .push object eof value")
            vt = self.tok[i[0]]
            if len(vt) >= 2 and vt[0] in "\"'":
                inner = vt[1:-1] if len(vt) >= 2 else ""
                raw = inner
            elif vt and vt.isdigit():
                raw = vt
            elif vt.startswith("::"):
                raw = self.var_get(vt) or ""
            else:
                raise SemanticEngineError(5, "azl_semantic_engine: .push object bad value")
            i[0] += 1
            fields[key] = raw[:64]
            if i[0] < self.ntok and self.tok[i[0]] == ",":
                i[0] += 1
        if depth != 0:
            raise SemanticEngineError(5, "azl_semantic_engine: .push object unclosed")
        parts = [
            self._tz_esc_field(fields["type"]),
            self._tz_esc_field(fields["value"]),
            self._tz_esc_field(fields["line"]),
            self._tz_esc_field(fields["column"]),
        ]
        return "tz|" + "|".join(parts)

    @staticmethod
    def _rhs_concat_base(v: str) -> str | None:
        suf = ".concat"
        if (
            not v.startswith("::")
            or not v.endswith(suf)
            or len(v) <= len(suf) + 2
        ):
            return None
        return v[: -len(suf)]

    def _values_eq(self, l_nullish: int, l: str, r_nullish: int, r: str) -> bool:
        if l_nullish and r_nullish:
            return True
        if l_nullish or r_nullish:
            return False
        return l == r

    def _eval_primary(self, i: list[int]) -> tuple[str, int]:
        if i[0] >= self.ntok:
            raise SemanticEngineError(5, "azl_semantic_engine: expression primary: eof")
        t = self.tok[i[0]]
        if t == "(":
            i[0] += 1
            inner = self._eval_or(i)
            if i[0] >= self.ntok or self.tok[i[0]] != ")":
                raise SemanticEngineError(5, "azl_semantic_engine: expected )")
            i[0] += 1
            s, nn = inner, 0
            while (
                i[0] + 2 < self.ntok
                and self.tok[i[0]] == "."
                and self.tok[i[0] + 1] == "toInt"
                and self.tok[i[0] + 2] == "("
            ):
                i[0] += 3
                if i[0] >= self.ntok or self.tok[i[0]] != ")":
                    raise SemanticEngineError(5, "azl_semantic_engine: toInt() expected )")
                i[0] += 1
                raw = "" if nn else s.strip()
                try:
                    s = str(int(raw)) if raw else "0"
                except ValueError:
                    s = "0"
                nn = 0
            return s, nn
        if len(t) >= 2 and t[0] in "\"'":
            inner = self._unescape_azl_string_token(t)
            i[0] += 1
            return inner, 0
        if t and (
            t[0].isdigit()
            or (t[0] == "-" and len(t) > 1 and t[1].isdigit())
        ):
            i[0] += 1
            return t, 0
        if t == "null":
            i[0] += 1
            return "", 1
        if t in ("false", "true"):
            i[0] += 1
            return t, 0
        if t and (t[0].isalpha() or t[0] == "_") and all(
            ch.isalnum() or ch == "_" for ch in t
        ):
            if t not in _BARE_ID_FORBIDDEN:
                i[0] += 1
                gk = "::" + t
                vv = self.var_get(gk)
                if vv is None:
                    return "", 1
                # Interpreter-shaped cache slots (e.g. cached_tok): empty string means "unset".
                if vv == "":
                    return "", 1
                return vv, 0
        if t.startswith("::"):
            if t == "::internal.env":
                i[0] += 1
                if i[0] >= self.ntok or self.tok[i[0]] != "(":
                    raise SemanticEngineError(5, "azl_semantic_engine: env ( expected")
                i[0] += 1
                if i[0] >= self.ntok:
                    raise SemanticEngineError(5, "azl_semantic_engine: env key expected")
                ts = self.tok[i[0]]
                if len(ts) < 2 or ts[0] not in "\"'":
                    raise SemanticEngineError(5, "azl_semantic_engine: env key must be string")
                key = ts[1:-1] if len(ts) >= 2 else ""
                i[0] += 1
                if i[0] >= self.ntok or self.tok[i[0]] != ")":
                    raise SemanticEngineError(5, "azl_semantic_engine: env ) expected")
                i[0] += 1
                return os.environ.get(key, ""), 0
            if t.endswith(".length") and len(t) > len(".length") + 2:
                base = t[: -len(".length")]
                if base.startswith("::"):
                    i[0] += 1
                    vv = self.var_get(base)
                    return (str(0 if vv is None else len(vv)), 0)
            if t == "::perf.tok_cache":
                i[0] += 1
                if i[0] >= self.ntok or self.tok[i[0]] != "[":
                    raise SemanticEngineError(
                        5, "azl_semantic_engine: perf.tok_cache[ expected"
                    )
                i[0] += 1
                key_s, _ = self._eval_primary(i)
                if i[0] >= self.ntok or self.tok[i[0]] != "]":
                    raise SemanticEngineError(5, "azl_semantic_engine: perf.tok_cache ] expected")
                i[0] += 1
                raw = self._perf_tok_cache.get(key_s)
                if raw is None:
                    return "", 1
                # Values are capped at insert (::insert_cache uses 65536); do not re-truncate to
                # MAX_VAR_VALUE_LEN or tokenize/parse cache hits corrupt the interpreter chain.
                return raw, 0
            if t == "::perf.ast_cache":
                i[0] += 1
                if i[0] >= self.ntok or self.tok[i[0]] != "[":
                    raise SemanticEngineError(
                        5, "azl_semantic_engine: perf.ast_cache[ expected"
                    )
                i[0] += 1
                key_s, _ = self._eval_primary(i)
                if i[0] >= self.ntok or self.tok[i[0]] != "]":
                    raise SemanticEngineError(5, "azl_semantic_engine: perf.ast_cache ] expected")
                i[0] += 1
                raw = self._perf_ast_cache.get(key_s)
                if raw is None:
                    return "", 1
                return raw, 0
            vv = self.var_get(t)
            i[0] += 1
            if vv is None:
                return "", 1
            return vv, 0
        raise SemanticEngineError(5, f"azl_semantic_engine: bad primary {t!r}")

    def _eval_sum(self, i: list[int]) -> tuple[str, int]:
        """Primary (+ primary)* — integer + if both parse as base-10 int, else string concat."""

        def parse_full_int(s: str, nullish: int) -> int | None:
            if nullish:
                return None
            s = s.strip()
            if not s:
                return None
            try:
                v = int(s, 10)
            except ValueError:
                return None
            return v if str(v) == s else None

        acc_s, acc_n = self._eval_primary(i)
        while i[0] < self.ntok and self.tok[i[0]] in ("+", "-"):
            op = self.tok[i[0]]
            i[0] += 1
            rh_s, rh_n = self._eval_primary(i)
            ai = parse_full_int(acc_s, acc_n)
            bi = parse_full_int(rh_s, rh_n)
            if ai is not None and bi is not None:
                acc_s = str(ai - bi if op == "-" else ai + bi)
                acc_n = 0
            else:
                if op == "-":
                    raise SemanticEngineError(
                        5,
                        "azl_semantic_engine: - requires integer operands",
                    )
                acc_s = ("" if acc_n else acc_s) + ("" if rh_n else rh_s)
                acc_n = 0
        return acc_s, acc_n

    def _eval_eq(self, i: list[int]) -> tuple[str, int]:
        left, ln = self._eval_sum(i)
        if i[0] >= self.ntok or self.tok[i[0]] not in ("==", "!="):
            return left, ln
        op = self.tok[i[0]]
        i[0] += 1
        right, rn = self._eval_sum(i)
        eq = self._values_eq(ln, left, rn, right)
        if op == "!=":
            eq = not eq
        return ("true" if eq else "false"), 0

    def _eval_and(self, i: list[int]) -> tuple[str, int]:
        acc, acc_n = self._eval_eq(i)
        while i[0] < self.ntok and self.tok[i[0]] == "&&":
            i[0] += 1
            if not self._cond_is_true(acc):
                _, _ = self._eval_eq(i)
                while i[0] < self.ntok and self.tok[i[0]] == "&&":
                    i[0] += 1
                    _, _ = self._eval_eq(i)
                return "false", 0
            nxt, nn = self._eval_eq(i)
            acc = nxt
            acc_n = nn
        return acc, acc_n

    def _eval_or(self, i: list[int]) -> str:
        acc, acc_nullish = self._eval_and(i)
        while i[0] < self.ntok and self.tok[i[0]] == "or":
            i[0] += 1
            nxt, nn = self._eval_and(i)
            if acc_nullish or acc == "":
                acc = nxt
                acc_nullish = nn
        return acc

    def eval_expr(self, i: list[int]) -> str:
        return self._eval_or(i)

    def _cond_is_true(self, s: str) -> bool:
        return s in ("true", "1")

    @staticmethod
    def _unescape_azl_string_token(quoted: str) -> str:
        if len(quoted) < 2 or quoted[0] not in "\"'":
            return ""
        inner = quoted[1:-1]
        out: list[str] = []
        p = 0
        while p < len(inner):
            if inner[p] == "\\" and p + 1 < len(inner):
                n = inner[p + 1]
                if n == "n":
                    out.append("\n")
                elif n == "t":
                    out.append("\t")
                elif n == "r":
                    out.append("\r")
                elif n == "\\":
                    out.append("\\")
                elif n == '"':
                    out.append('"')
                elif n == "'":
                    out.append("'")
                else:
                    out.append(n)
                p += 2
            else:
                out.append(inner[p])
                p += 1
        return "".join(out)

    def _skip_braced_block(self, i: list[int]) -> None:
        if i[0] >= self.ntok or self.tok[i[0]] != "{":
            return
        d = 1
        i[0] += 1
        while i[0] < self.ntok and d > 0:
            if self.tok[i[0]] == "{":
                d += 1
            elif self.tok[i[0]] == "}":
                d -= 1
            i[0] += 1

    def exec_if(self, i: list[int]) -> None:
        i[0] += 1
        cond = self.eval_expr(i)
        if i[0] >= self.ntok or self.tok[i[0]] != "{":
            raise SemanticEngineError(5, "azl_semantic_engine: if missing {")
        took_then = self._cond_is_true(cond)
        if took_then:
            i[0] += 1
            self.exec_init_block(i)
            if i[0] < self.ntok and self.tok[i[0]] == "}":
                i[0] += 1
        else:
            self._skip_braced_block(i)
        if i[0] < self.ntok and self.tok[i[0]] == "else":
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != "{":
                raise SemanticEngineError(5, "azl_semantic_engine: else missing {")
            if took_then:
                self._skip_braced_block(i)
            else:
                i[0] += 1
                self.exec_init_block(i)
                if i[0] < self.ntok and self.tok[i[0]] == "}":
                    i[0] += 1

    def exec_for_in(self, i: list[int]) -> None:
        """for ::var in ::seq { body } — listener bodies only (invoked from exec_block)."""
        i[0] += 1
        if i[0] >= self.ntok:
            return
        loop_var = self.tok[i[0]]
        if not loop_var.startswith("::"):
            i[0] += 1
            return
        i[0] += 1
        if i[0] >= self.ntok or self.tok[i[0]] != "in":
            return
        i[0] += 1
        if i[0] >= self.ntok:
            return
        seq_key = self.tok[i[0]]
        if not seq_key.startswith("::"):
            i[0] += 1
            return
        i[0] += 1
        if i[0] >= self.ntok or self.tok[i[0]] != "{":
            raise SemanticEngineError(5, "azl_semantic_engine: for-in missing {")
        body_start = i[0] + 1
        body_end = self.find_block_end(body_start)
        i[0] = body_end + 1
        raw = self.var_get(seq_key)
        if raw is None:
            raw = ""
        for seg in raw.split("\n") if raw else [""]:
            self.var_set(loop_var, seg[:MAX_VAR_VALUE_LEN])
            self.exec_block(
                body_start, body_end, preserve_listener_break_on_exit=True
            )
            if self._listener_break:
                break

    def _builtin_vm_compile_ast_apply(self, ast_s: str) -> None:
        """Sets ::vc.ok / ::vc.error / ::vc.bytecode per magic ast tags (gate F90–F92)."""
        self.var_set("::vc.ok", "false")
        self.var_set("::vc.error", "")
        self.var_set("::vc.bytecode", "")
        if ast_s == "F90_VM_OK":
            self.var_set("::vc.ok", "true")
            self.var_set("::vc.bytecode", "BC")
        elif ast_s == "F91_VM_BAD":
            self.var_set("::vc.ok", "false")
            self.var_set("::vc.error", "compile_failed")
        elif ast_s == "F92_VM_EMPTY":
            self.var_set("::vc.ok", "true")
            self.var_set("::vc.bytecode", "")
        else:
            self.var_set("::vc.ok", "false")
            self.var_set("::vc.error", "unknown_ast")

    @staticmethod
    def _vm_run_bytecode_result(bc: str) -> str:
        if not bc:
            return "vm_run_empty"
        if bc == "BC":
            return "P0_VM_EXEC_OK"
        return "vm_run:" + bc[:200]

    @staticmethod
    def _parse_execute_ast_with_tail(post: str) -> list[tuple[str, str]] | None:
        """Parse ``k|v|k2|v2`` tail after ``|with|`` (same rules as ``emit|`` row in ``execute_ast``)."""
        pairs: list[tuple[str, str]] = []
        r = post
        ok_parse = True
        while ok_parse and r:
            bar = r.find("|")
            if bar <= 0:
                ok_parse = False
                break
            pk = r[:bar]
            r = r[bar + 1 :]
            if not pk or not all(ch.isalnum() or ch == "_" for ch in pk):
                ok_parse = False
                break
            bar2 = r.find("|")
            if bar2 < 0:
                pairs.append((pk[:47], r[:255]))
                break
            pairs.append((pk[:47], r[:bar2][:255]))
            r = r[bar2 + 1 :]
        return pairs if (ok_parse and pairs) else None

    def _execute_ast_try_listen_stub(self, lrest: str) -> str | None:
        """Parse ``evt|say|…`` / ``evt|emit|…`` / ``evt|set|…`` tail after a ``listen|`` prefix; register execute_ast stub if valid."""
        bar = lrest.find("|")
        if bar <= 0:
            return None
        levn = lrest[:bar]
        ltail = lrest[bar + 1 :]
        stub: tuple[str, str, str, str] | None = None
        if levn and ltail.startswith("say|"):
            lpay = ltail[4:]
            if lpay:
                stub = (levn[:63], "say", lpay[:255], "")
        elif levn and ltail.startswith("emit|"):
            erest = ltail[5:]
            w = "|with|"
            wi = erest.find(w)
            if wi >= 0:
                inner = erest[:wi]
                ptail = erest[wi + len(w) :]
                if inner and "|" not in inner:
                    prs = self._parse_execute_ast_with_tail(ptail)
                    if prs:
                        stub = (levn[:63], "emit", inner[:63], ptail[:512])
            else:
                etarget = erest.split("|", 1)[0]
                if etarget and "|" not in erest:
                    stub = (levn[:63], "emit", etarget[:63], "")
        elif levn and ltail.startswith("set|"):
            srest = ltail[4:]
            sbar = srest.find("|")
            if sbar > 0:
                gkey = srest[:sbar]
                gval = srest[sbar + 1 :]
                if gkey.startswith("::"):
                    stub = (levn[:63], "set", gkey[:63], gval[:255])
        if stub is None:
            return None
        sev = stub[0]
        dup = any(e == sev for e, _, __, ___ in self._execute_ast_listen_stubs)
        if not dup and len(self._execute_ast_listen_stubs) < 8:
            self._execute_ast_listen_stubs.append(stub)
        return "Listen: " + levn[:120]

    def _execute_spine_component_v1(self, ast_base: str) -> str:
        """Bootstrap walk of ``spine_component_v1`` rows; phase order is fixed by azl_interpreter.azl ``execute_component`` (host must not reorder)."""
        self._execute_ast_listen_stubs.clear()
        spine = self.var_get(ast_base + ".spine") or ""
        lines_raw = spine.split("\n")
        if not lines_raw or lines_raw[0].strip() != "spine_component_v1":
            return "execute_spine_bad_header"
        bh: list[list[str]] = []
        ini: list[list[str]] = []
        mem: list[list[str]] = []
        for ln in lines_raw[1:]:
            ln = ln.strip()
            if not ln:
                continue
            parts = ln.split("\t")
            if not parts:
                continue
            tag = parts[0]
            if tag == "comp":
                continue
            if tag == "bh":
                bh.append(parts)
            elif tag == "in":
                ini.append(parts)
            elif tag == "mem":
                mem.append(parts)
            else:
                return "execute_spine_bad_line"
        if (self.var_get("::halted") or "") == "true":
            return "Execution halted due to error"
        saved_listener_count = len(self.listeners)
        try:
            return self._execute_spine_component_v1_body(bh, ini, mem)
        finally:
            while len(self.listeners) > saved_listener_count:
                self.listeners.pop()

    def _execute_spine_component_v1_body(
        self,
        bh: list[list[str]],
        ini: list[list[str]],
        mem: list[list[str]],
    ) -> str:
        out = "Execution completed"
        if (self.var_get("::halted") or "") == "true":
            return "Execution halted due to error"
        bh_toks: list[str] = []
        cur_ev: str | None = None
        for parts in bh:
            if len(parts) < 5 or parts[1] != "listen":
                return "execute_spine_bad_behavior"
            ev = parts[2][:63]
            op = parts[3]
            if cur_ev is not None and ev != cur_ev:
                if bh_toks:
                    self.register_listener(
                        cur_ev, 0, 0, synthetic_toks=bh_toks
                    )
                bh_toks = []
            cur_ev = ev
            if op == "say":
                if len(parts) < 5:
                    return "execute_spine_bad_behavior"
                bh_toks.extend(["say", parts[4][:220]])
            elif op == "set":
                if len(parts) < 6:
                    return "execute_spine_bad_behavior"
                vk = parts[4][:80]
                vv = parts[5][:MAX_VAR_VALUE_LEN]
                if not vk.startswith("::"):
                    return "execute_spine_bad_behavior"
                bh_toks.extend(["set", vk, "=", vv])
            elif op == "emit":
                if len(parts) >= 8 and parts[5] == "with":
                    inner_ev = parts[4][:63]
                    pk = parts[6][:47]
                    pv = parts[7][:120]
                    if not self._payload_key_ok(pk):
                        return "execute_spine_bad_behavior"
                    esc = self._quote_azl_single_from_inner(pv[:200])
                    bh_toks.extend(
                        ["emit", inner_ev, "with", "{", pk + ":", esc, "}"]
                    )
                elif len(parts) >= 5:
                    bh_toks.extend(["emit", parts[4][:63]])
                else:
                    return "execute_spine_bad_behavior"
            else:
                return "execute_spine_bad_behavior"
            out = "Listen: " + ev[:120]
        if cur_ev is not None and bh_toks:
            self.register_listener(
                cur_ev, 0, 0, synthetic_toks=bh_toks
            )
        for parts in ini:
            if (self.var_get("::halted") or "") == "true":
                return "Execution halted due to error"
            if len(parts) < 3:
                return "execute_spine_bad_init"
            op = parts[1]
            if op == "say":
                msg_tok = parts[2][:220]
                self._exec_with_tok_swap(["say", msg_tok], 0, 2)
                out = "Said: " + msg_tok[:200]
            elif op == "emit":
                ev = parts[2][:63]
                self._exec_with_tok_swap(["emit", ev], 0, 2)
                out = "Emitted: " + ev[:120]
            else:
                return "execute_spine_bad_init"
        for parts in mem:
            if (self.var_get("::halted") or "") == "true":
                return "Execution halted due to error"
            if len(parts) < 3:
                return "execute_spine_bad_memory"
            op = parts[1]
            if op == "say":
                msg_tok = parts[2][:220]
                self._exec_with_tok_swap(["say", msg_tok], 0, 2)
                out = "Said: " + msg_tok[:200]
            elif op == "set":
                if len(parts) < 4:
                    return "execute_spine_bad_memory"
                vk = parts[2][:80]
                vv = parts[3][:MAX_VAR_VALUE_LEN]
                if not vk.startswith("::"):
                    return "execute_spine_bad_memory"
                self._exec_with_tok_swap(["set", vk, "=", vv], 0, 4)
                out = "Set " + vk + " = " + vv[:150]
            else:
                return "execute_spine_bad_memory"
        return out

    def _builtin_execute_ast_run_lines(
        self, lines: list[str], fn_reg: dict[str, str], result: str
    ) -> str:
        """Walk pipe rows (nested under ``if|`` branches share ``fn_reg``). ``if|`` uses ``_execute_ast_if_condition_take_then``."""
        for line in lines:
            if (self.var_get("::halted") or "") == "true":
                return "Execution halted due to error"
            seg = line.lstrip(" \t")
            if not seg:
                continue
            if seg.startswith("import|") or seg.startswith("link|"):
                continue
            if seg.startswith("if|"):
                rest = seg[3:]
                try:
                    d = json.loads(rest)
                except json.JSONDecodeError:
                    continue
                c = d.get("c", "")
                raw_then = d.get("t")
                raw_else = d.get("f")
                then_lines = (
                    [str(x) for x in raw_then]
                    if isinstance(raw_then, list)
                    else []
                )
                else_lines = (
                    [str(x) for x in raw_else]
                    if isinstance(raw_else, list)
                    else []
                )
                take_then = self._execute_ast_if_condition_take_then(str(c))
                chosen = then_lines if take_then else else_lines
                result = self._builtin_execute_ast_run_lines(chosen, fn_reg, result)
                continue
            if seg.startswith("say|"):
                pay = seg[4:]
                print(pay, flush=True)
                result = "Said: " + pay[:200]
            elif seg.startswith("emit|"):
                rest = seg[5:]
                w = "|with|"
                wi = rest.find(w)
                if wi >= 0:
                    evn = rest[:wi]
                    post = rest[wi + len(w) :]
                    pairs = self._parse_execute_ast_with_tail(post)
                    if evn and pairs:
                        # Harness-only line; payload dispatch semantics live in azl_interpreter.azl ::emit_event_resolved.
                        if os.environ.get("AZL_SPINE_BEHAVIOR_SMOKE_PAYLOAD_MARK") == "1":
                            print("AZL_EMIT_WITH_PAYLOAD", flush=True)
                        self.queue_push(evn[:63], pairs)
                        self.process_events()
                        result = "Emitted: " + evn[:120]
                else:
                    evn = rest.split("|", 1)[0]
                    if evn:
                        self.queue_push(evn[:63], None)
                        self.process_events()
                        result = "Emitted: " + evn[:120]
            elif seg.startswith("set|"):
                rest = seg[4:]
                bar = rest.find("|")
                if bar > 0:
                    gkey = rest[:bar]
                    gval = rest[bar + 1 :]
                    if gkey.startswith("::"):
                        self.var_set(gkey, gval[:MAX_VAR_VALUE_LEN])
                        result = "Set " + gkey + " = " + gval[:150]
            elif seg.startswith("let|"):
                rest = seg[4:]
                bar = rest.find("|")
                if bar > 0:
                    gkey = rest[:bar]
                    gval = rest[bar + 1 :]
                    if gkey.startswith("::"):
                        self.var_set(gkey, gval[:MAX_VAR_VALUE_LEN])
                        result = "Let " + gkey + " = " + gval[:150]
            elif seg.startswith("component|"):
                ctail = seg[10:]
                if ctail:
                    self.run_linked_component(ctail)
                    result = "Component: " + ctail[:120]
            elif seg.startswith("memory|"):
                mrest = seg[7:]
                if mrest.startswith("set|"):
                    rest = mrest[4:]
                    bar = rest.find("|")
                    if bar > 0:
                        gkey = rest[:bar]
                        gval = rest[bar + 1 :]
                        if gkey.startswith("::"):
                            self.var_set(gkey, gval[:MAX_VAR_VALUE_LEN])
                            result = "Set " + gkey + " = " + gval[:150]
                elif mrest.startswith("say|"):
                    pay = mrest[4:]
                    print(pay, flush=True)
                    result = "Said: " + pay[:200]
                elif mrest.startswith("emit|"):
                    rest = mrest[5:]
                    w = "|with|"
                    wi = rest.find(w)
                    if wi >= 0:
                        evn = rest[:wi]
                        post = rest[wi + len(w) :]
                        pairs = self._parse_execute_ast_with_tail(post)
                        if evn and pairs:
                            # Harness-only; see top-level emit|with| branch.
                            if os.environ.get("AZL_SPINE_BEHAVIOR_SMOKE_PAYLOAD_MARK") == "1":
                                print("AZL_EMIT_WITH_PAYLOAD", flush=True)
                            self.queue_push(evn[:63], pairs)
                            self.process_events()
                            result = "Emitted: " + evn[:120]
                    else:
                        evn = rest.split("|", 1)[0]
                        if evn:
                            self.queue_push(evn[:63], None)
                            self.process_events()
                            result = "Emitted: " + evn[:120]
                elif mrest.startswith("listen|"):
                    lr = self._execute_ast_try_listen_stub(mrest[7:])
                    if lr is not None:
                        result = lr
            elif seg.startswith("listen|"):
                lr = self._execute_ast_try_listen_stub(seg[7:])
                if lr is not None:
                    result = lr
            elif seg.startswith("fn|"):
                rest = seg[3:]
                trip = rest.split("|", 2)
                if len(trip) == 3 and trip[1] == "say":
                    fn_reg[trip[0][:63]] = trip[2][:200]
                    result = "registered:" + trip[0][:120]
            elif seg.startswith("call|"):
                cname = seg[5:].split("|", 1)[0][:63]
                cpay = fn_reg.get(cname)
                if cpay is None:
                    result = "fn_not_found"
                else:
                    print(cpay, flush=True)
                    result = "called:" + cname[:120]
        return result

    def _builtin_execute_ast_result(self, ast_base: str) -> str:
        """Bootstrap walk of serialized ``::ast.nodes`` (same pipe contract as azl_interpreter.azl ``execute_ast``). F-gate indices: preloop import|/link| (F98, F112–F122); memory/listen/say/emit/set rows (F93–F148)."""
        em = (self.var_get(ast_base + ".exec_model") or "").strip()
        if em == "spine_component_v1":
            return self._execute_spine_component_v1(ast_base)[:255]
        nk = ast_base + ".nodes"
        raw = self.var_get(nk) or ""
        result = "Execution completed"
        if not raw.strip():
            return result
        self._execute_ast_listen_stubs.clear()
        fn_reg: dict[str, str] = {}
        lines = raw.split("\n")
        for line in lines:
            if (self.var_get("::halted") or "") == "true":
                return "Execution halted due to error"
            seg = line.lstrip(" \t")
            if not seg:
                continue
            if seg.startswith("import|"):
                tail = seg[7:]
                if tail:
                    self.var_set("::p0_exec_import_last", tail[:MAX_VAR_VALUE_LEN])
            elif seg.startswith("link|"):
                tail = seg[5:]
                if tail:
                    self.run_linked_component(tail)
        result = self._builtin_execute_ast_run_lines(lines, fn_reg, result)
        return result[:255]

    def exec_set(self, i: list[int]) -> None:
        i[0] += 1
        if i[0] >= self.ntok:
            return
        t0 = self.tok[i[0]]
        if not t0:
            return
        if t0.endswith(".push") and len(t0) > len(".push") + 2:
            base = t0[: -len(".push")]
            if not base.startswith("::"):
                raise SemanticEngineError(5, "azl_semantic_engine: .push bad base")
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != "(":
                raise SemanticEngineError(5, "azl_semantic_engine: .push missing (")
            i[0] += 1
            if i[0] >= self.ntok:
                raise SemanticEngineError(5, "azl_semantic_engine: .push missing arg")
            arg = self.tok[i[0]]
            if len(arg) >= 2 and arg[0] in "\"'":
                inner = arg[1:-1] if len(arg) >= 2 else ""
                seg = inner
                i[0] += 1
            elif arg == "{":
                seg = self._parse_push_tz_object(i)
            elif arg.startswith("::"):
                seg = self.var_get(arg) or ""
                i[0] += 1
            else:
                raise SemanticEngineError(5, "azl_semantic_engine: .push bad arg")
            if i[0] >= self.ntok or self.tok[i[0]] != ")":
                raise SemanticEngineError(5, "azl_semantic_engine: .push missing )")
            i[0] += 1
            cur = self.var_get(base) or ""
            if cur == "" or cur == "[]":
                joined = seg
            else:
                joined = cur + "\n" + seg
            self.var_set(base, joined)
            return
        if t0.startswith("::"):
            k = t0
        else:
            nb = self._normalize_bare_identifier_lhs(t0)
            if nb is None:
                i[0] += 1
                return
            k = nb
        i[0] += 1
        if i[0] >= self.ntok or self.tok[i[0]] != "=":
            return
        i[0] += 1
        if i[0] >= self.ntok:
            return
        v = self.tok[i[0]]
        concat_lhs = self._rhs_concat_base(v)
        if concat_lhs is not None:
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != "(":
                raise SemanticEngineError(5, "azl_semantic_engine: .concat missing (")
            i[0] += 1
            if i[0] >= self.ntok:
                raise SemanticEngineError(5, "azl_semantic_engine: .concat missing arg")
            carg = self.tok[i[0]]
            rgt: str
            if carg == "::tokenize_line":
                i[0] += 1
                if i[0] >= self.ntok or self.tok[i[0]] != "(":
                    raise SemanticEngineError(
                        5, "azl_semantic_engine: tokenize_line missing ("
                    )
                i[0] += 1
                if i[0] >= self.ntok or not self.tok[i[0]].startswith("::"):
                    raise SemanticEngineError(
                        5, "azl_semantic_engine: tokenize_line bad line_text"
                    )
                a1 = self.tok[i[0]]
                i[0] += 1
                if i[0] >= self.ntok or self.tok[i[0]] != ",":
                    raise SemanticEngineError(
                        5, "azl_semantic_engine: tokenize_line missing ,"
                    )
                i[0] += 1
                if i[0] >= self.ntok or not self.tok[i[0]].startswith("::"):
                    raise SemanticEngineError(
                        5, "azl_semantic_engine: tokenize_line bad line_no"
                    )
                a2 = self.tok[i[0]]
                i[0] += 1
                if i[0] >= self.ntok or self.tok[i[0]] != ")":
                    raise SemanticEngineError(
                        5, "azl_semantic_engine: tokenize_line missing )"
                    )
                i[0] += 1
                rgt = self._builtin_tokenize_line(
                    self.var_get(a1) or "", self.var_get(a2) or "1"
                )
            elif not carg.startswith("::"):
                raise SemanticEngineError(5, "azl_semantic_engine: .concat bad arg")
            else:
                i[0] += 1
                rgt = self.var_get(carg) or ""
            if i[0] >= self.ntok or self.tok[i[0]] != ")":
                raise SemanticEngineError(5, "azl_semantic_engine: .concat missing )")
            i[0] += 1
            lft = self.var_get(concat_lhs)
            lp = (
                ""
                if (lft is None or lft == "" or lft == "[]")
                else lft
            )
            rp = "" if (rgt == "" or rgt == "[]") else rgt
            if not lp:
                joined = rp
            elif not rp:
                joined = lp
            else:
                joined = lp + "\n" + rp
            self.var_set(k, joined)
            return
        if v == "[":
            self._consume_agg_literal(i)
            self.var_set(k, "[]")
            return
        if v == "{":
            self._consume_agg_literal(i)
            self.var_set(k, "{}")
            return
        if (
            v.startswith("::")
            and v.endswith(".split_chars")
            and len(v) > len(".split_chars") + 2
        ):
            base = v[: -len(".split_chars")]
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != "(":
                raise SemanticEngineError(
                    5, "azl_semantic_engine: .split_chars missing ("
                )
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != ")":
                raise SemanticEngineError(
                    5, "azl_semantic_engine: .split_chars missing )"
                )
            i[0] += 1
            src = self.var_get(base) or ""
            joined = "\n".join(tuple(src))
            self.var_set(k, joined)
            return
        if (
            v.startswith("::")
            and v.endswith(".split")
            and len(v) > len(".split") + 2
        ):
            base = v[: -len(".split")]
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != "(":
                raise SemanticEngineError(5, "azl_semantic_engine: .split missing (")
            i[0] += 1
            if i[0] >= self.ntok:
                raise SemanticEngineError(5, "azl_semantic_engine: .split missing literal")
            lit = self.tok[i[0]]
            delim = self._unescape_azl_string_token(lit)
            if delim == "":
                raise SemanticEngineError(5, "azl_semantic_engine: split delimiter empty")
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != ")":
                raise SemanticEngineError(5, "azl_semantic_engine: .split missing )")
            i[0] += 1
            src = self.var_get(base) or ""
            joined = "\n".join(src.split(delim))
            self.var_set(k, joined)
            return

        def _hash_blob(var_tok: str) -> str:
            if not var_tok.startswith("::"):
                raise SemanticEngineError(5, "azl_semantic_engine: hash_* bad arg")
            raw = (self.var_get(var_tok) or "").encode("utf-8", errors="replace")
            h = hashlib.sha256(raw).hexdigest()[:16]
            return h

        if v == "::hash_source":
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != "(":
                raise SemanticEngineError(5, "azl_semantic_engine: hash_source missing (")
            i[0] += 1
            if i[0] >= self.ntok:
                raise SemanticEngineError(5, "azl_semantic_engine: hash_source missing arg")
            arg = self.tok[i[0]]
            hx = _hash_blob(arg)
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != ")":
                raise SemanticEngineError(5, "azl_semantic_engine: hash_source missing )")
            i[0] += 1
            self.var_set(k, ("tok_" + hx)[:255])
            return
        if v == "::hash_tokens":
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != "(":
                raise SemanticEngineError(5, "azl_semantic_engine: hash_tokens missing (")
            i[0] += 1
            if i[0] >= self.ntok:
                raise SemanticEngineError(5, "azl_semantic_engine: hash_tokens missing arg")
            arg = self.tok[i[0]]
            hx = _hash_blob(arg)
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != ")":
                raise SemanticEngineError(5, "azl_semantic_engine: hash_tokens missing )")
            i[0] += 1
            self.var_set(k, ("ast_" + hx)[:255])
            return
        if v == "::parse_tokens":
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != "(":
                raise SemanticEngineError(5, "azl_semantic_engine: parse_tokens missing (")
            i[0] += 1
            if i[0] >= self.ntok:
                raise SemanticEngineError(5, "azl_semantic_engine: parse_tokens missing arg")
            arg = self.tok[i[0]]
            if not arg.startswith("::"):
                raise SemanticEngineError(5, "azl_semantic_engine: parse_tokens bad arg")
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != ")":
                raise SemanticEngineError(5, "azl_semantic_engine: parse_tokens missing )")
            i[0] += 1
            buf = self.var_get(arg) or ""
            pairs = self._parse_tz_buffer_pairs(buf)
            spine = self._try_parse_component_spine_v1_from_pairs(pairs)
            self.var_set("::ast", "{}")
            if spine is not None:
                self.var_set("::ast.exec_model", "spine_component_v1")
                self.var_set("::ast.spine", spine)
                self.var_set("::ast.nodes", "")
            else:
                self.var_set("::ast.exec_model", "")
                nodes_s = self._parse_tokens_nodes_from_buffer(buf)
                self.var_set("::ast.nodes", nodes_s)
            self.var_set(k, "{}")
            return
        if v == "::vm_compile_ast":
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != "(":
                raise SemanticEngineError(5, "azl_semantic_engine: vm_compile_ast missing (")
            i[0] += 1
            if i[0] >= self.ntok:
                raise SemanticEngineError(5, "azl_semantic_engine: vm_compile_ast missing arg")
            arg = self.tok[i[0]]
            if arg.startswith("::"):
                ast_s = self.var_get(arg) or ""
                i[0] += 1
            elif len(arg) >= 2 and arg[0] in "\"'":
                ast_s = self._unescape_azl_string_token(arg)
                i[0] += 1
            else:
                raise SemanticEngineError(5, "azl_semantic_engine: vm_compile_ast bad arg")
            if i[0] >= self.ntok or self.tok[i[0]] != ")":
                raise SemanticEngineError(5, "azl_semantic_engine: vm_compile_ast missing )")
            i[0] += 1
            self._builtin_vm_compile_ast_apply(ast_s)
            self.var_set(k, "vm_compile_done")
            return
        if v == "::vm_run_bytecode_program":
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != "(":
                raise SemanticEngineError(
                    5, "azl_semantic_engine: vm_run_bytecode_program missing ("
                )
            i[0] += 1
            if i[0] >= self.ntok:
                raise SemanticEngineError(
                    5, "azl_semantic_engine: vm_run_bytecode_program missing arg"
                )
            barg = self.tok[i[0]]
            if not barg.startswith("::"):
                raise SemanticEngineError(
                    5, "azl_semantic_engine: vm_run_bytecode_program bad arg"
                )
            bc = self.var_get(barg) or ""
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != ")":
                raise SemanticEngineError(
                    5, "azl_semantic_engine: vm_run_bytecode_program missing )"
                )
            i[0] += 1
            outv = self._vm_run_bytecode_result(bc)
            self.var_set(k, outv[:MAX_VAR_VALUE_LEN])
            return
        if v == "::execute_ast":
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != "(":
                raise SemanticEngineError(
                    5, "azl_semantic_engine: execute_ast missing ("
                )
            i[0] += 1
            if i[0] >= self.ntok:
                raise SemanticEngineError(
                    5, "azl_semantic_engine: execute_ast missing arg1"
                )
            a1 = self.tok[i[0]]
            if not a1.startswith("::"):
                raise SemanticEngineError(
                    5, "azl_semantic_engine: execute_ast bad arg1"
                )
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != ",":
                raise SemanticEngineError(
                    5, "azl_semantic_engine: execute_ast missing ,"
                )
            i[0] += 1
            if i[0] >= self.ntok:
                raise SemanticEngineError(
                    5, "azl_semantic_engine: execute_ast missing arg2"
                )
            a2 = self.tok[i[0]]
            if not a2.startswith("::"):
                raise SemanticEngineError(
                    5, "azl_semantic_engine: execute_ast bad arg2"
                )
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != ")":
                raise SemanticEngineError(
                    5, "azl_semantic_engine: execute_ast missing )"
                )
            i[0] += 1
            _ = a2
            outv = self._builtin_execute_ast_result(a1)
            self.var_set(k, outv[:MAX_VAR_VALUE_LEN])
            return
        if (
            v
            and (v[0].isalpha() or v[0] == "_")
            and all(ch.isalnum() or ch == "_" for ch in v)
            and not v.startswith("::")
            and v not in ("true", "false", "null")
        ):
            # Per azl_interpreter.azl: bare RHS is existing ``::name`` if bound (e.g. cache-hit token path); else literal.
            gk = "::" + v
            for bx in self.vars:
                if bx.k == gk:
                    self.var_set(k, bx.v)
                    i[0] += 1
                    return
            self.var_set(k, v[:MAX_VAR_VALUE_LEN])
            i[0] += 1
            return
        val = self.eval_expr(i)
        self.var_set(k, val)

    @staticmethod
    def _payload_key_ok(t: str) -> bool:
        if not t or t.startswith(":"):
            return False
        return all(c.isalnum() or c == "_" for c in t)

    def _parse_emit_with_payload(self, i: list[int]) -> list[tuple[str, str]]:
        out: list[tuple[str, str]] = []
        if i[0] >= self.ntok or self.tok[i[0]] != "with":
            return out
        i[0] += 1
        if i[0] >= self.ntok or self.tok[i[0]] != "{":
            return out
        i[0] += 1
        depth = 1
        while i[0] < self.ntok and depth > 0:
            t = self.tok[i[0]]
            if t == "{":
                depth += 1
                i[0] += 1
                continue
            if t == "}":
                depth -= 1
                i[0] += 1
                continue
            if depth != 1:
                i[0] += 1
                continue
            key: str | None = None
            if len(t) >= 2 and t.endswith(":") and self._payload_key_ok(t[:-1]):
                key = t[:-1]
                i[0] += 1
            elif self._payload_key_ok(t):
                key = t
                i[0] += 1
                if i[0] >= self.ntok or self.tok[i[0]] != ":":
                    continue
                i[0] += 1
            else:
                i[0] += 1
                continue
            if i[0] >= self.ntok:
                break
            valtok = self.tok[i[0]]
            if len(valtok) >= 2 and valtok[0] in "\"'":
                inner = valtok[1:-1] if len(valtok) >= 2 else ""
            elif valtok.startswith("::"):
                vv = self.var_get(valtok)
                inner = vv if vv is not None else ""
            else:
                inner = valtok
            i[0] += 1
            if key and len(out) < MAX_PAYLOAD_KEYS:
                cap = (
                    INTERP_BLOB_VAR_MAX
                    if key in ("tokens", "code", "ast")
                    else 255
                )
                out.append((key, inner[:cap]))
            if i[0] < self.ntok and self.tok[i[0]] == ",":
                i[0] += 1
        return out

    def exec_emit(self, i: list[int]) -> None:
        i[0] += 1
        if i[0] >= self.ntok:
            return
        s = self.tok[i[0]]
        ev = ""
        have = False
        if len(s) >= 2 and s[0] in "\"'":
            ev = s[1:-1] if len(s) >= 2 else ""
            have = True
        elif s:
            ev = s[:63]
            have = True
        i[0] += 1
        payload: list[tuple[str, str]] = []
        if have and i[0] < self.ntok and self.tok[i[0]] == "with":
            payload = self._parse_emit_with_payload(i)
        if have:
            self.queue_push(ev, payload)

    def exec_link(self, i: list[int]) -> None:
        i[0] += 1
        if i[0] >= self.ntok:
            return
        self.run_linked_component(self.tok[i[0]])
        i[0] += 1

    def run_linked_component(self, link_target: str | None) -> None:
        if not link_target:
            return
        lt = link_target[2:] if link_target.startswith("::") else link_target

        ci = 0
        while ci < self.ntok:
            if self.tok[ci] != "component":
                ci += 1
                continue
            j = ci + 1
            name_buf = ""
            while (
                j < self.ntok
                and self.tok[j]
                and self.tok[j] not in ("{", "init")
            ):
                name_buf += self.tok[j]
                j += 1
            nb = name_buf[2:] if name_buf.startswith("::") else name_buf
            if nb != lt:
                ci += 1
                continue

            if j >= self.ntok or self.tok[j] != "{":
                return
            comp_end = self.find_block_end(j + 1)
            k = j
            while k < comp_end and self.tok[k] != "behavior":
                k += 1
            if k < comp_end and self.tok[k] == "behavior":
                k += 1
                if k < comp_end and self.tok[k] == "{":
                    self.register_behavior_listeners(k + 1, self.find_block_end(k + 1))
            k = j
            while k < comp_end and self.tok[k] != "init":
                k += 1
            if k < comp_end and self.tok[k] == "init":
                k += 1
                while k < comp_end and self.tok[k] != "{":
                    k += 1
                if k < comp_end:
                    k += 1
                    ki = [k]
                    self.exec_init_block(ki)
            if lt == "azl.interpreter":
                # Init stores aggregate `{ … }` as "{}"; keep perf counters addressable like dotted globals.
                for sub in ("tok_hits", "tok_misses", "ast_hits", "ast_misses"):
                    pk = f"::perf.stats.{sub}"
                    if self.var_get(pk) is None:
                        self.var_set(pk, "0")
            return

        sys.stderr.write(f"azl_semantic_engine: link: component not found: {link_target}\n")
        sys.stderr.flush()

    def register_behavior_listeners(self, start: int, end: int) -> None:
        i = start
        while i < end and i < self.ntok:
            if (
                self.tok[i] == "listen"
                and i + 2 < self.ntok
                and self.tok[i + 1] == "for"
            ):
                i += 2
                ev = self.tok[i]
                if ev and len(ev) >= 2 and ev[0] in "\"'":
                    evname = ev[1:-1] if len(ev) >= 2 else ""
                    i += 1
                    if i < self.ntok and self.tok[i] == "then":
                        i += 1
                    if i < self.ntok and self.tok[i] == "{":
                        block_start = i + 1
                        d = 1
                        i += 1
                        while i < self.ntok and d > 0:
                            if self.tok[i] == "{":
                                d += 1
                            elif self.tok[i] == "}":
                                d -= 1
                            i += 1
                        i -= 1
                        self.register_listener(evname, block_start, i)
            i += 1

    def exec_listen(self, i: list[int]) -> None:
        """Dynamic listen for "ev" [then] { ... } inside init or listener bodies."""
        if i[0] >= self.ntok or self.tok[i[0]] != "listen":
            return
        if i[0] + 2 >= self.ntok or self.tok[i[0] + 1] != "for":
            i[0] += 1
            return
        i[0] += 2
        ev = self.tok[i[0]]
        if not ev or len(ev) < 2 or ev[0] not in "\"'":
            if i[0] < self.ntok:
                i[0] += 1
            return
        evname = ev[1:-1] if len(ev) >= 2 else ""
        i[0] += 1
        if i[0] < self.ntok and self.tok[i[0]] == "then":
            i[0] += 1
        if i[0] < self.ntok and self.tok[i[0]] == "{":
            block_start = i[0] + 1
            d = 1
            i[0] += 1
            while i[0] < self.ntok and d > 0:
                if self.tok[i[0]] == "{":
                    d += 1
                elif self.tok[i[0]] == "}":
                    d -= 1
                i[0] += 1
            i[0] -= 1
            self.register_listener(evname, block_start, i[0])
            i[0] += 1

    def exec_block(
        self,
        start: int,
        end: int,
        *,
        preserve_listener_break_on_exit: bool = False,
    ) -> None:
        self._listener_nesting += 1
        self._listener_break = False
        try:
            depth = 1
            i = start
            while i < end and i < self.ntok:
                t = self.tok[i]
                if t == "{":
                    depth += 1
                    i += 1
                elif t == "}":
                    depth -= 1
                    if depth <= 0:
                        break
                    i += 1
                elif depth == 1 and t == "return":
                    i += 1
                    self._listener_break = True
                    break
                elif depth == 1 and t == "say":
                    ii = [i]
                    self.exec_say(ii)
                    i = ii[0]
                elif depth == 1 and t == "set":
                    ii = [i]
                    self.exec_set(ii)
                    i = ii[0]
                elif depth == 1 and t == "emit":
                    ii = [i]
                    self.exec_emit(ii)
                    i = ii[0]
                    self.process_events()
                elif depth == 1 and t == "link":
                    ii = [i]
                    self.exec_link(ii)
                    i = ii[0]
                elif depth == 1 and t == "if":
                    ii = [i]
                    self.exec_if(ii)
                    i = ii[0]
                    if self._listener_break:
                        break
                elif depth == 1 and t == "for":
                    ii = [i]
                    self.exec_for_in(ii)
                    i = ii[0]
                    if self._listener_break:
                        break
                elif depth == 1 and t == "listen":
                    ii = [i]
                    self.exec_listen(ii)
                    i = ii[0]
                elif (
                    depth == 1
                    and t.startswith("::")
                    and i + 1 < self.ntok
                    and self.tok[i + 1] == "("
                ):
                    ii = [i]
                    if self._try_spine_interpreter_builtin_statement(ii):
                        i = ii[0]
                    else:
                        raise SemanticEngineError(
                            5,
                            f"azl_semantic_engine: unsupported spine call {t!r}",
                        )
                else:
                    i += 1
        finally:
            self._listener_nesting -= 1
            if not preserve_listener_break_on_exit:
                self._listener_break = False

    def process_events(self) -> None:
        while True:
            popped = self.queue_pop()
            if popped is None:
                break
            ev, payload = popped
            for pk, pv in payload:
                self.var_set(f"::event.data.{pk}", pv)
            matched = False
            for j, ln in enumerate(self.listeners):
                if ln.event == ev:
                    if ln.synthetic_toks is not None:
                        self._exec_with_tok_swap(
                            ln.synthetic_toks, 0, len(ln.synthetic_toks)
                        )
                    else:
                        self.exec_block(ln.block_start, ln.block_end)
                    matched = True
                    break
            if not matched:
                for sev, skind, sa1, sa2 in self._execute_ast_listen_stubs:
                    if sev == ev:
                        if skind == "emit":
                            if sa2:
                                prs = self._parse_execute_ast_with_tail(sa2)
                                if prs:
                                    self.queue_push(sa1[:63], prs)
                                else:
                                    self.queue_push(sa1[:63], None)
                            else:
                                self.queue_push(sa1[:63], None)
                            self.process_events()
                        elif skind == "set":
                            if sa1.startswith("::"):
                                self.var_set(sa1, sa2[:MAX_VAR_VALUE_LEN])
                        else:
                            print(sa1, flush=True)
                        break
            for pk, _ in payload:
                self.var_set(f"::event.data.{pk}", "")

    def exec_init_block(self, i: list[int]) -> None:
        depth = 1
        while i[0] < self.ntok:
            t = self.tok[i[0]]
            if t == "{":
                depth += 1
                i[0] += 1
            elif t == "}":
                depth -= 1
                if depth <= 0:
                    break
                i[0] += 1
            elif depth == 1 and t == "return":
                i[0] += 1
                d = 1
                while i[0] < self.ntok and d > 0:
                    t2 = self.tok[i[0]]
                    if t2 == "{":
                        d += 1
                        i[0] += 1
                    elif t2 == "}":
                        d -= 1
                        if d == 0:
                            break
                        i[0] += 1
                    else:
                        i[0] += 1
                if self._listener_nesting > 0:
                    self._listener_break = True
                return
            elif depth == 1 and t == "say":
                self.exec_say(i)
            elif depth == 1 and t == "set":
                self.exec_set(i)
            elif depth == 1 and t == "emit":
                self.exec_emit(i)
                self.process_events()
            elif depth == 1 and t == "link":
                self.exec_link(i)
            elif depth == 1 and t == "if":
                self.exec_if(i)
            elif depth == 1 and t == "for":
                if self._listener_nesting > 0:
                    self.exec_for_in(i)
                else:
                    raise SemanticEngineError(
                        5, "azl_semantic_engine: for-in not allowed in init"
                    )
            elif depth == 1 and t == "listen":
                self.exec_listen(i)
            else:
                i[0] += 1

    def run(self, entry: str | None) -> int:
        if entry and entry.startswith("::"):
            entry = entry[2:]

        i = 0
        while i < self.ntok:
            if self.tok[i] == "component" and i + 1 < self.ntok:
                j = i + 1
                name_buf = ""
                while (
                    j < self.ntok
                    and self.tok[j]
                    and self.tok[j] not in ("{", "init")
                ):
                    name_buf += self.tok[j]
                    j += 1
                matches = (not entry) or (
                    bool(name_buf) and entry is not None and entry in name_buf
                )
                if matches:
                    if j >= self.ntok or self.tok[j] != "{":
                        return 0
                    comp_end = self.find_block_end(j + 1)
                    ii = j
                    while ii < comp_end and self.tok[ii] != "behavior":
                        ii += 1
                    if ii < comp_end and self.tok[ii] == "behavior":
                        ii += 1
                        if ii < comp_end and self.tok[ii] == "{":
                            bh_start = ii + 1
                            bh_end = self.find_block_end(ii + 1)
                            self.register_behavior_listeners(bh_start, bh_end)
                    ii = j
                    while ii < comp_end and self.tok[ii] != "init":
                        ii += 1
                    if ii < comp_end and self.tok[ii] == "init":
                        ii += 1
                        while ii < comp_end and self.tok[ii] != "{":
                            ii += 1
                        if ii < comp_end:
                            ii += 1
                            ki = [ii]
                            self.exec_init_block(ki)
                    self.process_events()
                    return 0
            i += 1

        i = 0
        while i < self.ntok:
            if self.tok[i] != "component" or i + 1 >= self.ntok:
                i += 1
                continue
            j = i + 1
            nb = ""
            while (
                j < self.ntok
                and self.tok[j]
                and self.tok[j] not in ("{", "init")
            ):
                nb += self.tok[j]
                j += 1
            if j >= self.ntok or self.tok[j] != "{":
                i += 1
                continue
            comp_end = self.find_block_end(j + 1)
            jj = j
            while jj < comp_end and self.tok[jj] != "behavior":
                jj += 1
            if jj < comp_end and self.tok[jj] == "behavior":
                jj += 1
                if jj < comp_end and self.tok[jj] == "{":
                    self.register_behavior_listeners(
                        jj + 1, self.find_block_end(jj + 1)
                    )
            jj = j
            while jj < comp_end and self.tok[jj] != "init":
                jj += 1
            if jj < comp_end and self.tok[jj] == "init":
                jj += 1
                while jj < comp_end and self.tok[jj] != "{":
                    jj += 1
                if jj < comp_end:
                    jj += 1
                    ki = [jj]
                    self.exec_init_block(ki)
            self.process_events()
            return 0

        return 0


def run_file(path: str, entry: str | None, *, daemon: bool = False) -> int:
    try:
        rt = MinimalAZLRuntime.from_file(path)
    except SemanticEngineError as e:
        sys.stderr.write(f"{e.message}\n")
        return e.code
    try:
        rc = rt.run(entry)
    except SemanticEngineError as e:
        sys.stderr.write(f"{e.message}\n")
        sys.stderr.flush()
        return e.code
    if rc != 0:
        return rc
    if daemon:
        import time

        while True:
            time.sleep(1)
    return 0
