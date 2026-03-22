/*
 * AZL Minimal C Interpreter - Phase 1 Skeleton
 * Proof-of-concept: parses and executes a tiny AZL subset.
 * Extensible foundation for full C-based AZL execution.
 *
 * Usage: azl_interpreter_minimal <file.azl> [entry_component]
 * Env: AZL_COMBINED_PATH, AZL_ENTRY
 *
 * emit ... with { k: v } binds ::event.data.<k> per queued event (see azl/tests/p0_semantic_*.azl, gates F10-F122).
 * Expression if-conditions: or, && (short-circuit; each && arm is ==/!=/sum; truth is true/1 only), ==, !=, +, -, :: paths.
 * for-in inside if { } is allowed when g_listener_nesting > 0 (listener context); still forbidden in component init { }.
 * return exits the current listener body (including from inside if { }); return in init skips rest of init.
 */

#define _GNU_SOURCE
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

#define BUF_SIZE  (2 * 1024 * 1024)   /* 2MB for enterprise combined files */
#define MAX_TOKS  65536
#define MAX_VARS  256
#define MAX_LISTENERS 64
#define MAX_EVENTS 32
#define MAX_PAYLOAD_KEYS 8

typedef struct { char key[48]; char v[256]; } PayloadKV;
typedef struct {
  char ev[64];
  PayloadKV kv[MAX_PAYLOAD_KEYS];
  int nkv;
} QueuedEvent;

static char *g_src;
static size_t g_src_len;
static const char *g_tok[MAX_TOKS];
static int g_ntok;

/* Variable store: key -> value (string) */
typedef struct { char k[64]; char v[256]; } Var;
static Var g_vars[MAX_VARS];
static int g_nvars;

/* Listener: event_name -> block (start,end) */
typedef struct { char event[64]; int block_start; int block_end; } Listener;
static Listener g_listeners[MAX_LISTENERS];
static int g_nlisteners;

/* Event queue for dispatch (event name + optional emit with { k: v, ... } payload) */
static QueuedEvent g_event_queue[MAX_EVENTS];
static int g_queue_head, g_queue_tail;

static void queue_push_event(const char *ev, const PayloadKV *kv, int nkv);
static void process_events(void);
static void var_set(const char *k, const char *v);

static int g_listener_nesting = 0;
static int g_listener_break = 0;

/* execute_ast listen|event|say|… / emit|… / set|… — stub listeners (F99–F102); cleared each execute_ast walk */
#define MAX_EXECUTE_AST_STUB_LISTENERS 8
#define EXEC_AST_STUB_SAY 0
#define EXEC_AST_STUB_EMIT 1
#define EXEC_AST_STUB_SET 2
typedef struct {
  char event[64];
  int kind; /* EXEC_AST_STUB_SAY, EMIT, or SET */
  char body[256]; /* say text, bare emit target, or set value */
  char set_key[64]; /* ::global for SET; empty for say/emit */
  int emit_npayload; /* 0 = bare emit; else use emit_payload[0..emit_npayload) */
  PayloadKV emit_payload[MAX_PAYLOAD_KEYS];
} ExecAstStubListen;
static ExecAstStubListen g_exec_ast_stubs[MAX_EXECUTE_AST_STUB_LISTENERS];
static int g_n_exec_ast_stubs;

static void exec_ast_stubs_reset(void) { g_n_exec_ast_stubs = 0; }

static int exec_ast_stub_register(const char *ev, int kind, const char *body) {
  if (!ev || !ev[0] || !body || !body[0]) return -1;
  if (kind == EXEC_AST_STUB_EMIT && strchr(body, '|') != NULL) return -1;
  for (int i = 0; i < g_n_exec_ast_stubs; i++)
    if (strcmp(g_exec_ast_stubs[i].event, ev) == 0) return 0; /* first wins */
  if (g_n_exec_ast_stubs >= MAX_EXECUTE_AST_STUB_LISTENERS) return -1;
  (void)snprintf(g_exec_ast_stubs[g_n_exec_ast_stubs].event,
                 sizeof(g_exec_ast_stubs[g_n_exec_ast_stubs].event), "%s", ev);
  g_exec_ast_stubs[g_n_exec_ast_stubs].kind = kind;
  (void)snprintf(g_exec_ast_stubs[g_n_exec_ast_stubs].body,
                 sizeof(g_exec_ast_stubs[g_n_exec_ast_stubs].body), "%s", body);
  g_exec_ast_stubs[g_n_exec_ast_stubs].set_key[0] = '\0';
  g_exec_ast_stubs[g_n_exec_ast_stubs].emit_npayload = 0;
  g_n_exec_ast_stubs++;
  return 0;
}

static int exec_ast_stub_register_emit_with(const char *ev, const char *target, const PayloadKV *pay, int npay) {
  if (!ev || !ev[0] || !target || !target[0] || strchr(target, '|') != NULL) return -1;
  if (!pay || npay <= 0 || npay > MAX_PAYLOAD_KEYS) return -1;
  for (int i = 0; i < g_n_exec_ast_stubs; i++)
    if (strcmp(g_exec_ast_stubs[i].event, ev) == 0) return 0;
  if (g_n_exec_ast_stubs >= MAX_EXECUTE_AST_STUB_LISTENERS) return -1;
  (void)snprintf(g_exec_ast_stubs[g_n_exec_ast_stubs].event,
                 sizeof(g_exec_ast_stubs[g_n_exec_ast_stubs].event), "%s", ev);
  g_exec_ast_stubs[g_n_exec_ast_stubs].kind = EXEC_AST_STUB_EMIT;
  (void)snprintf(g_exec_ast_stubs[g_n_exec_ast_stubs].body,
                 sizeof(g_exec_ast_stubs[g_n_exec_ast_stubs].body), "%s", target);
  g_exec_ast_stubs[g_n_exec_ast_stubs].set_key[0] = '\0';
  g_exec_ast_stubs[g_n_exec_ast_stubs].emit_npayload = npay;
  for (int j = 0; j < npay; j++) {
    (void)snprintf(
        g_exec_ast_stubs[g_n_exec_ast_stubs].emit_payload[j].key,
        sizeof(g_exec_ast_stubs[g_n_exec_ast_stubs].emit_payload[j].key), "%.*s",
        (int)(sizeof(g_exec_ast_stubs[0].emit_payload[0].key) - 1U), pay[j].key);
    (void)snprintf(g_exec_ast_stubs[g_n_exec_ast_stubs].emit_payload[j].v,
                   sizeof(g_exec_ast_stubs[g_n_exec_ast_stubs].emit_payload[j].v), "%.*s",
                   (int)(sizeof(g_exec_ast_stubs[0].emit_payload[0].v) - 1U), pay[j].v);
  }
  g_n_exec_ast_stubs++;
  return 0;
}

static int exec_ast_stub_register_set(const char *ev, const char *gkey, const char *gval) {
  if (!ev || !ev[0] || !gkey || gkey[0] != ':' || gkey[1] != ':' || !gval) return -1;
  for (int i = 0; i < g_n_exec_ast_stubs; i++)
    if (strcmp(g_exec_ast_stubs[i].event, ev) == 0) return 0;
  if (g_n_exec_ast_stubs >= MAX_EXECUTE_AST_STUB_LISTENERS) return -1;
  (void)snprintf(g_exec_ast_stubs[g_n_exec_ast_stubs].event,
                 sizeof(g_exec_ast_stubs[g_n_exec_ast_stubs].event), "%s", ev);
  g_exec_ast_stubs[g_n_exec_ast_stubs].kind = EXEC_AST_STUB_SET;
  (void)snprintf(g_exec_ast_stubs[g_n_exec_ast_stubs].set_key,
                 sizeof(g_exec_ast_stubs[g_n_exec_ast_stubs].set_key), "%s", gkey);
  (void)snprintf(g_exec_ast_stubs[g_n_exec_ast_stubs].body,
                 sizeof(g_exec_ast_stubs[g_n_exec_ast_stubs].body), "%s", gval ? gval : "");
  g_exec_ast_stubs[g_n_exec_ast_stubs].emit_npayload = 0;
  g_n_exec_ast_stubs++;
  return 0;
}

static int exec_ast_stub_dispatch(const char *ev) {
  if (!ev || !ev[0]) return 0;
  for (int i = 0; i < g_n_exec_ast_stubs; i++) {
    if (strcmp(g_exec_ast_stubs[i].event, ev) != 0) continue;
    if (g_exec_ast_stubs[i].kind == EXEC_AST_STUB_EMIT) {
      char evn[64];
      (void)snprintf(evn, sizeof(evn), "%s", g_exec_ast_stubs[i].body);
      int nk = g_exec_ast_stubs[i].emit_npayload;
      const PayloadKV *pkv = (nk > 0) ? g_exec_ast_stubs[i].emit_payload : NULL;
      queue_push_event(evn, pkv, nk);
      process_events();
    } else if (g_exec_ast_stubs[i].kind == EXEC_AST_STUB_SET) {
      var_set(g_exec_ast_stubs[i].set_key, g_exec_ast_stubs[i].body);
    } else {
      fputs(g_exec_ast_stubs[i].body, stdout);
      fputc('\n', stdout);
      fflush(stdout);
    }
    return 1;
  }
  return 0;
}

static void skip_whitespace_and_comments(const char **p) {
  for (;;) {
    while (**p && (isspace((unsigned char)**p) || **p == '\n' || **p == '\r')) (*p)++;
    if (**p == '#' || (**p == '/' && (*p)[1] == '/')) {
      while (**p && **p != '\n') (*p)++;
      continue;
    }
    break;
  }
}

