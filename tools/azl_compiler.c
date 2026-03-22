/* Minimal AZL scanner + recursive-descent compiler → AzlBytecodeProgram (no JSON). */
#define _GNU_SOURCE
#include "azl_compiler.h"

#include "azl_core_engine.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  const char *s;
  size_t n;
  size_t i;
  unsigned line;
} Lex;

typedef enum {
  TK_EOF = 0,
  TK_EMIT,
  TK_LISTEN,
  TK_FOR,
  TK_SET,
  TK_IF,
  TK_ELSE,
  TK_IDENT,
  TK_STRING,
  TK_LBRACE,
  TK_RBRACE,
  TK_LPAREN,
  TK_RPAREN,
  TK_COLON,
  TK_COMMA,
  TK_EQEQ,
  TK_ASSIGN,
  TK_ILLEGAL,
} TkKind;

typedef struct {
  TkKind k;
  char text[AZL_BC_STR_MAX];
} Tok;

static void lex_skip_ws_comments(Lex *L) {
  for (;;) {
    while (L->i < L->n && (L->s[L->i] == ' ' || L->s[L->i] == '\t' || L->s[L->i] == '\r' || L->s[L->i] == '\n')) {
      if (L->s[L->i] == '\n')
        L->line++;
      L->i++;
    }
    if (L->i < L->n && L->s[L->i] == '#') {
      while (L->i < L->n && L->s[L->i] != '\n')
        L->i++;
      continue;
    }
    break;
  }
}

static int lex_string(Lex *L, char *out, size_t outs) {
  if (L->i >= L->n || L->s[L->i] != '"')
    return -1;
  L->i++;
  size_t w = 0;
  while (L->i < L->n && L->s[L->i] != '"') {
    if (L->s[L->i] == '\\' && L->i + 1 < L->n) {
      L->i++;
      char c = L->s[L->i++];
      if (c == 'n')
        c = '\n';
      else if (c == 't')
        c = '\t';
      else if (c == 'r')
        c = '\r';
      if (w + 1 < outs)
        out[w++] = c;
    } else {
      if (w + 1 < outs)
        out[w++] = L->s[L->i++];
    }
  }
  if (L->i >= L->n || L->s[L->i] != '"')
    return -1;
  L->i++;
  if (outs > 0)
    out[w < outs ? w : outs - 1] = '\0';
  return 0;
}

static int is_ident_start(char c) {
  return (unsigned char)(c - 'a') <= 25u || (unsigned char)(c - 'A') <= 25u || c == '_' || c == ':';
}

static int is_ident_cont(char c) {
  return is_ident_start(c) || (unsigned char)(c - '0') <= 9u || c == '.';
}

static void lex_next(Lex *L, Tok *t) {
  memset(t, 0, sizeof(*t));
  lex_skip_ws_comments(L);
  if (L->i >= L->n) {
    t->k = TK_EOF;
    return;
  }
  char c = L->s[L->i];
  if (c == '{') {
    L->i++;
    t->k = TK_LBRACE;
    return;
  }
  if (c == '}') {
    L->i++;
    t->k = TK_RBRACE;
    return;
  }
  if (c == ':') {
    L->i++;
    t->k = TK_COLON;
    return;
  }
  if (c == ',') {
    L->i++;
    t->k = TK_COMMA;
    return;
  }
  if (c == '(') {
    L->i++;
    t->k = TK_LPAREN;
    return;
  }
  if (c == ')') {
    L->i++;
    t->k = TK_RPAREN;
    return;
  }
  if (c == '=') {
    if (L->i + 1u < L->n && L->s[L->i + 1u] == '=') {
      L->i += 2u;
      t->k = TK_EQEQ;
      return;
    }
    L->i++;
    t->k = TK_ASSIGN;
    return;
  }
  if (c == '"') {
    if (lex_string(L, t->text, sizeof(t->text)) != 0) {
      t->k = TK_ILLEGAL;
      return;
    }
    t->k = TK_STRING;
    return;
  }
  if (is_ident_start(c)) {
    size_t w = 0;
    while (L->i < L->n && is_ident_cont(L->s[L->i]) && w + 1 < sizeof(t->text))
      t->text[w++] = L->s[L->i++];
    t->text[w] = '\0';
    if (strcmp(t->text, "emit") == 0)
      t->k = TK_EMIT;
    else if (strcmp(t->text, "listen") == 0)
      t->k = TK_LISTEN;
    else if (strcmp(t->text, "for") == 0)
      t->k = TK_FOR;
    else if (strcmp(t->text, "set") == 0)
      t->k = TK_SET;
    else if (strcmp(t->text, "if") == 0)
      t->k = TK_IF;
    else if (strcmp(t->text, "else") == 0)
      t->k = TK_ELSE;
    else
      t->k = TK_IDENT;
    return;
  }
  t->k = TK_ILLEGAL;
}

