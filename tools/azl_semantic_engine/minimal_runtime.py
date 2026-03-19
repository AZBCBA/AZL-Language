"""
Faithful port of tools/azl_interpreter_minimal.c token stream + execution semantics.
Single source of behavioral truth: keep in sync with C when changing the minimal contract.
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
        if ch in "{}();=,[]!":
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
    queue: list[str] = field(default_factory=list)

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

    def queue_push(self, ev: str) -> None:
        if len(self.queue) >= MAX_EVENTS:
            return
        self.queue.append(ev[:63])

    def queue_pop(self) -> str | None:
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

    def exec_say(self, i: list[int]) -> None:
        i[0] += 1
        if i[0] >= self.ntok:
            return
        s = self.tok[i[0]]
        if len(s) >= 2 and s[0] in "\"'":
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
            vv = self.var_get(t)
            i[0] += 1
            if vv is None:
                return "", 1
            return vv, 0
        raise SemanticEngineError(5, f"azl_semantic_engine: bad primary {t!r}")

    def _eval_eq(self, i: list[int]) -> tuple[str, int]:
        left, ln = self._eval_primary(i)
        if i[0] >= self.ntok or self.tok[i[0]] not in ("==", "!="):
            return left, ln
        op = self.tok[i[0]]
        i[0] += 1
        right, rn = self._eval_primary(i)
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

    def exec_set(self, i: list[int]) -> None:
        i[0] += 1
        if i[0] >= self.ntok:
            return
        k = self.tok[i[0]]
        if not k or not k.startswith("::"):
            i[0] += 1
            return
        i[0] += 1
        if i[0] >= self.ntok or self.tok[i[0]] != "=":
            return
        i[0] += 1
        if i[0] >= self.ntok:
            return
        v = self.tok[i[0]]
        if v == "[":
            self._consume_agg_literal(i)
            self.var_set(k, "[]")
            return
        if v == "{":
            self._consume_agg_literal(i)
            self.var_set(k, "{}")
            return
        val = self.eval_expr(i)
        self.var_set(k, val)

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
        if have:
            self.queue_push(ev)
        i[0] += 1
        if i[0] < self.ntok and self.tok[i[0]] == "with":
            i[0] += 1
            if i[0] < self.ntok and self.tok[i[0]] == "{":
                d = 1
                i[0] += 1
                while i[0] < self.ntok and d > 0:
                    if self.tok[i[0]] == "{":
                        d += 1
                    elif self.tok[i[0]] == "}":
                        d -= 1
                    i[0] += 1

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

    def exec_block(self, start: int, end: int) -> None:
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
            elif depth == 1 and t == "link":
                ii = [i]
                self.exec_link(ii)
                i = ii[0]
            elif depth == 1 and t == "if":
                ii = [i]
                self.exec_if(ii)
                i = ii[0]
            else:
                i += 1

    def process_events(self) -> None:
        while True:
            ev = self.queue_pop()
            if ev is None:
                break
            for j, ln in enumerate(self.listeners):
                if ln.event == ev:
                    self.exec_block(ln.block_start, ln.block_end)
                    break

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