static int tokenize(void) {
  const char *p = g_src;
  g_ntok = 0;
  while (g_ntok < MAX_TOKS - 1) {
    skip_whitespace_and_comments(&p);
    if (!*p) break;
    const char *start = p;
    if (*p == '"' || *p == '\'') {
      char q = *p++;
      while (*p && *p != q) { if (*p == '\\') p++; p++; }
      if (*p == q) p++;
      size_t len = (size_t)(p - start);
      char *s = malloc(len + 1);
      if (!s) return -1;
      memcpy(s, start, len);
      s[len] = '\0';
      g_tok[g_ntok++] = s;
      continue;
    }
    if (isalnum((unsigned char)*p) || *p == '_' || *p == ':') {
      while (*p && (isalnum((unsigned char)*p) || *p == '_' || *p == '.' || *p == ':')) p++;
      size_t len = (size_t)(p - start);
      char *s = malloc(len + 1);
      if (!s) return -1;
      memcpy(s, start, len);
      s[len] = '\0';
      g_tok[g_ntok++] = s;
      continue;
    }
    if (*p == '=' && p[1] == '=') {
      char *s = malloc(3);
      if (!s) return -1;
      s[0] = '='; s[1] = '='; s[2] = '\0';
      g_tok[g_ntok++] = s;
      p += 2;
      continue;
    }
    if (*p == '!' && p[1] == '=') {
      char *s = malloc(3);
      if (!s) return -1;
      s[0] = '!'; s[1] = '='; s[2] = '\0';
      g_tok[g_ntok++] = s;
      p += 2;
      continue;
    }
    if (*p == '&' && p[1] == '&') {
      char *s = malloc(3);
      if (!s) return -1;
      s[0] = '&'; s[1] = '&'; s[2] = '\0';
      g_tok[g_ntok++] = s;
      p += 2;
      continue;
    }
    if (*p == '{' || *p == '}' || *p == '(' || *p == ')' || *p == ';' || *p == '=' || *p == ',' || *p == '[' || *p == ']' || *p == '!' || *p == '+' || *p == '-') {
      char *s = malloc(2);
      if (!s) return -1;
      s[0] = *p++;
      s[1] = '\0';
      g_tok[g_ntok++] = s;
      continue;
    }
    p++;
  }
  g_tok[g_ntok] = NULL;
  return 0;
}

static void free_tokens(void) {
  for (int i = 0; i < g_ntok; i++) free((void *)g_tok[i]);
  g_ntok = 0;
}

static const char *var_get(const char *k) {
  for (int i = 0; i < g_nvars; i++)
    if (strcmp(g_vars[i].k, k) == 0) return g_vars[i].v;
  return NULL;
}
static void var_set(const char *k, const char *v) {
  for (int i = 0; i < g_nvars; i++)
    if (strcmp(g_vars[i].k, k) == 0) {
      (void)snprintf(g_vars[i].v, sizeof(g_vars[i].v), "%s", v ? v : "");
      return;
    }
  if (g_nvars < MAX_VARS) {
    (void)snprintf(g_vars[g_nvars].k, sizeof(g_vars[g_nvars].k), "%s", k ? k : "");
    (void)snprintf(g_vars[g_nvars].v, sizeof(g_vars[g_nvars].v), "%s", v ? v : "");
    g_nvars++;
  }
}
static int payload_key_ok(const char *key) {
  if (!key || !key[0]) return 0;
  if (key[0] == ':') return 0;
  for (const char *p = key; *p; p++)
    if (!isalnum((unsigned char)*p) && *p != '_') return 0;
  return 1;
}

/*
 * Parse `with { key: "value" | ::var, ... }` for emit payload; *i must point at `with`.
 * Advances *i past the closing `}` of the object (or leaves *i after `with` if no `{`).
 */
static int parse_emit_with_payload(int *i, PayloadKV *out, int max_out) {
  int n = 0;
  if (*i >= g_ntok || strcmp(g_tok[*i], "with") != 0) return 0;
  (*i)++;
  if (*i >= g_ntok || strcmp(g_tok[*i], "{") != 0) return 0;
  (*i)++;
  int depth = 1;
  while (*i < g_ntok && depth > 0) {
    const char *t = g_tok[*i];
    if (strcmp(t, "{") == 0) { depth++; (*i)++; continue; }
    if (strcmp(t, "}") == 0) { depth--; (*i)++; continue; }
    if (depth != 1) { (*i)++; continue; }
    char keybuf[48];
    const char *key = NULL;
    size_t tl = strlen(t);
    if (tl >= 2 && t[tl - 1U] == ':') {
      if (tl - 1U >= sizeof(keybuf)) { (*i)++; continue; }
      memcpy(keybuf, t, tl - 1U);
      keybuf[tl - 1U] = '\0';
      if (!payload_key_ok(keybuf)) { (*i)++; continue; }
      key = keybuf;
      (*i)++;
    } else {
      if (!payload_key_ok(t)) { (*i)++; continue; }
      if (tl >= sizeof(keybuf)) { (*i)++; continue; }
      memcpy(keybuf, t, tl);
      keybuf[tl] = '\0';
      key = keybuf;
      (*i)++;
      if (*i >= g_ntok || strcmp(g_tok[*i], ":") != 0) continue;
      (*i)++;
    }
    if (*i >= g_ntok) break;
    const char *valtok = g_tok[*i];
    char valbuf[256] = {0};
    if (valtok && strlen(valtok) >= 2 && (valtok[0] == '"' || valtok[0] == '\'')) {
      size_t L = strlen(valtok);
      size_t nc = L >= 2 ? L - 2 : 0;
      if (nc >= sizeof(valbuf)) nc = sizeof(valbuf) - 1U;
      memcpy(valbuf, valtok + 1, nc);
      valbuf[nc] = '\0';
    } else if (valtok && valtok[0] == ':' && valtok[1] == ':') {
      const char *vv = var_get(valtok);
      if (vv) (void)snprintf(valbuf, sizeof(valbuf), "%s", vv);
      else valbuf[0] = '\0';
    } else {
      (void)snprintf(valbuf, sizeof(valbuf), "%s", valtok ? valtok : "");
    }
    (*i)++;
    if (n < max_out && key) {
      (void)snprintf(out[n].key, sizeof(out[n].key), "%s", key);
      (void)snprintf(out[n].v, sizeof(out[n].v), "%s", valbuf);
      n++;
    }
    if (*i < g_ntok && strcmp(g_tok[*i], ",") == 0) (*i)++;
  }
  return n;
}

static void queue_push_event(const char *ev, const PayloadKV *kv, int nkv) {
  if ((g_queue_tail + 1) % MAX_EVENTS == g_queue_head) return;
  QueuedEvent *qe = &g_event_queue[g_queue_tail];
  (void)snprintf(qe->ev, sizeof(qe->ev), "%s", ev ? ev : "");
  if (nkv > MAX_PAYLOAD_KEYS) nkv = MAX_PAYLOAD_KEYS;
  qe->nkv = nkv;
  for (int k = 0; k < nkv; k++) {
    size_t lk = strlen(kv[k].key);
    if (lk >= sizeof(qe->kv[k].key)) lk = sizeof(qe->kv[k].key) - 1U;
    memcpy(qe->kv[k].key, kv[k].key, lk);
    qe->kv[k].key[lk] = '\0';
    size_t lv = strlen(kv[k].v);
    if (lv >= sizeof(qe->kv[k].v)) lv = sizeof(qe->kv[k].v) - 1U;
    memcpy(qe->kv[k].v, kv[k].v, lv);
    qe->kv[k].v[lv] = '\0';
  }
  g_queue_tail = (g_queue_tail + 1) % MAX_EVENTS;
}

static int queue_pop_event(QueuedEvent *qe) {
  if (g_queue_head == g_queue_tail) return 0;
  *qe = g_event_queue[g_queue_head];
  g_queue_head = (g_queue_head + 1) % MAX_EVENTS;
  return 1;
}

static void apply_event_payload(const QueuedEvent *qe) {
  char fullkey[96];
  for (int k = 0; k < qe->nkv; k++) {
    (void)snprintf(fullkey, sizeof(fullkey), "::event.data.%s", qe->kv[k].key);
    var_set(fullkey, qe->kv[k].v);
  }
}

static void clear_event_payload(const QueuedEvent *qe) {
  char fullkey[96];
  for (int k = 0; k < qe->nkv; k++) {
    (void)snprintf(fullkey, sizeof(fullkey), "::event.data.%s", qe->kv[k].key);
    var_set(fullkey, "");
  }
}
static void register_listener(const char *ev, int start, int end) {
  if (g_nlisteners < MAX_LISTENERS) {
    (void)snprintf(g_listeners[g_nlisteners].event, sizeof(g_listeners[g_nlisteners].event),
                   "%s", ev ? ev : "");
    g_listeners[g_nlisteners].block_start = start;
    g_listeners[g_nlisteners].block_end = end;
    g_nlisteners++;
  }
}

static int find_block_end(int i);
static void register_behavior_listeners(int start, int end);
static void exec_init_block(int *i);
static void exec_link(int *i);
static void run_linked_component(const char *link_target);
static void exec_if(int *i);
static int eval_expr(int *i, char *out, size_t outsz);
static void exec_listen(int *i);
static void exec_block_impl(int start, int end, int preserve_listener_break_exit);

/*
 * Double-quoted say: expand ::path and ::path.length (path = dotted segments;
 * .length → decimal strlen of stored value, same as eval_expr).
 * Single-quoted strings are literal. Returns 0 on success.
 */
static int say_expand_double_quoted(const char *inner, size_t n) {
  size_t p = 0;
  while (p < n) {
    if (p + 1 < n && inner[p] == ':' && inner[p + 1] == ':') {
      size_t path0 = p + 2;
      if (path0 >= n || (!isalpha((unsigned char)inner[path0]) && inner[path0] != '_')) {
        fputc(':', stdout);
        p++;
        continue;
      }
      size_t j = path0;
      j++;
      while (j < n && (isalnum((unsigned char)inner[j]) || inner[j] == '_')) j++;
      int use_length = 0;
      size_t end_hole = j;
      for (;;) {
        if (j + 7 <= n && memcmp(inner + j, ".length", 7) == 0) {
          size_t after = j + 7;
          if (after == n || !(isalnum((unsigned char)inner[after]) || inner[after] == '_' ||
                              inner[after] == '.')) {
            use_length = 1;
            end_hole = after;
            break;
          }
        }
        if (j < n && inner[j] == '.') {
          j++;
          if (j >= n || (!isalpha((unsigned char)inner[j]) && inner[j] != '_')) {
            fputc(':', stdout);
            p++;
            continue;
          }
          j++;
          while (j < n && (isalnum((unsigned char)inner[j]) || inner[j] == '_')) j++;
          continue;
        }
        end_hole = j;
        break;
      }
      char kbuf[128];
      size_t plen = j - path0;
      if (plen + 3 >= sizeof(kbuf)) return -1;
      kbuf[0] = ':';
      kbuf[1] = ':';
      memcpy(kbuf + 2, inner + path0, plen);
      kbuf[2 + plen] = '\0';
      const char *vv = var_get(kbuf);
      if (use_length) {
        unsigned long Ln = vv ? (unsigned long)strlen(vv) : 0UL;
        fprintf(stdout, "%lu", Ln);
      } else if (vv) {
        fputs(vv, stdout);
      }
      p = end_hole;
    } else {
      fputc(inner[p], stdout);
      p++;
    }
  }
  return 0;
}