#define AZL_COMPILER_MAX_LOCALS 32

typedef struct {
  char name[AZL_BC_STR_MAX];
  int slot;
} LocalEnt;

typedef struct {
  Lex lex;
  Tok cur;
  AzlBytecodeProgram *out;
  char *err;
  size_t err_sz;
  int ctrue;
  int cfalse;
  LocalEnt locals[AZL_COMPILER_MAX_LOCALS];
  int nlocals;
} Parse;

static void parse_bump(Parse *p) { lex_next(&p->lex, &p->cur); }

static void parse_err(Parse *p, const char *msg) {
  if (p->err && p->err_sz)
    snprintf(p->err, p->err_sz, "line %u: %s", p->lex.line, msg);
}

static int add_const(Parse *p, const char *s) {
  if (!p->out || p->out->nconst >= AZL_BC_CONST_MAX) {
    parse_err(p, "const pool full");
    return -1;
  }
  strncpy(p->out->consts[p->out->nconst], s, AZL_BC_STR_MAX - 1u);
  p->out->consts[p->out->nconst][AZL_BC_STR_MAX - 1u] = '\0';
  return (int)p->out->nconst++;
}

static int add_insn(Parse *p, const AzlBytecodeInstr *in) {
  if (!p->out || p->out->ncode >= AZL_BC_CODE_MAX) {
    parse_err(p, "code buffer full");
    return -1;
  }
  p->out->code[p->out->ncode++] = *in;
  return 0;
}

static int parse_expect(Parse *p, TkKind want) {
  if (p->cur.k != want) {
    parse_err(p, "unexpected token");
    return -1;
  }
  parse_bump(p);
  return 0;
}

static int local_find(Parse *p, const char *name) {
  for (int i = 0; i < p->nlocals; i++) {
    if (strcmp(p->locals[i].name, name) == 0)
      return p->locals[i].slot;
  }
  return -1;
}

static int local_alloc(Parse *p, const char *name) {
  int f = local_find(p, name);
  if (f >= 0)
    return f;
  if (p->nlocals >= AZL_COMPILER_MAX_LOCALS) {
    parse_err(p, "too many locals");
    return -1;
  }
  snprintf(p->locals[p->nlocals].name, sizeof(p->locals[0].name), "%s", name);
  p->locals[p->nlocals].slot = p->nlocals;
  p->nlocals++;
  return p->locals[p->nlocals - 1].slot;
}

/* Push string or local onto stack (for comparisons). */
static int parse_primary_load(Parse *p) {
  if (p->cur.k == TK_STRING) {
    int ix = add_const(p, p->cur.text);
    if (ix < 0)
      return -1;
    parse_bump(p);
    AzlBytecodeInstr ins = {AZL_OP_LOAD_CONST, (uint32_t)ix, 0, 0};
    return add_insn(p, &ins);
  }
  if (p->cur.k == TK_IDENT) {
    int sl = local_find(p, p->cur.text);
    if (sl < 0) {
      parse_err(p, "unknown variable");
      return -1;
    }
    parse_bump(p);
    AzlBytecodeInstr ins = {AZL_OP_LOAD_VAR, (uint32_t)sl, 0, 0};
    return add_insn(p, &ins);
  }
  parse_err(p, "expected string or identifier");
  return -1;
}

static int parse_cmp_expr(Parse *p) {
  if (parse_primary_load(p) != 0)
    return -1;
  if (parse_expect(p, TK_EQEQ) != 0)
    return -1;
  if (parse_primary_load(p) != 0)
    return -1;
  if (p->ctrue < 0 || p->cfalse < 0) {
    parse_err(p, "internal: missing true/false consts");
    return -1;
  }
  AzlBytecodeInstr eq = {AZL_OP_EQ, (uint32_t)p->ctrue, (uint32_t)p->cfalse, 0};
  return add_insn(p, &eq);
}

