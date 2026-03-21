"""
Faithful port of tools/azl_interpreter_minimal.c token stream + execution semantics.
Single source of behavioral truth: keep in sync with C when changing the minimal contract.

Nested ``listen`` may run inside ``init`` / listener bodies; ``emit`` inside ``exec_block``
drains the event queue (``process_events``) so chained handlers match the interpret→tokenize shape.
Each queued event may carry a ``with { … }`` payload bound as ``::event.data.<key>`` for that dispatch
(F10–F87 parity fixtures under ``azl/tests/p0_semantic_*.azl``). ``return`` at listener depth exits the
current listener body (including from inside ``if { … }``); ``return`` in top-level ``init`` skips the rest of ``init``.
``set ::dst = ::src.split("delim")`` stores split segments joined by newlines; ``for ::v in ::dst { … }`` (listener
bodies only) iterates those segments — matches the ``::code.split("\\n")`` + line loop shape in ``azl_interpreter.azl``.
``::var.length`` in expressions yields the string length as a decimal string (unset base → ``0``).
``set ::dst = ::src.split_chars()`` stores Unicode code points of ``::src`` joined by newlines (``for ::c in ::dst`` matches ``for ::char in ::line_text`` in ``azl_interpreter.azl``).
``set ::buf.push("literal")`` / ``::var`` / ``{ type: "…", value: "…" | ::var, line: N | ::var, column: M | ::var }`` appends one newline-delimited segment (object rows serialize as ``tz|…|…|…|…`` with ``\\|`` / ``\\\\`` escapes). ``set ::acc = ::lhs.concat(::rhs)`` joins two buffers with newline (``[]`` / empty same as ``for ::row in``).
Double-quoted ``say "…"`` expands ``::dotted.path`` and ``::dotted.path.length`` (same ``.length`` rule as expressions: byte length of stored value; unset → ``0``). Single-quoted ``say '…'`` stays literal.
Binary ``-`` in expressions is supported only when both operands are canonical base-10 integers (``::column - ::name.length`` tokenize-line shape); otherwise use ``+`` string/int rules.
"""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass, field

BUF_SIZE = 2 * 1024 * 1024
MAX_TOKS = 65536
MAX_VARS = 256
MAX_LISTENERS = 64
MAX_EVENTS = 32
MAX_PAYLOAD_KEYS = 8


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

    def var_set(self, k: str, v: str) -> None:
        for i, x in enumerate(self.vars):
            if x.k == k:
                self.vars[i] = Var(k=k, v=v[:255])
                return
        if len(self.vars) < MAX_VARS:
            self.vars.append(Var(k=k[:63], v=v[:255]))

    def queue_push(self, ev: str, payload: list[tuple[str, str]] | None = None) -> None:
        if len(self.queue) >= MAX_EVENTS:
            return
        pl = [(k[:47], v[:255]) for k, v in (payload or [])][:MAX_PAYLOAD_KEYS]
        self.queue.append((ev[:63], pl))

    def queue_pop(self) -> tuple[str, list[tuple[str, str]]] | None:
        if not self.queue:
            return None
        return self.queue.pop(0)

    def register_listener(self, ev: str, block_start: int, block_end: int) -> None:
        if len(self.listeners) < MAX_LISTENERS:
            self.listeners.append(
                Listener(event=ev[:63], block_start=block_start, block_end=block_end)
            )

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
            inner = t[1:-1] if len(t) >= 2 else ""
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

    def _eval_or(self, i: list[int]) -> str:
        acc, acc_nullish = self._eval_eq(i)
        while i[0] < self.ntok and self.tok[i[0]] == "or":
            i[0] += 1
            nxt, nn = self._eval_eq(i)
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
        if self._cond_is_true(cond):
            i[0] += 1
            self.exec_init_block(i)
            if i[0] < self.ntok and self.tok[i[0]] == "}":
                i[0] += 1
        else:
            self._skip_braced_block(i)

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
            self.var_set(loop_var, seg[:255])
            self.exec_block(
                body_start, body_end, preserve_listener_break_on_exit=True
            )
            if self._listener_break:
                break

    def exec_set(self, i: list[int]) -> None:
        i[0] += 1
        if i[0] >= self.ntok:
            return
        t0 = self.tok[i[0]]
        if not t0 or not t0.startswith("::"):
            i[0] += 1
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
            self.var_set(base, joined[:255])
            return
        k = t0
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
            if not carg.startswith("::"):
                raise SemanticEngineError(5, "azl_semantic_engine: .concat bad arg")
            i[0] += 1
            if i[0] >= self.ntok or self.tok[i[0]] != ")":
                raise SemanticEngineError(5, "azl_semantic_engine: .concat missing )")
            i[0] += 1
            lft = self.var_get(concat_lhs)
            rgt = self.var_get(carg) or ""
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
            self.var_set(k, joined[:255])
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
            self.var_set(k, joined[:255])
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
            self.var_set(k, joined[:255])
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
                out.append((key, inner[:255]))
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
            for j, ln in enumerate(self.listeners):
                if ln.event == ev:
                    self.exec_block(ln.block_start, ln.block_end)
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