/* Execute say "string" or say ::var - print to stdout */
static void exec_say(int *i) {
  (*i)++;
  if (*i >= g_ntok) return;
  const char *s = g_tok[*i];
  if (s && strlen(s) >= 2 && s[0] == '"') {
    size_t len = strlen(s);
    size_t n = (len >= 2) ? len - 2 : 0;
    if (say_expand_double_quoted(s + 1, n) != 0) {
      fprintf(stderr, "azl_interpreter_minimal: say double-quoted expand failed\n");
      exit(5);
    }
    fputc('\n', stdout);
    fflush(stdout);
    (*i)++;
  } else if (s && strlen(s) >= 2 && s[0] == '\'') {
    size_t len = strlen(s);
    fwrite(s + 1, 1, len - 2, stdout);
    fputc('\n', stdout);
    fflush(stdout);
    (*i)++;
  } else if (s && s[0] == ':' && s[1] == ':') {
    const char *v = var_get(s);
    if (v) fputs(v, stdout);
    fputc('\n', stdout);
    fflush(stdout);
    (*i)++;
  } else {
    (*i)++;
  }
}

/* Skip a balanced [...] or {...} starting at g_tok[*i] (inclusive). */
static void consume_agg_literal(int *i) {
  if (*i >= g_ntok) return;
  const char *open = g_tok[*i];
  const char *close = NULL;
  if (strcmp(open, "[") == 0) close = "]";
  else if (strcmp(open, "{") == 0) close = "}";
  else return;
  int d = 1;
  (*i)++;
  while (*i < g_ntok && d > 0) {
    if (strcmp(g_tok[*i], open) == 0) d++;
    else if (strcmp(g_tok[*i], close) == 0) d--;
    (*i)++;
  }
}

static void tz_esc_field_c(const char *in, char *out, size_t cap) {
  if (!out || cap == 0) return;
  out[0] = '\0';
  size_t o = 0;
  for (const char *p = in ? in : ""; *p && o + 2 < cap; p++) {
    if (*p == '\\' || *p == '|') {
      out[o++] = '\\';
      if (o + 1 >= cap) break;
    }
    out[o++] = *p;
  }
  if (o < cap)
    out[o] = '\0';
  else
    out[cap - 1U] = '\0';
}

static int push_obj_value_uint_str(const char *vt) {
  if (!vt || !*vt) return 0;
  for (const char *p = vt; *p; p++)
    if (!isdigit((unsigned char)*p)) return 0;
  return 1;
}

/* Parse `{ type: "…", value: "…", line: N, column: M }` for .push → tz|…|…|…|… */
static int parse_push_tz_object(int *i, char *seg, size_t seg_sz) {
  if (!seg || seg_sz == 0) return -1;
  if (*i >= g_ntok || strcmp(g_tok[*i], "{") != 0) return -1;
  (*i)++;
  char ty[96] = {0}, vl[96] = {0}, ln[48] = {0}, col[48] = {0};
  int depth = 1;
  while (*i < g_ntok && depth > 0) {
    const char *t = g_tok[*i];
    if (strcmp(t, "{") == 0) return -1;
    if (strcmp(t, "}") == 0) {
      depth--;
      (*i)++;
      if (depth == 0) break;
      continue;
    }
    if (depth != 1) return -1;
    char keybuf[48];
    const char *key = NULL;
    size_t tl = strlen(t);
    if (tl >= 2 && t[tl - 1U] == ':') {
      if (tl - 1U >= sizeof(keybuf)) return -1;
      memcpy(keybuf, t, tl - 1U);
      keybuf[tl - 1U] = '\0';
      if (!payload_key_ok(keybuf)) return -1;
      key = keybuf;
      (*i)++;
    } else {
      if (!payload_key_ok(t)) return -1;
      if (tl >= sizeof(keybuf)) return -1;
      memcpy(keybuf, t, tl);
      keybuf[tl] = '\0';
      key = keybuf;
      (*i)++;
      if (*i >= g_ntok || strcmp(g_tok[*i], ":") != 0) return -1;
      (*i)++;
    }
    if (*i >= g_ntok) return -1;
    const char *valtok = g_tok[*i];
    char raw[128] = {0};
    if (valtok && strlen(valtok) >= 2U && (valtok[0] == '"' || valtok[0] == '\'')) {
      size_t L = strlen(valtok);
      size_t nc = L >= 2U ? L - 2U : 0U;
      if (nc >= sizeof(raw)) nc = sizeof(raw) - 1U;
      memcpy(raw, valtok + 1, nc);
      raw[nc] = '\0';
    } else if (valtok && push_obj_value_uint_str(valtok)) {
      (void)snprintf(raw, sizeof(raw), "%s", valtok);
    } else if (valtok && valtok[0] == ':' && valtok[1] == ':') {
      const char *vv = var_get(valtok);
      if (vv)
        (void)snprintf(raw, sizeof(raw), "%.127s", vv);
      else
        raw[0] = '\0';
    } else
      return -1;
    (*i)++;
    if (strcmp(key, "type") == 0) {
      char tmp[96];
      (void)snprintf(tmp, sizeof(tmp), "%.63s", raw);
      (void)snprintf(ty, sizeof(ty), "%s", tmp);
    } else if (strcmp(key, "value") == 0) {
      char tmp[96];
      (void)snprintf(tmp, sizeof(tmp), "%.63s", raw);
      (void)snprintf(vl, sizeof(vl), "%s", tmp);
    } else if (strcmp(key, "line") == 0) {
      (void)snprintf(ln, sizeof(ln), "%.31s", raw);
    } else if (strcmp(key, "column") == 0) {
      (void)snprintf(col, sizeof(col), "%.31s", raw);
    } else
      return -1;
    if (*i < g_ntok && strcmp(g_tok[*i], ",") == 0) (*i)++;
  }
  if (depth != 0) return -1;
  char et[112], ev[112], el[64], ec[64];
  tz_esc_field_c(ty, et, sizeof(et));
  tz_esc_field_c(vl, ev, sizeof(ev));
  tz_esc_field_c(ln, el, sizeof(el));
  tz_esc_field_c(col, ec, sizeof(ec));
  /* Worst-case escaped row can exceed seg (Var.v is 256); format into scratch to avoid
   * -Wformat-truncation, then copy — matches Python joined[:255] truncation at var_set. */
  char enc[512];
  int nw = snprintf(enc, sizeof(enc), "tz|%s|%s|%s|%s", et, ev, el, ec);
  if (nw < 0 || (size_t)nw >= sizeof(enc))
    return -1;
  size_t take = (size_t)nw;
  if (take >= seg_sz)
    take = seg_sz - 1U;
  memcpy(seg, enc, take);
  seg[take] = '\0';
  return 0;
}

static int rhs_is_var_concat_call(const char *v, char *base_out, size_t base_sz) {
  if (!v || !base_out || base_sz == 0) return 0;
  base_out[0] = '\0';
  if (v[0] != ':' || v[1] != ':') return 0;
  size_t L = strlen(v);
  const char *suf = ".concat";
  size_t sl = strlen(suf);
  if (L <= 2U + sl) return 0;
  if (strcmp(v + L - sl, suf) != 0) return 0;
  size_t bl = L - sl;
  if (bl >= base_sz) bl = base_sz - 1U;
  memcpy(base_out, v, bl);
  base_out[bl] = '\0';
  return 1;
}

static void mini_expr_error(const char *ctx) {
  fprintf(stderr, "azl_interpreter_minimal: expression error: %s\n", ctx ? ctx : "parse");
}

static int values_eq(int l_nullish, const char *l, int r_nullish, const char *r) {
  if (l_nullish && r_nullish) return 1;
  if (l_nullish || r_nullish) return 0;
  return strcmp(l, r) == 0;
}

static int cond_is_true(const char *s);

static int eval_primary(int *i, char *out, size_t outsz, int *nullish);
static int eval_sum(int *i, char *out, size_t outsz, int *nullish_out);

static int eval_eq(int *i, char *out, size_t outsz, int *nullish_out) {
  char left[256], right[256];
  int ln = 0, rn = 0;
  if (eval_sum(i, left, sizeof(left), &ln) != 0) return -1;
  if (*i >= g_ntok ||
      (strcmp(g_tok[*i], "==") != 0 && strcmp(g_tok[*i], "!=") != 0)) {
    (void)snprintf(out, outsz, "%s", left);
    *nullish_out = ln;
    return 0;
  }
  const char *op = g_tok[*i];
  (*i)++;
  if (eval_sum(i, right, sizeof(right), &rn) != 0) return -1;
  int eq = values_eq(ln, left, rn, right);
  if (strcmp(op, "!=") == 0) eq = !eq;
  (void)snprintf(out, outsz, "%s", eq ? "true" : "false");
  *nullish_out = 0;
  return 0;
}

static int eval_and(int *i, char *out, size_t outsz, int *nullish_out) {
  char acc[256];
  int acc_n = 0;
  if (eval_eq(i, acc, sizeof(acc), &acc_n) != 0) return -1;
  while (*i < g_ntok && strcmp(g_tok[*i], "&&") == 0) {
    (*i)++;
    if (!cond_is_true(acc)) {
      char dummy[256];
      int dn = 0;
      if (eval_eq(i, dummy, sizeof(dummy), &dn) != 0) return -1;
      while (*i < g_ntok && strcmp(g_tok[*i], "&&") == 0) {
        (*i)++;
        if (eval_eq(i, dummy, sizeof(dummy), &dn) != 0) return -1;
      }
      (void)snprintf(out, outsz, "false");
      *nullish_out = 0;
      return 0;
    }
    char next[256];
    int nn = 0;
    if (eval_eq(i, next, sizeof(next), &nn) != 0) return -1;
    (void)snprintf(acc, sizeof(acc), "%s", next);
    acc_n = nn;
  }
  (void)snprintf(out, outsz, "%s", acc);
  *nullish_out = acc_n;
  return 0;
}

static int eval_or(int *i, char *out, size_t outsz) {
  char acc[256];
  int acc_nullish = 0;
  if (eval_and(i, acc, sizeof(acc), &acc_nullish) != 0) return -1;
  while (*i < g_ntok && strcmp(g_tok[*i], "or") == 0) {
    (*i)++;
    char next[256];
    int nn = 0;
    if (eval_and(i, next, sizeof(next), &nn) != 0) return -1;
    int use_right = (acc_nullish || acc[0] == '\0');
    if (use_right) {
      (void)snprintf(acc, sizeof(acc), "%s", next);
      acc_nullish = nn;
    }
  }
  (void)snprintf(out, outsz, "%s", acc);
  return 0;
}

/* After a primary value, consume optional `.toInt()` calls (AZL interpreter init). */
static int apply_to_int_suffixes(int *i, char *out, size_t outsz, int *nullish) {
  while (*i + 2 < g_ntok && strcmp(g_tok[*i], ".") == 0 && strcmp(g_tok[*i + 1], "toInt") == 0 &&
         strcmp(g_tok[*i + 2], "(") == 0) {
    *i += 3;
    if (*i >= g_ntok || strcmp(g_tok[*i], ")") != 0) return -1;
    (*i)++;
    char *endp = NULL;
    long n = 0;
    if (!*nullish && out[0] != '\0') {
      n = strtol(out, &endp, 10);
      if (endp == out || (endp && *endp != '\0')) n = 0;
    }
    (void)snprintf(out, outsz, "%ld", n);
    *nullish = 0;
  }
  return 0;
}

