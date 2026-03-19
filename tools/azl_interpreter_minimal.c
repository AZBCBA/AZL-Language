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

#define BUF_SIZE  (256 * 1024)
#define TOK_SIZE  4096
#define MAX_TOKS  16384

static char *g_src;
static size_t g_src_len;
static const char *g_tok[MAX_TOKS];
static int g_ntok;

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

/* Execute say "string" - print to stdout */
static void exec_say(int *i) {
  (*i)++;
  if (*i >= g_ntok) return;
  const char *s = g_tok[*i];
  if (s && strlen(s) >= 2 && (s[0] == '"' || s[0] == '\'')) {
    size_t len = strlen(s);
    fwrite(s + 1, 1, len - 2, stdout);
    fputc('\n', stdout);
    fflush(stdout);
  }
  (*i)++;
}

/* Scan init block for say statements */
static void exec_init_block(int *i) {
  int depth = 1;  /* we're inside the init { already */
  for (; *i < g_ntok; ) {
    const char *t = g_tok[*i];
    if (!t) break;
    if (strcmp(t, "{") == 0) { depth++; (*i)++; }
    else if (strcmp(t, "}") == 0) { depth--; if (depth <= 0) break; (*i)++; }
    else if (depth == 1 && strcmp(t, "say") == 0) exec_say(i);  /* exec_say advances i */
    else (*i)++;
  }
}

static int run(const char *entry) {
  for (int i = 0; i < g_ntok; i++) {
    if (strcmp(g_tok[i], "component") == 0 && i + 1 < g_ntok) {
      /* Component name may be ::boot.entry (one token) or :: boot . entry (many) */
      int j = i + 1;
      char name_buf[256] = {0};
      while (j < g_ntok && g_tok[j] && strcmp(g_tok[j], "{") != 0 && strcmp(g_tok[j], "init") != 0) {
        size_t len = strlen(g_tok[j]);
        if (strlen(name_buf) + len + 1 < sizeof(name_buf))
          strncat(name_buf, g_tok[j], sizeof(name_buf) - strlen(name_buf) - 1);
        j++;
      }
      int matches = !entry || (name_buf[0] && strstr(name_buf, entry) != NULL);
      if (matches) {
        i = j;
        while (i < g_ntok && strcmp(g_tok[i], "init") != 0) i++;
        if (i < g_ntok && strcmp(g_tok[i], "init") == 0) {
          i++;
          while (i < g_ntok && strcmp(g_tok[i], "{") != 0) i++;
          if (i < g_ntok) { i++; exec_init_block(&i); }
        }
        return 0;
      }
    }
  }
  /* No entry match: run first component's init */
  for (int i = 0; i < g_ntok; i++) {
    if (strcmp(g_tok[i], "component") == 0 && i + 1 < g_ntok) {
      i++;
      while (i < g_ntok && strcmp(g_tok[i], "init") != 0) i++;
      if (i < g_ntok && strcmp(g_tok[i], "init") == 0) {
        i++;
        while (i < g_ntok && strcmp(g_tok[i], "{") != 0) i++;
        if (i < g_ntok) { i++; exec_init_block(&i); }
      }
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
