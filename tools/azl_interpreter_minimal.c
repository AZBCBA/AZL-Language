/*
 * AZL Minimal C Interpreter - Phase 1 Skeleton
 * Proof-of-concept: parses and executes a tiny AZL subset.
 * Extensible foundation for full C-based AZL execution.
 *
 * Usage: azl_interpreter_minimal <file.azl> [entry_component]
 * Env: AZL_COMBINED_PATH, AZL_ENTRY
 */

#define _GNU_SOURCE
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define BUF_SIZE  (2 * 1024 * 1024)   /* 2MB for enterprise combined files */
#define MAX_TOKS  65536
#define MAX_VARS  256
#define MAX_LISTENERS 64
#define MAX_EVENTS 32

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

/* Event queue for dispatch */
static char g_event_queue[MAX_EVENTS][64];
static int g_queue_head, g_queue_tail;

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
    if (*p == '{' || *p == '}' || *p == '(' || *p == ')' || *p == ';' || *p == '=' || *p == ',' || *p == '[' || *p == ']' || *p == '!') {
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
static void queue_push(const char *ev) {
  if ((g_queue_tail + 1) % MAX_EVENTS != g_queue_head) {
    (void)snprintf(g_event_queue[g_queue_tail], sizeof(g_event_queue[g_queue_tail]), "%s",
                   ev ? ev : "");
    g_queue_tail = (g_queue_tail + 1) % MAX_EVENTS;
  }
}
static int queue_pop(char *ev) {
  if (g_queue_head == g_queue_tail) return 0;
  (void)snprintf(ev, 64, "%s", g_event_queue[g_queue_head]);
  g_queue_head = (g_queue_head + 1) % MAX_EVENTS;
  return 1;
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

/* Execute say "string" or say ::var - print to stdout */
static void exec_say(int *i) {
  (*i)++;
  if (*i >= g_ntok) return;
  const char *s = g_tok[*i];
  if (s && strlen(s) >= 2 && (s[0] == '"' || s[0] == '\'')) {
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

static void mini_expr_error(const char *ctx) {
  fprintf(stderr, "azl_interpreter_minimal: expression error: %s\n", ctx ? ctx : "parse");
}

static int values_eq(int l_nullish, const char *l, int r_nullish, const char *r) {
  if (l_nullish && r_nullish) return 1;
  if (l_nullish || r_nullish) return 0;
  return strcmp(l, r) == 0;
}

static int eval_primary(int *i, char *out, size_t outsz, int *nullish);

static int eval_eq(int *i, char *out, size_t outsz, int *nullish_out) {
  char left[256], right[256];
  int ln = 0, rn = 0;
  if (eval_primary(i, left, sizeof(left), &ln) != 0) return -1;
  if (*i >= g_ntok ||
      (strcmp(g_tok[*i], "==") != 0 && strcmp(g_tok[*i], "!=") != 0)) {
    (void)snprintf(out, outsz, "%s", left);
    *nullish_out = ln;
    return 0;
  }
  const char *op = g_tok[*i];
  (*i)++;
  if (eval_primary(i, right, sizeof(right), &rn) != 0) return -1;
  int eq = values_eq(ln, left, rn, right);
  if (strcmp(op, "!=") == 0) eq = !eq;
  (void)snprintf(out, outsz, "%s", eq ? "true" : "false");
  *nullish_out = 0;
  return 0;
}

static int eval_or(int *i, char *out, size_t outsz) {
  char acc[256];
  int acc_nullish = 0;
  if (eval_eq(i, acc, sizeof(acc), &acc_nullish) != 0) return -1;
  while (*i < g_ntok && strcmp(g_tok[*i], "or") == 0) {
    (*i)++;
    char next[256];
    int nn = 0;
    if (eval_eq(i, next, sizeof(next), &nn) != 0) return -1;
    int use_right = (acc_nullish || acc[0] == '\0');
    if (use_right) {
      (void)snprintf(acc, sizeof(acc), "%s", next);
      acc_nullish = nn;
    }
  }
  (void)snprintf(out, outsz, "%s", acc);
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
    *nullish = 0;
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
    const char *vv = var_get(t);
    if (!vv) *nullish = 1;
    else (void)snprintf(out, outsz, "%s", vv);
    (*i)++;
    return 0;
  }

  return -1;
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

/* Execute set ::var = value */
static void exec_set(int *i) {
  (*i)++;
  if (*i >= g_ntok) return;
  const char *k = g_tok[*i];
  if (!k || k[0] != ':' || k[1] != ':') { (*i)++; return; }
  (*i)++;
  if (*i >= g_ntok || strcmp(g_tok[*i], "=") != 0) return;
  (*i)++;
  if (*i >= g_ntok) return;
  const char *v = g_tok[*i];
  char val[256] = {0};
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
  queue_push(ev);
  (*i)++;
  /* Skip "with" { ... } if present */
  if (*i < g_ntok && strcmp(g_tok[*i], "with") == 0) {
    (*i)++;
    if (*i < g_ntok && strcmp(g_tok[*i], "{") == 0) {
      int d = 1;
      (*i)++;
      while (*i < g_ntok && d > 0) {
        if (strcmp(g_tok[*i], "{") == 0) d++;
        else if (strcmp(g_tok[*i], "}") == 0) d--;
        (*i)++;
      }
    }
  }
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

/* Execute a block from start to end (exclusive) */
static void exec_block(int start, int end) {
  int depth = 1;
  for (int i = start; i < end && i < g_ntok; ) {
    const char *t = g_tok[i];
    if (!t) break;
    if (strcmp(t, "{") == 0) { depth++; i++; }
    else if (strcmp(t, "}") == 0) { depth--; if (depth <= 0) break; i++; }
    else if (depth == 1 && strcmp(t, "say") == 0) exec_say(&i);
    else if (depth == 1 && strcmp(t, "set") == 0) exec_set(&i);
    else if (depth == 1 && strcmp(t, "if") == 0) exec_if(&i);
    else if (depth == 1 && strcmp(t, "emit") == 0) exec_emit(&i);
    else if (depth == 1 && strcmp(t, "link") == 0) exec_link(&i);
    else i++;
  }
}

/* Process event queue: dispatch to listeners */
static void process_events(void) {
  char ev[64];
  while (queue_pop(ev)) {
    for (int j = 0; j < g_nlisteners; j++) {
      if (strcmp(g_listeners[j].event, ev) == 0) {
        exec_block(g_listeners[j].block_start, g_listeners[j].block_end);
        break;
      }
    }
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
    else if (depth == 1 && strcmp(t, "say") == 0) exec_say(i);
    else if (depth == 1 && strcmp(t, "set") == 0) exec_set(i);
    else if (depth == 1 && strcmp(t, "if") == 0) exec_if(i);
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