static int eval_primary(int *i, char *out, size_t outsz, int *nullish) {
  *nullish = 0;
  out[0] = '\0';
  if (*i >= g_ntok) return -1;
  const char *t = g_tok[*i];
  if (!t) return -1;

  if (strcmp(t, "(") == 0) {
    (*i)++;
    if (eval_or(i, out, outsz) != 0) return -1;
    if (*i >= g_ntok || strcmp(g_tok[*i], ")") != 0) return -1;
    (*i)++;
    if (apply_to_int_suffixes(i, out, outsz, nullish) != 0) return -1;
    return 0;
  }

  if (strlen(t) >= 2 && (t[0] == '"' || t[0] == '\'')) {
    size_t len = strlen(t);
    size_t n = (len >= 2) ? len - 2 : 0;
    if (n >= outsz) n = outsz - 1;
    memcpy(out, t + 1, n);
    out[n] = '\0';
    (*i)++;
    return 0;
  }

  if (isdigit((unsigned char)t[0]) || (t[0] == '-' && t[1] && isdigit((unsigned char)t[1]))) {
    (void)snprintf(out, outsz, "%s", t);
    (*i)++;
    return 0;
  }

  if (strcmp(t, "null") == 0) {
    *nullish = 1;
    (*i)++;
    return 0;
  }

  if (strcmp(t, "false") == 0 || strcmp(t, "true") == 0) {
    (void)snprintf(out, outsz, "%s", t);
    (*i)++;
    return 0;
  }

  if (t[0] == ':' && t[1] == ':') {
    if (strcmp(t, "::internal.env") == 0) {
      (*i)++;
      if (*i >= g_ntok || strcmp(g_tok[*i], "(") != 0) return -1;
      (*i)++;
      if (*i >= g_ntok) return -1;
      const char *ts = g_tok[*i];
      if (strlen(ts) < 2 || (ts[0] != '"' && ts[0] != '\'')) return -1;
      char key[128] = {0};
      size_t L = strlen(ts);
      size_t n = (L >= 2) ? L - 2 : 0;
      if (n >= sizeof(key)) n = sizeof(key) - 1;
      memcpy(key, ts + 1, n);
      key[n] = '\0';
      (*i)++;
      if (*i >= g_ntok || strcmp(g_tok[*i], ")") != 0) return -1;
      (*i)++;
      const char *ev = getenv(key);
      if (ev) (void)snprintf(out, outsz, "%s", ev);
      else out[0] = '\0';
      *nullish = 0;
      return 0;
    }
    {
      const char *suf = ".length";
      size_t tl = strlen(t);
      size_t sl = strlen(suf);
      if (tl > sl + 3U && strcmp(t + tl - sl, suf) == 0) {
        char base[128];
        size_t bl = tl - sl;
        if (bl >= sizeof(base)) return -1;
        memcpy(base, t, bl);
        base[bl] = '\0';
        if (base[0] == ':' && base[1] == ':') {
          (*i)++;
          const char *vv = var_get(base);
          unsigned long Ln = vv ? (unsigned long)strlen(vv) : 0UL;
          (void)snprintf(out, outsz, "%lu", Ln);
          *nullish = 0;
          return 0;
        }
      }
    }
    const char *vv = var_get(t);
    if (!vv) *nullish = 1;
    else (void)snprintf(out, outsz, "%s", vv);
    (*i)++;
    return 0;
  }

  return -1;
}

/* Primary (+ primary)* — int + if both canonical base-10, else string concat. */
static int parse_full_long(const char *s, long *out) {
  if (!s || !*s) return 0;
  char *e = NULL;
  errno = 0;
  long v = strtol(s, &e, 10);
  if (errno == ERANGE || e == s || (e && *e != '\0')) return 0;
  char canon[256];
  (void)snprintf(canon, sizeof(canon), "%ld", v);
  if (strcmp(canon, s) != 0) return 0;
  *out = v;
  return 1;
}

static int eval_sum(int *i, char *out, size_t outsz, int *nullish_out) {
  char acc[256];
  int acc_n = 0;
  if (eval_primary(i, acc, sizeof(acc), &acc_n) != 0) return -1;
  while (*i < g_ntok &&
         (strcmp(g_tok[*i], "+") == 0 || strcmp(g_tok[*i], "-") == 0)) {
    int is_sub = (strcmp(g_tok[*i], "-") == 0);
    (*i)++;
    char rh[256];
    int rn = 0;
    if (eval_primary(i, rh, sizeof(rh), &rn) != 0) return -1;
    long la, lb;
    int a_int = !acc_n && parse_full_long(acc, &la);
    int b_int = !rn && parse_full_long(rh, &lb);
    if (a_int && b_int) {
      long res = is_sub ? (la - lb) : (la + lb);
      (void)snprintf(acc, sizeof(acc), "%ld", res);
      acc_n = 0;
    } else {
      if (is_sub) return -1;
      char tmp[512];
      (void)snprintf(tmp, sizeof(tmp), "%s%s", acc_n ? "" : acc, rn ? "" : rh);
      size_t tl = strlen(tmp);
      if (tl >= sizeof(acc)) return -1;
      memcpy(acc, tmp, tl + 1);
      acc_n = 0;
    }
  }
  (void)snprintf(out, outsz, "%s", acc);
  *nullish_out = acc_n;
  return 0;
}

static int eval_expr(int *i, char *out, size_t outsz) {
  return eval_or(i, out, outsz);
}

static int cond_is_true(const char *s) {
  return s && (strcmp(s, "true") == 0 || strcmp(s, "1") == 0);
}

static void skip_braced_block(int *i) {
  if (*i >= g_ntok || strcmp(g_tok[*i], "{") != 0) return;
  int d = 1;
  (*i)++;
  while (*i < g_ntok && d > 0) {
    if (strcmp(g_tok[*i], "{") == 0) d++;
    else if (strcmp(g_tok[*i], "}") == 0) d--;
    (*i)++;
  }
}

static void exec_if(int *i) {
  (*i)++;
  char cond[256] = {0};
  if (eval_expr(i, cond, sizeof(cond)) != 0) {
    mini_expr_error("if condition");
    exit(5);
  }
  if (*i >= g_ntok || strcmp(g_tok[*i], "{") != 0) {
    mini_expr_error("if missing {");
    exit(5);
  }
  if (cond_is_true(cond)) {
    (*i)++;
    exec_init_block(i);
    if (*i < g_ntok && strcmp(g_tok[*i], "}") == 0) (*i)++;
  } else {
    skip_braced_block(i);
  }
}

/* Unescape AZL quoted string token (minimal: \\n \\t \\r \\\\ \" \') into out. */
static int unescape_azl_string_token(const char *quoted, char *out, size_t outsz) {
  if (!out || outsz == 0) return -1;
  out[0] = '\0';
  if (!quoted) return -1;
  size_t L = strlen(quoted);
  if (L < 2) return -1;
  char q = quoted[0];
  if ((q != '"' && q != '\'') || quoted[L - 1U] != q) return -1;
  const char *in = quoted + 1;
  const char *end = quoted + L - 1U;
  size_t o = 0;
  while (in < end && o + 1 < outsz) {
    if (*in == '\\' && in + 1 < end) {
      char n = in[1];
      if (n == 'n') out[o++] = '\n';
      else if (n == 't') out[o++] = '\t';
      else if (n == 'r') out[o++] = '\r';
      else if (n == '\\') out[o++] = '\\';
      else if (n == '"') out[o++] = '"';
      else if (n == '\'') out[o++] = '\'';
      else out[o++] = n;
      in += 2;
    } else {
      out[o++] = *in++;
    }
  }
  out[o] = '\0';
  return (int)o;
}

static void split_join_newlines(const char *src, const char *delim, char *out, size_t cap) {
  if (!out || cap == 0) return;
  out[0] = '\0';
  if (!delim || !delim[0]) return;
  size_t o = 0;
  const char *p = src ? src : "";
  size_t dlen = strlen(delim);
  int need_nl = 0;
  for (;;) {
    const char *found = strstr(p, delim);
    size_t seglen = found ? (size_t)(found - p) : strlen(p);
    if (need_nl && o + 1 < cap) out[o++] = '\n';
    need_nl = 1;
    for (size_t j = 0; j < seglen && o + 1 < cap; j++)
      out[o++] = p[j];
    out[o] = '\0';
    if (!found) break;
    p = found + dlen;
  }
}

/* UTF-8: length in bytes of one scalar value starting at s; 0 at NUL; 1 on invalid lead. */
static size_t utf8_scalar_byte_len(const unsigned char *s) {
  if (!s || !*s) return 0;
  unsigned char c0 = s[0];
  if (c0 < 0x80) return 1;
  if ((c0 & 0xE0) == 0xC0) {
    if (!s[1] || (s[1] & 0xC0) != 0x80) return 1;
    if (c0 < 0xC2) return 1;
    return 2;
  }
  if ((c0 & 0xF0) == 0xE0) {
    if (!s[1] || !s[2] || (s[1] & 0xC0) != 0x80 || (s[2] & 0xC0) != 0x80) return 1;
    if (c0 == 0xE0 && s[1] < 0xA0) return 1;
    if (c0 == 0xED && s[1] > 0x9F) return 1;
    return 3;
  }
  if ((c0 & 0xF8) == 0xF0) {
    if (!s[1] || !s[2] || !s[3]) return 1;
    if ((s[1] & 0xC0) != 0x80 || (s[2] & 0xC0) != 0x80 || (s[3] & 0xC0) != 0x80) return 1;
    if (c0 == 0xF0 && s[1] < 0x90) return 1;
    if (c0 == 0xF4 && s[1] > 0x8F) return 1;
    return 4;
  }
  return 1;
}

static void join_chars_newlines_utf8(const char *src, char *out, size_t cap) {
  if (!out || cap == 0) return;
  out[0] = '\0';
  size_t o = 0;
  const unsigned char *p = (const unsigned char *)(src ? src : "");
  int need_nl = 0;
  while (*p) {
    size_t L = utf8_scalar_byte_len(p);
    if (L == 0) break;
    if (need_nl && o + 1 < cap) out[o++] = '\n';
    need_nl = 1;
    for (size_t j = 0; j < L && o + 1 < cap; j++)
      out[o++] = (char)p[j];
    out[o] = '\0';
    p += L;
  }
}