static int parse_set_stmt(Parse *p) {
  if (parse_expect(p, TK_SET) != 0)
    return -1;
  if (p->cur.k != TK_IDENT) {
    parse_err(p, "expected identifier after set");
    return -1;
  }
  char name[AZL_BC_STR_MAX];
  strncpy(name, p->cur.text, sizeof(name) - 1u);
  name[sizeof(name) - 1u] = '\0';
  parse_bump(p);
  if (parse_expect(p, TK_ASSIGN) != 0)
    return -1;
  if (p->cur.k != TK_STRING) {
    parse_err(p, "expected string value");
    return -1;
  }
  int v = add_const(p, p->cur.text);
  if (v < 0)
    return -1;
  parse_bump(p);
  int slot = local_alloc(p, name);
  if (slot < 0)
    return -1;
  AzlBytecodeInstr lc = {AZL_OP_LOAD_CONST, (uint32_t)v, 0, 0};
  AzlBytecodeInstr st = {AZL_OP_STORE_VAR, (uint32_t)slot, 0, 0};
  if (add_insn(p, &lc) != 0 || add_insn(p, &st) != 0)
    return -1;
  return 0;
}

static int parse_stmt(Parse *p);
static int parse_emit_stmt(Parse *p);

static int parse_if_stmt(Parse *p) {
  if (parse_expect(p, TK_IF) != 0)
    return -1;
  if (parse_expect(p, TK_LPAREN) != 0)
    return -1;
  if (parse_cmp_expr(p) != 0)
    return -1;
  if (parse_expect(p, TK_RPAREN) != 0)
    return -1;
  size_t jif_at = p->out->ncode;
  AzlBytecodeInstr jif = {AZL_OP_JUMP_IF_FALSE, 0u, (uint32_t)p->cfalse, 0};
  if (add_insn(p, &jif) != 0)
    return -1;
  if (parse_expect(p, TK_LBRACE) != 0)
    return -1;
  while (p->cur.k != TK_RBRACE && p->cur.k != TK_EOF) {
    if (parse_stmt(p) != 0)
      return -1;
  }
  if (parse_expect(p, TK_RBRACE) != 0)
    return -1;
  if (p->cur.k == TK_ELSE) {
    parse_bump(p);
    size_t jmp_over = p->out->ncode;
    AzlBytecodeInstr ju = {AZL_OP_JUMP, 0u, 0, 0};
    if (add_insn(p, &ju) != 0)
      return -1;
    p->out->code[jif_at].a = (uint32_t)p->out->ncode;
    if (parse_expect(p, TK_LBRACE) != 0)
      return -1;
    while (p->cur.k != TK_RBRACE && p->cur.k != TK_EOF) {
      if (parse_stmt(p) != 0)
        return -1;
    }
    if (parse_expect(p, TK_RBRACE) != 0)
      return -1;
    p->out->code[jmp_over].a = (uint32_t)p->out->ncode;
  } else {
    p->out->code[jif_at].a = (uint32_t)p->out->ncode;
  }
  return 0;
}

static int parse_stmt(Parse *p) {
  if (p->cur.k == TK_EMIT)
    return parse_emit_stmt(p);
  if (p->cur.k == TK_SET)
    return parse_set_stmt(p);
  if (p->cur.k == TK_IF)
    return parse_if_stmt(p);
  if (p->cur.k == TK_ILLEGAL) {
    parse_err(p, "illegal token");
    return -1;
  }
  parse_err(p, "unsupported statement (use emit, set, or if)");
  return -1;
}

/* emit STRING { STRING : STRING (, STRING : STRING)* } */
static int parse_emit_stmt(Parse *p) {
  if (parse_expect(p, TK_EMIT) != 0)
    return -1;
  if (p->cur.k != TK_STRING) {
    parse_err(p, "expected event string after emit");
    return -1;
  }
  int ev = add_const(p, p->cur.text);
  if (ev < 0)
    return -1;
  parse_bump(p);
  if (parse_expect(p, TK_LBRACE) != 0)
    return -1;
  int first = 1;
  for (;;) {
    if (p->cur.k == TK_RBRACE) {
      parse_bump(p);
      break;
    }
    if (!first) {
      if (p->cur.k != TK_COMMA) {
        parse_err(p, "expected ',' or '}'");
        return -1;
      }
      parse_bump(p);
    }
    first = 0;
    if (p->cur.k != TK_STRING) {
      parse_err(p, "expected key string");
      return -1;
    }
    int ki = add_const(p, p->cur.text);
    if (ki < 0)
      return -1;
    parse_bump(p);
    if (parse_expect(p, TK_COLON) != 0)
      return -1;
    if (p->cur.k != TK_STRING) {
      parse_err(p, "expected value string");
      return -1;
    }
    int vi = add_const(p, p->cur.text);
    if (vi < 0)
      return -1;
    parse_bump(p);
    AzlBytecodeInstr ins = {AZL_OP_EMIT, (uint32_t)ev, (uint32_t)ki, (uint32_t)vi};
    if (add_insn(p, &ins) != 0)
      return -1;
  }
  return 0;
}

