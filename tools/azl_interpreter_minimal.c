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

static int next_token(const char **p, char *out, size_t out_sz) {
  skip_whitespace_and_comments(p);
  if (!**p) return 0;
  const char *start = *p;
  if (*start == '"' || *start == '\'') {
    char q = *start++;
    size_t i = 0;
    while (*start && *start != q && i + 1 < out_sz) {
      if (*start == '\\') start++;
      out[i++] = *start++;
    }
    out[i] = '\0';
    if (*start == q) start++;
    *p = start;
    return 1;
  }
  if (isalnum((unsigned char)*start) || *start == '_' || *start == ':') {
    size_t i = 0;
    while (*start && (isalnum((unsigned char)*start) || *start == '_' || *start == '.' || *start == ':') && i + 1 < out_sz)
      out[i++] = *start++;
    out[i] = '\0';
    *p = start;
    return 1;
  }
  if (*start == '{' || *start == '}' || *start == '(' || *start == ')' || *start == ';' || *start == '=' || *start == ',' || *start == '[' || *start == ']') {
    out[0] = *start;
    out[1] = '\0';
    (*p)++;
    return 1;
  }
  (*p)++;
  return 0;
}

static int tokenize(void) {
  char tok[256];
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
    if (*p == '{' || *p == '}' || *p == '(' || *p == ')' || *p == ';' || *p == '=' || *p == ',' || *p == '[' || *p == ']') {
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
      strncpy(g_vars[i].v, v, sizeof(g_vars[i].v) - 1);
      g_vars[i].v[sizeof(g_vars[i].v) - 1] = '\0';
      return;
    }
  if (g_nvars < MAX_VARS) {
    strncpy(g_vars[g_nvars].k, k, sizeof(g_vars[g_nvars].k) - 1);
    g_vars[g_nvars].k[sizeof(g_vars[g_nvars].k) - 1] = '\0';
    strncpy(g_vars[g_nvars].v, v, sizeof(g_vars[g_nvars].v) - 1);
    g_vars[g_nvars].v[sizeof(g_vars[g_nvars].v) - 1] = '\0';
    g_nvars++;
  }
}
static void queue_push(const char *ev) {
  if ((g_queue_tail + 1) % MAX_EVENTS != g_queue_head) {
    strncpy(g_event_queue[g_queue_tail], ev, 63);
    g_event_queue[g_queue_tail][63] = '\0';
    g_queue_tail = (g_queue_tail + 1) % MAX_EVENTS;
  }
}
static int queue_pop(char *ev) {
  if (g_queue_head == g_queue_tail) return 0;
  strncpy(ev, g_event_queue[g_queue_head], 63);
  ev[63] = '\0';
  g_queue_head = (g_queue_head + 1) % MAX_EVENTS;
  return 1;
}
static void register_listener(const char *ev, int start, int end) {
  if (g_nlisteners < MAX_LISTENERS) {
    strncpy(g_listeners[g_nlisteners].event, ev, 63);
    g_listeners[g_nlisteners].event[63] = '\0';
    g_listeners[g_nlisteners].block_start = start;
    g_listeners[g_nlisteners].block_end = end;
    g_nlisteners++;
  }
}

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
  if (v && strlen(v) >= 2 && (v[0] == '"' || v[0] == '\'')) {
    size_t len = strlen(v);
    if (len >= 2) {
      size_t n = len - 2;
      if (n >= sizeof(val)) n = sizeof(val) - 1;
      memcpy(val, v + 1, n);
      val[n] = '\0';
    }
  } else if (v && (isdigit((unsigned char)v[0]) || (v[0] == '-' && v[1]))) {
    strncpy(val, v, sizeof(val) - 1);
  } else if (v && v[0] == ':' && v[1] == ':') {
    const char *vv = var_get(v);
    if (vv) strncpy(val, vv, sizeof(val) - 1);
  } else if (v) {
    strncpy(val, v, sizeof(val) - 1);
  }
  var_set(k, val);
  (*i)++;
}

/* Execute emit "event" */
static void exec_emit(int *i) {
  (*i)++;
  if (*i >= g_ntok) return;
  const char *s = g_tok[*i];
  if (s && strlen(s) >= 2 && (s[0] == '"' || s[0] == '\'')) {
    char ev[64] = {0};
    size_t len = strlen(s);
    if (len >= 2) {
      size_t n = len - 2;
      if (n >= sizeof(ev)) n = sizeof(ev) - 1;
      memcpy(ev, s + 1, n);
      ev[n] = '\0';
    }
    queue_push(ev);
  }
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
    else if (depth == 1 && strcmp(t, "emit") == 0) exec_emit(&i);
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
    else if (depth == 1 && strcmp(t, "emit") == 0) { exec_emit(i); process_events(); }
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
        i = j;
        /* Register behavior listeners before init */
        while (i < g_ntok && strcmp(g_tok[i], "behavior") != 0) i++;
        if (i < g_ntok && strcmp(g_tok[i], "behavior") == 0) {
          i++;
          if (i < g_ntok && strcmp(g_tok[i], "{") == 0) {
            int bh_start = i + 1;
            int bh_end = find_block_end(i + 1);
            register_behavior_listeners(bh_start, bh_end);
          }
        }
        i = j;
        while (i < g_ntok && strcmp(g_tok[i], "init") != 0) i++;
        if (i < g_ntok && strcmp(g_tok[i], "init") == 0) {
          i++;
          while (i < g_ntok && strcmp(g_tok[i], "{") != 0) i++;
          if (i < g_ntok) { i++; exec_init_block(&i); }
        }
        process_events();
        return 0;
      }
    }
  }
  /* No entry match: run first component */
  for (int i = 0; i < g_ntok; i++) {
    if (strcmp(g_tok[i], "component") == 0 && i + 1 < g_ntok) {
      int j = i + 1;
      while (j < g_ntok && strcmp(g_tok[j], "behavior") != 0) j++;
      if (j < g_ntok && strcmp(g_tok[j], "behavior") == 0) {
        j++;
        if (j < g_ntok && strcmp(g_tok[j], "{") == 0) {
          register_behavior_listeners(j + 1, find_block_end(j + 1));
        }
      }
      j = i + 1;
      while (j < g_ntok && strcmp(g_tok[j], "init") != 0) j++;
      if (j < g_ntok && strcmp(g_tok[j], "init") == 0) {
        j++;
        while (j < g_ntok && strcmp(g_tok[j], "{") != 0) j++;
        if (j < g_ntok) { j++; exec_init_block(&j); }
      }
      process_events();
      return 0;
    }
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