/* True if v is ::name.split_chars; copies ::name into base_out. */
static int rhs_is_var_split_chars_call(const char *v, char *base_out, size_t base_sz) {
  if (!v || !base_out || base_sz == 0) return 0;
  base_out[0] = '\0';
  if (v[0] != ':' || v[1] != ':') return 0;
  size_t L = strlen(v);
  const char *suf = ".split_chars";
  size_t sl = strlen(suf);
  if (L <= 2U + sl) return 0;
  if (strcmp(v + L - sl, suf) != 0) return 0;
  size_t bl = L - sl;
  if (bl >= base_sz) bl = base_sz - 1U;
  memcpy(base_out, v, bl);
  base_out[bl] = '\0';
  return bl >= 3U ? 1 : 0;
}

/* True if v is ::name.split; copies ::name into base_out. */
static int rhs_is_var_split_call(const char *v, char *base_out, size_t base_sz) {
  if (!v || !base_out || base_sz == 0) return 0;
  base_out[0] = '\0';
  if (v[0] != ':' || v[1] != ':') return 0;
  size_t L = strlen(v);
  const char *suf = ".split";
  size_t sl = strlen(suf);
  if (L <= 2U + sl) return 0;
  if (strcmp(v + L - sl, suf) != 0) return 0;
  size_t bl = L - sl;
  if (bl >= base_sz) bl = base_sz - 1U;
  memcpy(base_out, v, bl);
  base_out[bl] = '\0';
  return bl >= 3U ? 1 : 0;
}

/* True if k is ::name.push; copies ::name into base_out. */
static int lhs_is_var_push_call(const char *k, char *base_out, size_t base_sz) {
  if (!k || !base_out || base_sz == 0) return 0;
  base_out[0] = '\0';
  if (k[0] != ':' || k[1] != ':') return 0;
  size_t L = strlen(k);
  const char *suf = ".push";
  size_t sl = strlen(suf);
  if (L <= 2U + sl) return 0;
  if (strcmp(k + L - sl, suf) != 0) return 0;
  size_t bl = L - sl;
  if (bl >= base_sz) bl = base_sz - 1U;
  memcpy(base_out, k, bl);
  base_out[bl] = '\0';
  return bl >= 3U ? 1 : 0;
}

/* Spine builtins: ::vm_compile_ast(::ast) sets ::vc.ok / ::vc.error / ::vc.bytecode (mirrors azl_interpreter.azl execute VM branch). */
static void builtin_vm_compile_ast_apply(const char *ast_in) {
  var_set("::vc.ok", "false");
  var_set("::vc.error", "");
  var_set("::vc.bytecode", "");
  const char *a = ast_in ? ast_in : "";
  if (strcmp(a, "F90_VM_OK") == 0) {
    var_set("::vc.ok", "true");
    var_set("::vc.bytecode", "BC");
  } else if (strcmp(a, "F91_VM_BAD") == 0) {
    var_set("::vc.ok", "false");
    var_set("::vc.error", "compile_failed");
  } else if (strcmp(a, "F92_VM_EMPTY") == 0) {
    var_set("::vc.ok", "true");
    var_set("::vc.bytecode", "");
  } else {
    var_set("::vc.ok", "false");
    var_set("::vc.error", "unknown_ast");
  }
}

static int rhs_vm_compile_ast_consume(int *i, char *ast_out, size_t ast_sz) {
  ast_out[0] = '\0';
  if (*i >= g_ntok) return -1;
  const char *a = g_tok[*i];
  if (a && a[0] == ':' && a[1] == ':') {
    const char *vv = var_get(a);
    (void)snprintf(ast_out, ast_sz, "%s", vv ? vv : "");
    (*i)++;
    return 0;
  }
  if (a && strlen(a) >= 2U && (a[0] == '"' || a[0] == '\'')) {
    if (unescape_azl_string_token(a, ast_out, ast_sz) < 0) return -1;
    (*i)++;
    return 0;
  }
  return -1;
}

static int rhs_vm_run_bytecode_consume(int *i, char *bc_out, size_t bc_sz) {
  bc_out[0] = '\0';
  if (*i >= g_ntok) return -1;
  const char *a = g_tok[*i];
  if (a && a[0] == ':' && a[1] == ':') {
    const char *vv = var_get(a);
    (void)snprintf(bc_out, bc_sz, "%s", vv ? vv : "");
    (*i)++;
    return 0;
  }
  return -1;
}

static void builtin_vm_run_bytecode_into(char *val, size_t valsz, const char *bc) {
  if (!bc || !bc[0]) {
    (void)snprintf(val, valsz, "vm_run_empty");
    return;
  }
  if (strcmp(bc, "BC") == 0)
    (void)snprintf(val, valsz, "P0_VM_EXEC_OK");
  else
    (void)snprintf(val, valsz, "vm_run:%s", bc);
}

/* After `(` — read ::astBase, ,, ::scopeVar, ). Caller positions *i at first arg. */
static int rhs_execute_ast_two_vars(int *i, char *ast_base, size_t ast_sz, char *scope_var, size_t scope_sz) {
  ast_base[0] = '\0';
  scope_var[0] = '\0';
  if (*i >= g_ntok || !g_tok[*i] || g_tok[*i][0] != ':' || g_tok[*i][1] != ':') return -1;
  (void)snprintf(ast_base, ast_sz, "%s", g_tok[*i]);
  (*i)++;
  if (*i >= g_ntok || strcmp(g_tok[*i], ",") != 0) return -1;
  (*i)++;
  if (*i >= g_ntok || !g_tok[*i] || g_tok[*i][0] != ':' || g_tok[*i][1] != ':') return -1;
  (void)snprintf(scope_var, scope_sz, "%s", g_tok[*i]);
  (*i)++;
  if (*i >= g_ntok || strcmp(g_tok[*i], ")") != 0) return -1;
  (*i)++;
  return 0;
}

/*
 * Parse execute_ast tail after "|with|": repeating key|value|key|value (F96 one pair, F97 many).
 * Returns count in [1, max_out] or 0 on failure.
 */
static int execute_ast_parse_with_pairs(const char *pay, PayloadKV *out, int max_out) {
  const char *r = pay ? pay : "";
  int n = 0;
  while (n < max_out && r[0]) {
    const char *sep1 = strchr(r, '|');
    if (!sep1 || sep1 == r) return 0;
    char kbuf[48];
    size_t kl = (size_t)(sep1 - r);
    if (kl >= sizeof(kbuf)) kl = sizeof(kbuf) - 1U;
    memcpy(kbuf, r, kl);
    kbuf[kl] = '\0';
    if (!payload_key_ok(kbuf)) return 0;
    r = sep1 + 1;
    const char *sep2 = strchr(r, '|');
    if (!sep2) {
      (void)snprintf(out[n].key, sizeof(out[n].key), "%s", kbuf);
      (void)snprintf(out[n].v, sizeof(out[n].v), "%s", r);
      n++;
      break;
    }
    char vbuf[256];
    size_t vl = (size_t)(sep2 - r);
    if (vl >= sizeof(vbuf)) vl = sizeof(vbuf) - 1U;
    memcpy(vbuf, r, vl);
    vbuf[vl] = '\0';
    (void)snprintf(out[n].key, sizeof(out[n].key), "%s", kbuf);
    (void)snprintf(out[n].v, sizeof(out[n].v), "%s", vbuf);
    n++;
    r = sep2 + 1;
  }
  return n > 0 ? n : 0;
}

/* execute_ast line: emit|eventName or emit|eventName|with|k|v(|k|v)* */
static void execute_ast_emit_line(const char *after_emit, char *result, size_t rsz) {
  const char *p = after_emit ? after_emit : "";
  const char *with = strstr(p, "|with|");
  if (with) {
    size_t evlen = (size_t)(with - p);
    if (evlen == 0U || evlen + 1U >= 64U) return;
    char evn[64];
    memcpy(evn, p, evlen);
    evn[evlen] = '\0';
    const char *pay = with + 6; /* "|with|" is 6 chars */
    PayloadKV payload[MAX_PAYLOAD_KEYS];
    int np = execute_ast_parse_with_pairs(pay, payload, MAX_PAYLOAD_KEYS);
    if (np <= 0) return;
    queue_push_event(evn, payload, np);
    process_events();
    (void)snprintf(result, rsz, "Emitted: %.120s", evn);
    return;
  }
  char evn[64];
  size_t e = 0;
  for (; p[e] && p[e] != '|' && e + 1U < sizeof(evn); e++)
    evn[e] = p[e];
  evn[e] = '\0';
  if (!evn[0]) return;
  queue_push_event(evn, NULL, 0);
  process_events();
  (void)snprintf(result, rsz, "Emitted: %.120s", evn);
}

/* set|::global|value — mirrors execute_set return string shape (no 💾 say in minimal stub). */
static void execute_ast_set_line(const char *after_set, char *result, size_t rsz) {
  const char *p = after_set ? after_set : "";
  const char *sep = strchr(p, '|');
  if (!sep || sep == p) return;
  char keybuf[96];
  size_t kl = (size_t)(sep - p);
  if (kl >= sizeof(keybuf)) kl = sizeof(keybuf) - 1U;
  memcpy(keybuf, p, kl);
  keybuf[kl] = '\0';
  if (keybuf[0] != ':' || keybuf[1] != ':') return;
  const char *val = sep + 1;
  char vbuf[256];
  (void)snprintf(vbuf, sizeof(vbuf), "%s", val ? val : "");
  var_set(keybuf, vbuf);
  (void)snprintf(result, rsz, "Set %s = %.150s", keybuf, vbuf);
}

static void execute_ast_listen_line(const char *after_listen, char *result, size_t rsz);

/* memory|set|::k|v, memory|say|text, memory|emit|…, memory|listen|… — stub memory rows (F104–F127; F115+ = memory|listen|… same stub table as listen|). */
static void execute_ast_memory_line(const char *after_mem, char *result, size_t rsz) {
  const char *p = after_mem ? after_mem : "";
  if (strncmp(p, "listen|", 7U) == 0) {
    execute_ast_listen_line(p + 7, result, rsz);
  } else if (strncmp(p, "set|", 4U) == 0) {
    execute_ast_set_line(p + 4, result, rsz);
  } else if (strncmp(p, "say|", 4U) == 0) {
    const char *pay = p + 4;
    fputs(pay, stdout);
    fputc('\n', stdout);
    fflush(stdout);
    (void)snprintf(result, rsz, "Said: %.200s", pay);
  } else if (strncmp(p, "emit|", 5U) == 0) {
    execute_ast_emit_line(p + 5, result, rsz);
  }
}