static int parse_program(Parse *p) {
  memset(p->locals, 0, sizeof(p->locals));
  p->nlocals = 0;
  p->ctrue = -1;
  p->cfalse = -1;
  parse_bump(p);
  p->ctrue = add_const(p, "true");
  p->cfalse = add_const(p, "false");
  if (p->ctrue < 0 || p->cfalse < 0)
    return -1;
  while (p->cur.k != TK_EOF) {
    if (parse_stmt(p) != 0)
      return -1;
  }
  AzlBytecodeInstr halt = {AZL_OP_HALT, 0, 0, 0};
  if (add_insn(p, &halt) != 0)
    return -1;
  return 0;
}

static int program_alloc_empty(AzlBytecodeProgram *out) {
  azl_bytecode_program_destroy(out);
  out->consts = (char (*)[AZL_BC_STR_MAX])calloc(AZL_BC_CONST_MAX, AZL_BC_STR_MAX);
  out->code = (AzlBytecodeInstr *)calloc(AZL_BC_CODE_MAX, sizeof(AzlBytecodeInstr));
  if (!out->consts || !out->code) {
    azl_bytecode_program_destroy(out);
    return -1;
  }
  out->nconst = 0;
  out->ncode = 0;
  return 0;
}

int azl_compile_source(const char *src, size_t src_len, AzlBytecodeProgram *out, char *errbuf, size_t errbuf_sz) {
  if (!src || !out) {
    if (errbuf && errbuf_sz)
      snprintf(errbuf, errbuf_sz, "null argument");
    return -1;
  }
  if (program_alloc_empty(out) != 0) {
    if (errbuf && errbuf_sz)
      snprintf(errbuf, errbuf_sz, "oom");
    return -1;
  }
  Parse p;
  memset(&p, 0, sizeof(p));
  p.lex.s = src;
  p.lex.n = src_len;
  p.lex.i = 0;
  p.lex.line = 1u;
  p.out = out;
  p.err = errbuf;
  p.err_sz = errbuf_sz;
  if (parse_program(&p) != 0) {
    azl_bytecode_program_destroy(out);
    return -1;
  }
  return 0;
}

int azl_compile_file(const char *path, AzlBytecodeProgram *out, char *errbuf, size_t errbuf_sz) {
  if (!path || !out) {
    if (errbuf && errbuf_sz)
      snprintf(errbuf, errbuf_sz, "null argument");
    return -1;
  }
  FILE *f = fopen(path, "rb");
  if (!f) {
    if (errbuf && errbuf_sz)
      snprintf(errbuf, errbuf_sz, "cannot open %s", path);
    return -1;
  }
  char buf[65536];
  size_t n = fread(buf, 1, sizeof(buf) - 1u, f);
  fclose(f);
  buf[n] = '\0';
  return azl_compile_source(buf, n, out, errbuf, errbuf_sz);
}

static const char *cmp_payload(const AzlEvent *ev, const char *key) {
  if (!ev || !key)
    return NULL;
  for (const AzlPayloadKV *q = ev->payload; q; q = q->next) {
    if (q->key && strcmp(q->key, key) == 0)
      return q->value ? q->value : "";
  }
  return NULL;
}

static int g_cmp_ok;
static int g_branch_ok;

static void cmp_on_hello(AzlEngine *eng, const AzlEvent *ev, void *ud) {
  (void)eng;
  (void)ud;
  const char *m = cmp_payload(ev, "message");
  if (m && strcmp(m, "Hello World") == 0)
    g_cmp_ok = 1;
}

static void cmp_on_success(AzlEngine *eng, const AzlEvent *ev, void *ud) {
  (void)eng;
  (void)ud;
  const char *r = cmp_payload(ev, "result");
  if (r && strcmp(r, "yes") == 0)
    g_branch_ok = 1;
}