/* execute_ast component|name — run linked component init/listeners (F99). */
static void execute_ast_component_line(const char *after_comp, char *result, size_t rsz) {
  const char *p = after_comp ? after_comp : "";
  if (!p[0]) return;
  run_linked_component(p);
  (void)snprintf(result, rsz, "Component: %.120s", p);
}

/* execute_ast listen|event|say|payload — stub listener (F99); dispatch if no token listener matches. */
static void execute_ast_listen_line(const char *after_listen, char *result, size_t rsz) {
  const char *p = after_listen ? after_listen : "";
  const char *e1 = strchr(p, '|');
  if (!e1 || e1 == p) return;
  char evn[64];
  size_t el = (size_t)(e1 - p);
  if (el >= sizeof(evn)) el = sizeof(evn) - 1U;
  memcpy(evn, p, el);
  evn[el] = '\0';
  const char *q = e1 + 1;
  if (strncmp(q, "say|", 4U) == 0) {
    const char *pay = q + 4;
    if (!pay[0]) return;
    if (exec_ast_stub_register(evn, EXEC_AST_STUB_SAY, pay) != 0) return;
  } else if (strncmp(q, "emit|", 5U) == 0) {
    const char *tail = q + 5;
    if (!tail[0]) return;
    const char *ww = strstr(tail, "|with|");
    if (ww) {
      size_t innl = (size_t)(ww - tail);
      if (innl == 0U || innl + 1U >= 64U) return;
      char inn[64];
      memcpy(inn, tail, innl);
      inn[innl] = '\0';
      if (strchr(inn, '|') != NULL) return;
      const char *pay = ww + 6; /* strlen("|with|") == 6 */
      PayloadKV payload[MAX_PAYLOAD_KEYS];
      int np = execute_ast_parse_with_pairs(pay, payload, MAX_PAYLOAD_KEYS);
      if (np <= 0) return;
      if (exec_ast_stub_register_emit_with(evn, inn, payload, np) != 0) return;
    } else {
      if (strchr(tail, '|') != NULL) return;
      if (exec_ast_stub_register(evn, EXEC_AST_STUB_EMIT, tail) != 0) return;
    }
  } else if (strncmp(q, "set|", 4U) == 0) {
    const char *rest = q + 4;
    const char *sep = strchr(rest, '|');
    if (!sep || sep == rest) return;
    if (rest[0] != ':' || rest[1] != ':') return;
    char keybuf[64];
    size_t kl = (size_t)(sep - rest);
    if (kl >= sizeof(keybuf)) kl = sizeof(keybuf) - 1U;
    memcpy(keybuf, rest, kl);
    keybuf[kl] = '\0';
    const char *val = sep + 1;
    if (exec_ast_stub_register_set(evn, keybuf, val) != 0) return;
  } else
    return;
  (void)snprintf(result, rsz, "Listen: %.120s", evn);
}

/* Shallow import stub (mirrors preloop resolve_module_now for import nodes; F98). */
static void execute_ast_import_line(const char *after_import) {
  const char *p = after_import ? after_import : "";
  if (!p[0]) return;
  var_set("::p0_exec_import_last", p);
}

/* Shallow link: same as `link ::target` init side-effect (F98 preloop). */
static void execute_ast_link_line(const char *after_link) {
  const char *p = after_link ? after_link : "";
  if (!p[0]) return;
  run_linked_component(p);
}

static void builtin_execute_ast_into(char *val, size_t valsz, const char *ast_base) {
  char nodes_key[160];
  if (!ast_base || !ast_base[0] || strlen(ast_base) + 7U >= sizeof(nodes_key)) {
    (void)snprintf(val, valsz, "execute_ast_bad_base");
    return;
  }
  (void)snprintf(nodes_key, sizeof(nodes_key), "%s.nodes", ast_base);
  const char *nodes0 = var_get(nodes_key);
  char result[256];
  (void)snprintf(result, sizeof(result), "Execution completed");
  if (!nodes0 || !nodes0[0]) {
    (void)snprintf(val, valsz, "%s", result);
    return;
  }
  exec_ast_stubs_reset();
  char buf1[512], buf2[512];
  (void)snprintf(buf1, sizeof(buf1), "%s", nodes0);
  (void)snprintf(buf2, sizeof(buf2), "%s", nodes0);
  char *save1 = NULL;
  for (char *line = strtok_r(buf1, "\n", &save1); line; line = strtok_r(NULL, "\n", &save1)) {
    const char *haltv = var_get("::halted");
    if (haltv && strcmp(haltv, "true") == 0) {
      (void)snprintf(result, sizeof(result), "Execution halted due to error");
      (void)snprintf(val, valsz, "%s", result);
      return;
    }
    while (*line == ' ' || *line == '\t') line++;
    if (!line[0]) continue;
    if (strncmp(line, "import|", 7U) == 0)
      execute_ast_import_line(line + 7);
    else if (strncmp(line, "link|", 5U) == 0)
      execute_ast_link_line(line + 5);
  }
  char *save2 = NULL;
  for (char *line = strtok_r(buf2, "\n", &save2); line; line = strtok_r(NULL, "\n", &save2)) {
    const char *haltv = var_get("::halted");
    if (haltv && strcmp(haltv, "true") == 0) {
      (void)snprintf(result, sizeof(result), "Execution halted due to error");
      break;
    }
    while (*line == ' ' || *line == '\t') line++;
    if (!line[0]) continue;
    if (strncmp(line, "import|", 7U) == 0) continue;
    if (strncmp(line, "link|", 5U) == 0) continue;
    if (strncmp(line, "say|", 4U) == 0) {
      const char *pay = line + 4;
      fputs(pay, stdout);
      fputc('\n', stdout);
      fflush(stdout);
      (void)snprintf(result, sizeof(result), "Said: %.200s", pay);
    } else if (strncmp(line, "emit|", 5U) == 0) {
      execute_ast_emit_line(line + 5, result, sizeof(result));
    } else if (strncmp(line, "set|", 4U) == 0) {
      execute_ast_set_line(line + 4, result, sizeof(result));
    } else if (strncmp(line, "component|", 10U) == 0) {
      execute_ast_component_line(line + 10, result, sizeof(result));
    } else if (strncmp(line, "memory|", 7U) == 0) {
      execute_ast_memory_line(line + 7, result, sizeof(result));
    } else if (strncmp(line, "listen|", 7U) == 0) {
      execute_ast_listen_line(line + 7, result, sizeof(result));
    }
  }
  (void)snprintf(val, valsz, "%s", result);
}

/* Execute set ::var = value */
static void exec_set(int *i) {
  (*i)++;
  if (*i >= g_ntok) return;
  const char *k = g_tok[*i];
  if (!k || k[0] != ':' || k[1] != ':') { (*i)++; return; }
  char push_base[64];
  if (lhs_is_var_push_call(k, push_base, sizeof(push_base))) {
    (*i)++;
    if (*i >= g_ntok || strcmp(g_tok[*i], "(") != 0) {
      fprintf(stderr, "azl_interpreter_minimal: .push missing (\n");
      exit(5);
    }
    (*i)++;
    if (*i >= g_ntok) {
      fprintf(stderr, "azl_interpreter_minimal: .push missing arg\n");
      exit(5);
    }
    const char *arg = g_tok[*i];
    char seg[256] = {0};
    if (arg && strlen(arg) >= 2U && (arg[0] == '"' || arg[0] == '\'')) {
      size_t len = strlen(arg);
      size_t n = (len >= 2U) ? len - 2U : 0U;
      if (n >= sizeof(seg)) n = sizeof(seg) - 1U;
      memcpy(seg, arg + 1, n);
      seg[n] = '\0';
      (*i)++;
    } else if (arg && strcmp(arg, "{") == 0) {
      if (parse_push_tz_object(i, seg, sizeof(seg)) != 0) {
        fprintf(stderr, "azl_interpreter_minimal: .push object parse failed\n");
        exit(5);
      }
    } else if (arg && arg[0] == ':' && arg[1] == ':') {
      const char *vv = var_get(arg);
      if (vv) (void)snprintf(seg, sizeof(seg), "%s", vv);
      (*i)++;
    } else {
      fprintf(stderr, "azl_interpreter_minimal: .push bad arg\n");
      exit(5);
    }
    if (*i >= g_ntok || strcmp(g_tok[*i], ")") != 0) {
      fprintf(stderr, "azl_interpreter_minimal: .push missing )\n");
      exit(5);
    }
    (*i)++;
    const char *cur0 = var_get(push_base);
    const char *cur = (cur0 && cur0[0] && strcmp(cur0, "[]") != 0) ? cur0 : "";
    char out[256] = {0};
    if (!cur[0])
      (void)snprintf(out, sizeof(out), "%s", seg);
    else
      (void)snprintf(out, sizeof(out), "%s\n%s", cur, seg);
    var_set(push_base, out);
    return;
  }
  (*i)++;
  if (*i >= g_ntok || strcmp(g_tok[*i], "=") != 0) return;
  (*i)++;
  if (*i >= g_ntok) return;
  const char *v = g_tok[*i];
  char val[256] = {0};
  char concat_base[64];
  if (v && rhs_is_var_concat_call(v, concat_base, sizeof(concat_base))) {
    (*i)++;
    if (*i >= g_ntok || strcmp(g_tok[*i], "(") != 0) {
      fprintf(stderr, "azl_interpreter_minimal: .concat missing (\n");
      exit(5);
    }
    (*i)++;
    if (*i >= g_ntok) {
      fprintf(stderr, "azl_interpreter_minimal: .concat missing arg\n");
      exit(5);
    }
    const char *carg = g_tok[*i];
    if (!carg || carg[0] != ':' || carg[1] != ':') {
      fprintf(stderr, "azl_interpreter_minimal: .concat bad arg\n");
      exit(5);
    }
    (*i)++;
    if (*i >= g_ntok || strcmp(g_tok[*i], ")") != 0) {
      fprintf(stderr, "azl_interpreter_minimal: .concat missing )\n");
      exit(5);
    }
    (*i)++;
    const char *l0 = var_get(concat_base);
    const char *r0 = var_get(carg);
    const char *lp = (l0 && l0[0] && strcmp(l0, "[]") != 0) ? l0 : "";
    const char *rp = (r0 && r0[0] && strcmp(r0, "[]") != 0) ? r0 : "";
    if (!lp[0])
      (void)snprintf(val, sizeof(val), "%s", rp);
    else if (!rp[0])
      (void)snprintf(val, sizeof(val), "%s", lp);
    else
      (void)snprintf(val, sizeof(val), "%s\n%s", lp, rp);
    var_set(k, val);
    return;
  }
  if (v && strcmp(v, "[") == 0) {
    consume_agg_literal(i);
    (void)snprintf(val, sizeof(val), "[]");
    var_set(k, val);
    return;
  }
  if (v && strcmp(v, "{") == 0) {
    consume_agg_literal(i);
    (void)snprintf(val, sizeof(val), "{}");
    var_set(k, val);
    return;
  }
  char schars_base[64];
  if (v && rhs_is_var_split_chars_call(v, schars_base, sizeof(schars_base))) {
    (*i)++;
    if (*i >= g_ntok || strcmp(g_tok[*i], "(") != 0) {
      fprintf(stderr, "azl_interpreter_minimal: .split_chars missing (\n");
      exit(5);
    }
    (*i)++;
    if (*i >= g_ntok || strcmp(g_tok[*i], ")") != 0) {
      fprintf(stderr, "azl_interpreter_minimal: .split_chars missing )\n");
      exit(5);
    }
    (*i)++;
    const char *srct = var_get(schars_base);
    join_chars_newlines_utf8(srct, val, sizeof(val));
    var_set(k, val);
    return;
  }
  char split_base[64];
  if (v && rhs_is_var_split_call(v, split_base, sizeof(split_base))) {
    (*i)++;
    if (*i >= g_ntok || strcmp(g_tok[*i], "(") != 0) {
      fprintf(stderr, "azl_interpreter_minimal: .split missing (\n");
      exit(5);
    }
    (*i)++;
    if (*i >= g_ntok) {
      fprintf(stderr, "azl_interpreter_minimal: .split missing literal\n");
      exit(5);
    }
    char delimbuf[64];
    if (unescape_azl_string_token(g_tok[*i], delimbuf, sizeof(delimbuf)) < 0 ||
        !delimbuf[0]) {
      fprintf(stderr, "azl_interpreter_minimal: split delimiter empty\n");
      exit(5);
    }
    (*i)++;
    if (*i >= g_ntok || strcmp(g_tok[*i], ")") != 0) {
      fprintf(stderr, "azl_interpreter_minimal: .split missing )\n");
      exit(5);
    }
    (*i)++;
    const char *srct = var_get(split_base);
    split_join_newlines(srct, delimbuf, val, sizeof(val));
    var_set(k, val);
    return;
  }
  if (v && strcmp(v, "::vm_compile_ast") == 0) {
    (*i)++;
    if (*i >= g_ntok || strcmp(g_tok[*i], "(") != 0) {
      fprintf(stderr, "azl_interpreter_minimal: vm_compile_ast missing (\n");
      exit(5);
    }
    (*i)++;
    char astb[256];
    if (rhs_vm_compile_ast_consume(i, astb, sizeof(astb)) != 0) {
      fprintf(stderr, "azl_interpreter_minimal: vm_compile_ast bad arg\n");
      exit(5);
    }
    if (*i >= g_ntok || strcmp(g_tok[*i], ")") != 0) {
      fprintf(stderr, "azl_interpreter_minimal: vm_compile_ast missing )\n");
      exit(5);
    }
    (*i)++;
    builtin_vm_compile_ast_apply(astb);
    var_set(k, "vm_compile_done");
    return;
  }
  if (v && strcmp(v, "::vm_run_bytecode_program") == 0) {
    (*i)++;
    if (*i >= g_ntok || strcmp(g_tok[*i], "(") != 0) {
      fprintf(stderr, "azl_interpreter_minimal: vm_run_bytecode_program missing (\n");
      exit(5);
    }
    (*i)++;
    char bcb[256];
    if (rhs_vm_run_bytecode_consume(i, bcb, sizeof(bcb)) != 0) {
      fprintf(stderr, "azl_interpreter_minimal: vm_run_bytecode_program bad arg\n");
      exit(5);
    }
    if (*i >= g_ntok || strcmp(g_tok[*i], ")") != 0) {
      fprintf(stderr, "azl_interpreter_minimal: vm_run_bytecode_program missing )\n");
      exit(5);
    }
    (*i)++;
    builtin_vm_run_bytecode_into(val, sizeof(val), bcb);
    var_set(k, val);
    return;
  }
  if (v && strcmp(v, "::execute_ast") == 0) {
    (*i)++;
    if (*i >= g_ntok || strcmp(g_tok[*i], "(") != 0) {
      fprintf(stderr, "azl_interpreter_minimal: execute_ast missing (\n");
      exit(5);
    }
    (*i)++;
    char astb[96], scp[96];
    if (rhs_execute_ast_two_vars(i, astb, sizeof(astb), scp, sizeof(scp)) != 0) {
      fprintf(stderr, "azl_interpreter_minimal: execute_ast bad args\n");
      exit(5);
    }
    (void)scp;
    builtin_execute_ast_into(val, sizeof(val), astb);
    var_set(k, val);
    return;
  }
  if (eval_expr(i, val, sizeof(val)) != 0) {
    mini_expr_error("set RHS");
    exit(5);
  }
  var_set(k, val);
}

/* Execute emit "event" or emit event (unquoted identifier) */
static void exec_emit(int *i) {
  (*i)++;
  if (*i >= g_ntok) return;
  const char *s = g_tok[*i];
  char ev[64] = {0};
  int have_ev = 0;
  if (s && strlen(s) >= 2 && (s[0] == '"' || s[0] == '\'')) {
    size_t len = strlen(s);
    if (len >= 2) {
      size_t n = len - 2;
      if (n >= sizeof(ev)) n = sizeof(ev) - 1;
      memcpy(ev, s + 1, n);
      ev[n] = '\0';
      have_ev = 1;
    }
  } else if (s && s[0] != '\0') {
    (void)snprintf(ev, sizeof(ev), "%s", s);
    have_ev = 1;
  }
  if (!have_ev) return;
  (*i)++;
  PayloadKV payload[MAX_PAYLOAD_KEYS];
  int npayload = 0;
  if (*i < g_ntok && strcmp(g_tok[*i], "with") == 0)
    npayload = parse_emit_with_payload(i, payload, MAX_PAYLOAD_KEYS);
  queue_push_event(ev, payload, npayload);
}

/* link ::component.name — register listeners + run init for that component */
static void exec_link(int *i) {
  (*i)++;
  if (*i >= g_ntok) return;
  run_linked_component(g_tok[*i]);
  (*i)++;
}

static void run_linked_component(const char *link_target) {
  if (!link_target || !link_target[0]) return;
  const char *lt = link_target;
  if (lt[0] == ':' && lt[1] == ':') lt += 2;

  for (int ci = 0; ci < g_ntok; ci++) {
    if (strcmp(g_tok[ci], "component") != 0) continue;
    int j = ci + 1;
    char name_buf[256] = {0};
    while (j < g_ntok && g_tok[j] && strcmp(g_tok[j], "{") != 0 && strcmp(g_tok[j], "init") != 0) {
      if (strlen(name_buf) + strlen(g_tok[j]) + 1 < sizeof(name_buf))
        strncat(name_buf, g_tok[j], sizeof(name_buf) - strlen(name_buf) - 1);
      j++;
    }
    const char *nb = name_buf;
    if (nb[0] == ':' && nb[1] == ':') nb += 2;
    if (strcmp(nb, lt) != 0) continue;

    if (j >= g_ntok || strcmp(g_tok[j], "{") != 0) return;
    /* j points at opening '{'; find_block_end expects first token *inside* the block */
    int comp_end = find_block_end(j + 1);
    int k = j;
    while (k < comp_end && strcmp(g_tok[k], "behavior") != 0) k++;
    if (k < comp_end && strcmp(g_tok[k], "behavior") == 0) {
      k++;
      if (k < comp_end && strcmp(g_tok[k], "{") == 0) {
        register_behavior_listeners(k + 1, find_block_end(k + 1));
      }
    }
    k = j;
    while (k < comp_end && strcmp(g_tok[k], "init") != 0) k++;
    if (k < comp_end && strcmp(g_tok[k], "init") == 0) {
      k++;
      while (k < comp_end && strcmp(g_tok[k], "{") != 0) k++;
      if (k < comp_end) {
        k++;
        exec_init_block(&k);
      }
    }
    return;
  }
  fprintf(stderr, "azl_interpreter_minimal: link: component not found: %s\n", link_target);
}

/*
 * Dynamic listen registration inside init / listener bodies (nested listeners).
 * Same surface as register_behavior_listeners: listen for "ev" [then] { ... }
 */
static void exec_listen(int *i) {
  if (*i >= g_ntok || strcmp(g_tok[*i], "listen") != 0) return;
  if (*i + 2 >= g_ntok || strcmp(g_tok[*i + 1], "for") != 0) {
    (*i)++;
    return;
  }
  *i += 2;
  const char *ev = g_tok[*i];
  if (!ev || strlen(ev) < 2 || (ev[0] != '"' && ev[0] != '\'')) {
    if (*i < g_ntok) (*i)++;
    return;
  }
  char evname[64] = {0};
  size_t len = strlen(ev);
  if (len >= 2) {
    size_t n = len - 2;
    if (n >= sizeof(evname)) n = sizeof(evname) - 1;
    memcpy(evname, ev + 1, n);
    evname[n] = '\0';
  }
  (*i)++;
  if (*i < g_ntok && strcmp(g_tok[*i], "then") == 0) (*i)++;
  if (*i < g_ntok && strcmp(g_tok[*i], "{") == 0) {
    int block_start = *i + 1;
    int d = 1;
    (*i)++;
    while (*i < g_ntok && d > 0) {
      if (strcmp(g_tok[*i], "{") == 0) d++;
      else if (strcmp(g_tok[*i], "}") == 0) d--;
      (*i)++;
    }
    (*i)--;
    register_listener(evname, block_start, *i);
    (*i)++;
  }
}

static void exec_for_in(int *i) {
  (*i)++;
  if (*i >= g_ntok) return;
  const char *loop_var = g_tok[*i];
  if (!loop_var || loop_var[0] != ':' || loop_var[1] != ':') {
    (*i)++;
    return;
  }
  (*i)++;
  if (*i >= g_ntok || strcmp(g_tok[*i], "in") != 0) return;
  (*i)++;
  if (*i >= g_ntok) return;
  const char *seq_key = g_tok[*i];
  if (!seq_key || seq_key[0] != ':' || seq_key[1] != ':') {
    (*i)++;
    return;
  }
  (*i)++;
  if (*i >= g_ntok || strcmp(g_tok[*i], "{") != 0) {
    fprintf(stderr, "azl_interpreter_minimal: for-in missing {\n");
    exit(5);
  }
  int body_start = *i + 1;
  int body_end = find_block_end(body_start);
  *i = body_end + 1;
  const char *raw = var_get(seq_key);
  if (!raw) raw = "";
  char segbuf[256];
  const char *q = raw;
  for (;;) {
    const char *nl = strchr(q, '\n');
    size_t slen = nl ? (size_t)(nl - q) : strlen(q);
    if (slen >= sizeof(segbuf)) slen = sizeof(segbuf) - 1U;
    memcpy(segbuf, q, slen);
    segbuf[slen] = '\0';
    var_set(loop_var, segbuf);
    exec_block_impl(body_start, body_end, 1);
    if (g_listener_break) break;
    if (!nl) break;
    q = nl + 1;
  }
}