int azl_compiler_selftest(void) {
  static const char src[] = "emit \"hello\" { \"message\": \"Hello World\" }\n";
  AzlBytecodeProgram prog;
  azl_bytecode_program_init_empty(&prog);
  char err[256];
  if (azl_compile_source(src, strlen(src), &prog, err, sizeof(err)) != 0) {
    fprintf(stderr, "azl_compiler_selftest: compile failed: %s\n", err);
    return -1;
  }
  AzlEngine *e = azl_engine_create((size_t)1u << 16, 1024u, 64u);
  if (!e) {
    azl_bytecode_program_destroy(&prog);
    return -1;
  }
  g_cmp_ok = 0;
  azl_engine_register_listener(e, "hello", cmp_on_hello, NULL);
  if (azl_vm_exec_block(e, &prog) != AZL_OK) {
    fprintf(stderr, "azl_compiler_selftest: vm_exec failed\n");
    azl_engine_destroy(e);
    azl_bytecode_program_destroy(&prog);
    return -1;
  }
  if (!g_cmp_ok) {
    fprintf(stderr, "azl_compiler_selftest: listener did not observe Hello World\n");
    azl_engine_destroy(e);
    azl_bytecode_program_destroy(&prog);
    return -1;
  }
  /* File round-trip */
  azl_bytecode_program_destroy(&prog);
  const char *paths[] = {"tools/testdata/vm_hello.azl", "testdata/vm_hello.azl", NULL};
  FILE *f = NULL;
  const char *used = NULL;
  for (int i = 0; paths[i]; i++) {
    f = fopen(paths[i], "rb");
    if (f) {
      used = paths[i];
      break;
    }
  }
  if (!f) {
    fprintf(stderr, "azl_compiler_selftest: vm_hello.azl not found\n");
    azl_engine_destroy(e);
    return -1;
  }
  char fbuf[4096];
  size_t fn = fread(fbuf, 1, sizeof(fbuf) - 1u, f);
  fclose(f);
  fbuf[fn] = '\0';
  if (azl_compile_source(fbuf, fn, &prog, err, sizeof(err)) != 0) {
    fprintf(stderr, "azl_compiler_selftest: file compile failed: %s\n", err);
    azl_engine_destroy(e);
    return -1;
  }
  g_cmp_ok = 0;
  if (azl_vm_exec_block(e, &prog) != AZL_OK) {
    fprintf(stderr, "azl_compiler_selftest: file vm_exec failed\n");
    azl_engine_destroy(e);
    azl_bytecode_program_destroy(&prog);
    return -1;
  }
  azl_bytecode_program_destroy(&prog);
  if (!g_cmp_ok) {
    fprintf(stderr, "azl_compiler_selftest: file run did not observe Hello World\n");
    azl_engine_destroy(e);
    return -1;
  }

  const char *branch_paths[] = {"tools/testdata/vm_branch.azl", "testdata/vm_branch.azl", NULL};
  FILE *bf = NULL;
  const char *bused = NULL;
  for (int i = 0; branch_paths[i]; i++) {
    bf = fopen(branch_paths[i], "rb");
    if (bf) {
      bused = branch_paths[i];
      break;
    }
  }
  if (!bf) {
    fprintf(stderr, "azl_compiler_selftest: vm_branch.azl not found\n");
    azl_engine_destroy(e);
    return -1;
  }
  char bbuf[4096];
  size_t bn = fread(bbuf, 1, sizeof(bbuf) - 1u, bf);
  fclose(bf);
  bbuf[bn] = '\0';
  if (azl_compile_source(bbuf, bn, &prog, err, sizeof(err)) != 0) {
    fprintf(stderr, "azl_compiler_selftest: branch compile failed: %s\n", err);
    azl_engine_destroy(e);
    return -1;
  }
  g_branch_ok = 0;
  azl_engine_register_listener(e, "success", cmp_on_success, NULL);
  if (azl_vm_exec_block(e, &prog) != AZL_OK) {
    fprintf(stderr, "azl_compiler_selftest: branch vm_exec failed\n");
    azl_engine_destroy(e);
    azl_bytecode_program_destroy(&prog);
    return -1;
  }
  azl_bytecode_program_destroy(&prog);
  azl_engine_destroy(e);
  if (!g_branch_ok) {
    fprintf(stderr, "azl_compiler_selftest: branch did not emit success/result=yes\n");
    return -1;
  }
  fprintf(stderr, "azl_compiler_selftest: ok (%s, %s)\n", used ? used : "?", bused ? bused : "?");
  return 0;
}