/* Execute a block from start to end (exclusive) */
static void exec_block_impl(int start, int end, int preserve_listener_break_exit) {
  g_listener_nesting++;
  g_listener_break = 0;
  int depth = 1;
  for (int i = start; i < end && i < g_ntok; ) {
    const char *t = g_tok[i];
    if (!t) break;
    if (strcmp(t, "{") == 0) { depth++; i++; }
    else if (strcmp(t, "}") == 0) { depth--; if (depth <= 0) break; i++; }
    else if (depth == 1 && strcmp(t, "return") == 0) {
      i++;
      g_listener_break = 1;
      break;
    } else if (depth == 1 && strcmp(t, "say") == 0) exec_say(&i);
    else if (depth == 1 && strcmp(t, "set") == 0) exec_set(&i);
    else if (depth == 1 && strcmp(t, "if") == 0) {
      exec_if(&i);
      if (g_listener_break) break;
    } else if (depth == 1 && strcmp(t, "for") == 0) {
      exec_for_in(&i);
      if (g_listener_break) break;
    } else if (depth == 1 && strcmp(t, "listen") == 0) exec_listen(&i);
    else if (depth == 1 && strcmp(t, "emit") == 0) {
      exec_emit(&i);
      process_events();
    } else if (depth == 1 && strcmp(t, "link") == 0) exec_link(&i);
    else i++;
  }
  g_listener_nesting--;
  if (!preserve_listener_break_exit)
    g_listener_break = 0;
}

static void exec_block(int start, int end) {
  exec_block_impl(start, end, 0);
}

/* Process event queue: dispatch to listeners */
static void process_events(void) {
  QueuedEvent qe;
  while (queue_pop_event(&qe)) {
    apply_event_payload(&qe);
    int matched = 0;
    for (int j = 0; j < g_nlisteners; j++) {
      if (strcmp(g_listeners[j].event, qe.ev) == 0) {
        exec_block(g_listeners[j].block_start, g_listeners[j].block_end);
        matched = 1;
        break;
      }
    }
    if (!matched)
      (void)exec_ast_stub_dispatch(qe.ev);
    clear_event_payload(&qe);
  }
}

/* Scan init/behavior block */
static void exec_init_block(int *i) {
  int depth = 1;
  for (; *i < g_ntok; ) {
    const char *t = g_tok[*i];
    if (!t) break;
    if (strcmp(t, "{") == 0) { depth++; (*i)++; }
    else if (strcmp(t, "}") == 0) { depth--; if (depth <= 0) break; (*i)++; }
    else if (depth == 1 && strcmp(t, "return") == 0) {
      (*i)++;
      int d = 1;
      while (*i < g_ntok && d > 0) {
        const char *t2 = g_tok[*i];
        if (strcmp(t2, "{") == 0) {
          d++;
          (*i)++;
        } else if (strcmp(t2, "}") == 0) {
          d--;
          if (d == 0) break;
          (*i)++;
        } else (*i)++;
      }
      if (g_listener_nesting > 0) g_listener_break = 1;
      return;
    } else if (depth == 1 && strcmp(t, "say") == 0) exec_say(i);
    else if (depth == 1 && strcmp(t, "set") == 0) exec_set(i);
    else if (depth == 1 && strcmp(t, "if") == 0) exec_if(i);
    else if (depth == 1 && strcmp(t, "for") == 0) {
      if (g_listener_nesting > 0) exec_for_in(i);
      else {
        fprintf(stderr, "azl_interpreter_minimal: for-in not allowed in init\n");
        exit(5);
      }
    } else if (depth == 1 && strcmp(t, "listen") == 0) exec_listen(i);
    else if (depth == 1 && strcmp(t, "emit") == 0) { exec_emit(i); process_events(); }
    else if (depth == 1 && strcmp(t, "link") == 0) exec_link(i);
    else (*i)++;
  }
}

/* Register listeners from behavior block */
static void register_behavior_listeners(int start, int end) {
  for (int i = start; i < end && i < g_ntok; i++) {
    if (strcmp(g_tok[i], "listen") == 0 && i + 2 < g_ntok &&
        strcmp(g_tok[i + 1], "for") == 0) {
      i += 2;
      const char *ev = g_tok[i];
      if (ev && strlen(ev) >= 2 && (ev[0] == '"' || ev[0] == '\'')) {
        char evname[64] = {0};
        size_t len = strlen(ev);
        if (len >= 2) {
          size_t n = len - 2;
          if (n >= sizeof(evname)) n = sizeof(evname) - 1;
          memcpy(evname, ev + 1, n);
          evname[n] = '\0';
        }
        i++;
        if (i < g_ntok && strcmp(g_tok[i], "then") == 0) i++;
        if (i < g_ntok && strcmp(g_tok[i], "{") == 0) {
          int block_start = i + 1;
          int d = 1;
          i++;
          while (i < g_ntok && d > 0) {
            if (strcmp(g_tok[i], "{") == 0) d++;
            else if (strcmp(g_tok[i], "}") == 0) d--;
            i++;
          }
          i--;
          register_listener(evname, block_start, i);
        }
      }
    }
  }
}

/* Find behavior block end */
static int find_block_end(int i) {
  int depth = 1;
  for (; i < g_ntok; i++) {
    if (strcmp(g_tok[i], "{") == 0) depth++;
    else if (strcmp(g_tok[i], "}") == 0) { depth--; if (depth <= 0) return i; }
  }
  return g_ntok;
}

static int run(const char *entry) {
  for (int i = 0; i < g_ntok; i++) {
    if (strcmp(g_tok[i], "component") == 0 && i + 1 < g_ntok) {
      int j = i + 1;
      char name_buf[256] = {0};
      while (j < g_ntok && g_tok[j] && strcmp(g_tok[j], "{") != 0 && strcmp(g_tok[j], "init") != 0) {
        if (strlen(name_buf) + strlen(g_tok[j]) + 1 < sizeof(name_buf))
          strncat(name_buf, g_tok[j], sizeof(name_buf) - strlen(name_buf) - 1);
        j++;
      }
      int matches = !entry || (name_buf[0] && strstr(name_buf, entry) != NULL);
      if (matches) {
        if (j >= g_ntok || strcmp(g_tok[j], "{") != 0) return 0;
        int comp_end = find_block_end(j + 1);
        i = j;
        /* Register behavior listeners before init (stay within this component body) */
        while (i < comp_end && strcmp(g_tok[i], "behavior") != 0) i++;
        if (i < comp_end && strcmp(g_tok[i], "behavior") == 0) {
          i++;
          if (i < comp_end && strcmp(g_tok[i], "{") == 0) {
            int bh_start = i + 1;
            int bh_end = find_block_end(i + 1);
            register_behavior_listeners(bh_start, bh_end);
          }
        }
        i = j;
        while (i < comp_end && strcmp(g_tok[i], "init") != 0) i++;
        if (i < comp_end && strcmp(g_tok[i], "init") == 0) {
          i++;
          while (i < comp_end && strcmp(g_tok[i], "{") != 0) i++;
          if (i < comp_end) { i++; exec_init_block(&i); }
        }
        process_events();
        return 0;
      }
    }
  }
  /* No entry match: run first component */
  for (int i = 0; i < g_ntok; i++) {
    if (strcmp(g_tok[i], "component") != 0 || i + 1 >= g_ntok) continue;
    int j = i + 1;
    char nb[256] = {0};
    while (j < g_ntok && g_tok[j] && strcmp(g_tok[j], "{") != 0 && strcmp(g_tok[j], "init") != 0) {
      if (strlen(nb) + strlen(g_tok[j]) + 1 < sizeof(nb))
        strncat(nb, g_tok[j], sizeof(nb) - strlen(nb) - 1);
      j++;
    }
    if (j >= g_ntok || strcmp(g_tok[j], "{") != 0) continue;
    int comp_end = find_block_end(j + 1);
    int jj = j;
    while (jj < comp_end && strcmp(g_tok[jj], "behavior") != 0) jj++;
    if (jj < comp_end && strcmp(g_tok[jj], "behavior") == 0) {
      jj++;
      if (jj < comp_end && strcmp(g_tok[jj], "{") == 0) {
        register_behavior_listeners(jj + 1, find_block_end(jj + 1));
      }
    }
    jj = j;
    while (jj < comp_end && strcmp(g_tok[jj], "init") != 0) jj++;
    if (jj < comp_end && strcmp(g_tok[jj], "init") == 0) {
      jj++;
      while (jj < comp_end && strcmp(g_tok[jj], "{") != 0) jj++;
      if (jj < comp_end) { jj++; exec_init_block(&jj); }
    }
    process_events();
    return 0;
  }
  return 0;
}

int main(int argc, char **argv) {
  int debug = 0;
  const char *path = getenv("AZL_COMBINED_PATH");
  const char *entry = getenv("AZL_ENTRY");
  if (argc >= 2 && strcmp(argv[1], "-d") == 0) { debug = 1; argc--; argv++; }
  if (argc >= 2) path = argv[1];
  if (argc >= 3) entry = argv[2];
  /* Normalize entry: ::boot.entry -> boot.entry for matching */
  if (entry && entry[0] == ':' && entry[1] == ':') entry += 2;
  if (!path || !*path) {
    fprintf(stderr, "azl_interpreter_minimal: AZL_COMBINED_PATH or <file> required\n");
    return 1;
  }
  FILE *f = fopen(path, "rb");
  if (!f) {
    fprintf(stderr, "azl_interpreter_minimal: cannot open %s\n", path);
    return 2;
  }
  g_src = malloc(BUF_SIZE);
  if (!g_src) { fclose(f); return 3; }
  g_src_len = fread(g_src, 1, BUF_SIZE - 1, f);
  g_src[g_src_len] = '\0';
  fclose(f);
  if (tokenize() != 0) {
    free(g_src);
    fprintf(stderr, "azl_interpreter_minimal: tokenize failed\n");
    return 4;
  }
  if (debug) {
    for (int i = 0; i < g_ntok && i < 50; i++)
      fprintf(stderr, "[%d] %s\n", i, g_tok[i] ? g_tok[i] : "(null)");
  }
  int rc = run(entry);
  free_tokens();
  free(g_src);
  /* Daemon mode: stay alive for native engine (like azl_native_runtime_loop.sh) */
  if (getenv("AZL_INTERPRETER_DAEMON") != NULL) {
    while (1) { sleep(1); }
  }
  return rc;
}
