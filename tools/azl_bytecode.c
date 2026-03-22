/* Minimal JSON bytecode loader + VM exec (native core, no Python). */
#define _GNU_SOURCE
#include "azl_bytecode.h"

#include <ctype.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

typedef struct {
  const char *s;
  size_t n;
  size_t i;
} J;

static void j_skip_ws(J *j) {
  while (j->i < j->n && (j->s[j->i] == ' ' || j->s[j->i] == '\t' || j->s[j->i] == '\n' || j->s[j->i] == '\r'))
    j->i++;
}

static int j_parse_string(J *j, char *out, size_t outs) {
  j_skip_ws(j);
  if (j->i >= j->n || j->s[j->i] != '"')
    return -1;
  j->i++;
  size_t w = 0;
  while (j->i < j->n && j->s[j->i] != '"') {
    if (j->s[j->i] == '\\' && j->i + 1 < j->n) {
      j->i++;
      char c = j->s[j->i++];
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
        out[w++] = j->s[j->i++];
    }
  }
  if (j->i >= j->n || j->s[j->i] != '"')
    return -1;
  j->i++;
  if (w < outs)
    out[w] = '\0';
  else if (outs > 0)
    out[outs - 1] = '\0';
  return 0;
}

static int j_parse_uint(J *j, uint32_t *out) {
  j_skip_ws(j);
  if (j->i >= j->n || !isdigit((unsigned char)j->s[j->i]))
    return -1;
  unsigned long v = 0;
  while (j->i < j->n && isdigit((unsigned char)j->s[j->i])) {
    v = v * 10ul + (unsigned long)(j->s[j->i] - '0');
    if (v > 0xfffffffful)
      return -1;
    j->i++;
  }
  *out = (uint32_t)v;
  return 0;
}

static int j_skip_value(J *j);

static int j_skip_string(J *j) {
  j_skip_ws(j);
  if (j->i >= j->n || j->s[j->i] != '"')
    return -1;
  j->i++;
  while (j->i < j->n && j->s[j->i] != '"') {
    if (j->s[j->i] == '\\' && j->i + 1 < j->n)
      j->i += 2;
    else
      j->i++;
  }
  if (j->i >= j->n)
    return -1;
  j->i++;
  return 0;
}

static int j_skip_value(J *j) {
  j_skip_ws(j);
  if (j->i >= j->n)
    return -1;
  char c = j->s[j->i];
  if (c == '"')
    return j_skip_string(j);
  if (c == '{') {
    j->i++;
    for (;;) {
      j_skip_ws(j);
      if (j->i < j->n && j->s[j->i] == '}') {
        j->i++;
        return 0;
      }
      if (j_skip_string(j) != 0)
        return -1;
      j_skip_ws(j);
      if (j->i >= j->n || j->s[j->i] != ':')
        return -1;
      j->i++;
      if (j_skip_value(j) != 0)
        return -1;
      j_skip_ws(j);
      if (j->i < j->n && j->s[j->i] == ',')
        j->i++;
    }
  }
  if (c == '[') {
    j->i++;
    for (;;) {
      j_skip_ws(j);
      if (j->i < j->n && j->s[j->i] == ']') {
        j->i++;
        return 0;
      }
      if (j_skip_value(j) != 0)
        return -1;
      j_skip_ws(j);
      if (j->i < j->n && j->s[j->i] == ',')
        j->i++;
    }
  }
  while (j->i < j->n && j->s[j->i] != ',' && j->s[j->i] != '}' && j->s[j->i] != ']')
    j->i++;
  return 0;
}

static const char *j_find_key_value_start(J *j0, const char *key) {
  J j = *j0;
  j_skip_ws(&j);
  if (j.i >= j.n || j.s[j.i] != '{')
    return NULL;
  j.i++;
  while (j.i < j.n) {
    j_skip_ws(&j);
    if (j.s[j.i] == '}') {
      return NULL;
    }
    char kbuf[64];
    if (j_parse_string(&j, kbuf, sizeof(kbuf)) != 0)
      return NULL;
    j_skip_ws(&j);
    if (j.i >= j.n || j.s[j.i] != ':')
      return NULL;
    j.i++;
    j_skip_ws(&j);
    const char *val = j.s + j.i;
    if (strcmp(kbuf, key) == 0)
      return val;
    if (j_skip_value(&j) != 0)
      return NULL;
    j_skip_ws(&j);
    if (j.i < j.n && j.s[j.i] == ',')
      j.i++;
  }
  return NULL;
}

static int count_string_array(const char *start, size_t maxlen) {
  J j;
  j.s = start;
  j.n = maxlen;
  j.i = 0;
  j_skip_ws(&j);
  if (j.i >= j.n || j.s[j.i] != '[')
    return -1;
  j.i++;
  int n = 0;
  for (;;) {
    j_skip_ws(&j);
    if (j.i < j.n && j.s[j.i] == ']')
      return n;
    if (j.i >= j.n || j.s[j.i] != '"')
      return -1;
    char tmp[AZL_BC_STR_MAX];
    if (j_parse_string(&j, tmp, sizeof(tmp)) != 0)
      return -1;
    n++;
    if (n > (int)AZL_BC_CONST_MAX)
      return -1;
    j_skip_ws(&j);
    if (j.i < j.n && j.s[j.i] == ',')
      j.i++;
    else
      break;
  }
  j_skip_ws(&j);
  if (j.i >= j.n || j.s[j.i] != ']')
    return -1;
  return n;
}

static int fill_string_array(const char *start, size_t maxlen, char (*pool)[AZL_BC_STR_MAX], int maxn) {
  J j;
  j.s = start;
  j.n = maxlen;
  j.i = 0;
  j_skip_ws(&j);
  if (j.i >= j.n || j.s[j.i] != '[')
    return -1;
  j.i++;
  int idx = 0;
  for (;;) {
    j_skip_ws(&j);
    if (j.i < j.n && j.s[j.i] == ']')
      break;
    if (idx >= maxn)
      return -1;
    if (j_parse_string(&j, pool[idx], AZL_BC_STR_MAX) != 0)
      return -1;
    idx++;
    j_skip_ws(&j);
    if (j.i < j.n && j.s[j.i] == ',')
      j.i++;
    else
      break;
  }
  j_skip_ws(&j);
  if (j.i >= j.n || j.s[j.i] != ']')
    return -1;
  return idx;
}

static int count_code_objects(const char *start, size_t maxlen) {
  J j;
  j.s = start;
  j.n = maxlen;
  j.i = 0;
  j_skip_ws(&j);
  if (j.i >= j.n || j.s[j.i] != '[')
    return -1;
  j.i++;
  int n = 0;
  for (;;) {
    j_skip_ws(&j);
    if (j.i < j.n && j.s[j.i] == ']')
      return n;
    if (j.i >= j.n || j.s[j.i] != '{')
      return -1;
    int depth = 1;
    j.i++;
    while (j.i < j.n && depth > 0) {
      if (j.s[j.i] == '{')
        depth++;
      else if (j.s[j.i] == '}')
        depth--;
      j.i++;
    }
    n++;
    if (n > (int)AZL_BC_CODE_MAX)
      return -1;
    j_skip_ws(&j);
    if (j.i < j.n && j.s[j.i] == ',')
      j.i++;
    else
      break;
  }
  j_skip_ws(&j);
  if (j.i >= j.n || j.s[j.i] != ']')
    return -1;
  return n;
}

static int parse_one_code_obj(J *j, AzlBytecodeInstr *ins) {
  memset(ins, 0, sizeof(*ins));
  j_skip_ws(j);
  if (j->i >= j->n || j->s[j->i] != '{')
    return -1;
  j->i++;
  char opname[32] = {0};
  uint32_t ev = 0, ky = 0, vl = 0;
  uint32_t slot = 0, target = 0, false_idx = 0, true_idx = 0;
  int have_ev = 0, have_ky = 0, have_vl = 0;
  int have_slot = 0, have_target = 0, have_false_idx = 0, have_true_idx = 0;
  while (j->i < j->n) {
    j_skip_ws(j);
    if (j->s[j->i] == '}') {
      j->i++;
      break;
    }
    char kbuf[32];
    if (j_parse_string(j, kbuf, sizeof(kbuf)) != 0)
      return -1;
    j_skip_ws(j);
    if (j->i >= j->n || j->s[j->i] != ':')
      return -1;
    j->i++;
    j_skip_ws(j);
    if (strcmp(kbuf, "op") == 0) {
      if (j_parse_string(j, opname, sizeof(opname)) != 0)
        return -1;
    } else if (strcmp(kbuf, "event") == 0) {
      if (j_parse_uint(j, &ev) != 0)
        return -1;
      have_ev = 1;
    } else if (strcmp(kbuf, "key") == 0) {
      if (j_parse_uint(j, &ky) != 0)
        return -1;
      have_ky = 1;
    } else if (strcmp(kbuf, "val") == 0) {
      if (j_parse_uint(j, &vl) != 0)
        return -1;
      have_vl = 1;
    } else if (strcmp(kbuf, "slot") == 0) {
      if (j_parse_uint(j, &slot) != 0)
        return -1;
      have_slot = 1;
    } else if (strcmp(kbuf, "target") == 0) {
      if (j_parse_uint(j, &target) != 0)
        return -1;
      have_target = 1;
    } else if (strcmp(kbuf, "false_idx") == 0) {
      if (j_parse_uint(j, &false_idx) != 0)
        return -1;
      have_false_idx = 1;
    } else if (strcmp(kbuf, "true_idx") == 0) {
      if (j_parse_uint(j, &true_idx) != 0)
        return -1;
      have_true_idx = 1;
    } else if (strcmp(kbuf, "a") == 0) {
      if (j_parse_uint(j, &ev) != 0)
        return -1;
      have_ev = 1;
    } else {
      /* skip unknown value */
      j_skip_ws(j);
      if (j->i < j->n && j->s[j->i] == '"') {
        char tmp[128];
        if (j_parse_string(j, tmp, sizeof(tmp)) != 0)
          return -1;
      } else if (j->i < j->n && isdigit((unsigned char)j->s[j->i])) {
        uint32_t u;
        (void)j_parse_uint(j, &u);
      } else if (j->i < j->n && (j->s[j->i] == 't' || j->s[j->i] == 'f')) {
        while (j->i < j->n && j->s[j->i] != ',' && j->s[j->i] != '}')
          j->i++;
      } else
        return -1;
    }
    j_skip_ws(j);
    if (j->i < j->n && j->s[j->i] == ',')
      j->i++;
  }
  if (strcmp(opname, "nop") == 0)
    ins->op = AZL_OP_NOP;
  else if (strcmp(opname, "halt") == 0)
    ins->op = AZL_OP_HALT;
  else if (strcmp(opname, "load_const") == 0) {
    ins->op = AZL_OP_LOAD_CONST;
    ins->a = ev;
    if (!have_ev)
      return -1;
  } else if (strcmp(opname, "emit") == 0) {
    ins->op = AZL_OP_EMIT;
    if (!have_ev || !have_ky || !have_vl)
      return -1;
    ins->a = ev;
    ins->b = ky;
    ins->c = vl;
  } else if (strcmp(opname, "call") == 0) {
    ins->op = AZL_OP_CALL;
    if (!have_ev)
      return -1;
    ins->a = ev;
  } else if (strcmp(opname, "store_var") == 0) {
    ins->op = AZL_OP_STORE_VAR;
    if (!have_slot)
      return -1;
    ins->a = slot;
  } else if (strcmp(opname, "load_var") == 0) {
    ins->op = AZL_OP_LOAD_VAR;
    if (!have_slot)
      return -1;
    ins->a = slot;
  } else if (strcmp(opname, "jump") == 0) {
    ins->op = AZL_OP_JUMP;
    if (!have_target)
      return -1;
    ins->a = target;
  } else if (strcmp(opname, "jump_if_false") == 0) {
    ins->op = AZL_OP_JUMP_IF_FALSE;
    if (!have_target || !have_false_idx)
      return -1;
    ins->a = target;
    ins->b = false_idx;
  } else if (strcmp(opname, "eq") == 0) {
    ins->op = AZL_OP_EQ;
    if (!have_true_idx || !have_false_idx)
      return -1;
    ins->a = true_idx;
    ins->b = false_idx;
  } else
    return -1;
  return 0;
}

static int fill_code_array(const char *start, size_t maxlen, AzlBytecodeInstr *code, int maxn) {
  J j;
  j.s = start;
  j.n = maxlen;
  j.i = 0;
  j_skip_ws(&j);
  if (j.i >= j.n || j.s[j.i] != '[')
    return -1;
  j.i++;
  int idx = 0;
  for (;;) {
    j_skip_ws(&j);
    if (j.i < j.n && j.s[j.i] == ']')
      break;
    if (idx >= maxn)
      return -1;
    if (parse_one_code_obj(&j, &code[idx]) != 0)
      return -1;
    idx++;
    j_skip_ws(&j);
    if (j.i < j.n && j.s[j.i] == ',')
      j.i++;
    else
      break;
  }
  j_skip_ws(&j);
  if (j.i >= j.n || j.s[j.i] != ']')
    return -1;
  return idx;
}

void azl_bytecode_program_init_empty(AzlBytecodeProgram *p) {
  if (!p)
    return;
  memset(p, 0, sizeof(*p));
}

void azl_bytecode_program_destroy(AzlBytecodeProgram *p) {
  if (!p)
    return;
  free(p->consts);
  free(p->code);
  azl_bytecode_program_init_empty(p);
}

int azl_bytecode_load_json(const char *json, size_t json_len, AzlBytecodeProgram *out, char *errbuf,
                           size_t errbuf_sz) {
  if (!json || !out) {
    if (errbuf && errbuf_sz)
      snprintf(errbuf, errbuf_sz, "null argument");
    return -1;
  }
  azl_bytecode_program_destroy(out);
  J jroot;
  jroot.s = json;
  jroot.n = json_len;
  jroot.i = 0;
  const char *carr = j_find_key_value_start(&jroot, "consts");
  jroot.i = 0;
  const char *darr = j_find_key_value_start(&jroot, "code");
  if (!carr || !darr) {
    if (errbuf && errbuf_sz)
      snprintf(errbuf, errbuf_sz, "missing consts or code array");
    return -1;
  }
  size_t clen = json_len - (size_t)(carr - json);
  size_t dlen = json_len - (size_t)(darr - json);
  int nc = count_string_array(carr, clen);
  if (nc < 0) {
    if (errbuf && errbuf_sz)
      snprintf(errbuf, errbuf_sz, "consts array parse failed");
    return -1;
  }
  int ni = count_code_objects(darr, dlen);
  if (ni < 0) {
    if (errbuf && errbuf_sz)
      snprintf(errbuf, errbuf_sz, "code array parse failed");
    return -1;
  }
  out->consts = (char (*)[AZL_BC_STR_MAX])calloc((size_t)nc, AZL_BC_STR_MAX);
  out->code = (AzlBytecodeInstr *)calloc((size_t)ni, sizeof(AzlBytecodeInstr));
  if (!out->consts || !out->code) {
    azl_bytecode_program_destroy(out);
    if (errbuf && errbuf_sz)
      snprintf(errbuf, errbuf_sz, "oom");
    return -1;
  }
  int nf = fill_string_array(carr, clen, out->consts, nc);
  if (nf != nc) {
    azl_bytecode_program_destroy(out);
    if (errbuf && errbuf_sz)
      snprintf(errbuf, errbuf_sz, "consts fill mismatch");
    return -1;
  }
  out->nconst = (size_t)nc;
  int nf2 = fill_code_array(darr, dlen, out->code, ni);
  if (nf2 != ni) {
    azl_bytecode_program_destroy(out);
    if (errbuf && errbuf_sz)
      snprintf(errbuf, errbuf_sz, "code fill mismatch");
    return -1;
  }
  out->ncode = (size_t)ni;
  return 0;
}

static const char *bc_payload_cstr(const AzlEvent *ev, const char *key) {
  if (!ev || !key)
    return NULL;
  for (const AzlPayloadKV *p = ev->payload; p; p = p->next) {
    if (p->key && strcmp(p->key, key) == 0)
      return p->value ? p->value : "";
  }
  return NULL;
}

static int g_bc_hello_ok;

static void bc_on_hello(AzlEngine *eng, const AzlEvent *ev, void *ud) {
  (void)eng;
  (void)ud;
  const char *m = bc_payload_cstr(ev, "message");
  if (m && strcmp(m, "Hello World") == 0)
    g_bc_hello_ok = 1;
}

int azl_bytecode_selftest(void) {
  const char *paths[] = {"tools/testdata/vm_hello_world.json", "testdata/vm_hello_world.json", NULL};
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
    fprintf(stderr, "azl_bytecode_selftest: cannot open vm_hello_world.json\n");
    return -1;
  }
  char buf[8192];
  size_t n = fread(buf, 1, sizeof(buf) - 1, f);
  fclose(f);
  buf[n] = '\0';

  AzlBytecodeProgram prog;
  azl_bytecode_program_init_empty(&prog);
  char err[256];
  if (azl_bytecode_load_json(buf, n, &prog, err, sizeof(err)) != 0) {
    fprintf(stderr, "azl_bytecode_selftest: load_json failed: %s\n", err);
    return -1;
  }

  AzlEngine *e = azl_engine_create((size_t)1u << 16, 1024u, 64u);
  if (!e) {
    azl_bytecode_program_destroy(&prog);
    return -1;
  }
  g_bc_hello_ok = 0;
  azl_engine_register_listener(e, "hello", bc_on_hello, NULL);
  AzlErr xr = azl_vm_exec_block(e, &prog);
  if (xr != AZL_OK) {
    fprintf(stderr, "azl_bytecode_selftest: vm_exec failed (%d)\n", (int)xr);
    azl_engine_destroy(e);
    azl_bytecode_program_destroy(&prog);
    return -1;
  }
  if (!g_bc_hello_ok) {
    fprintf(stderr, "azl_bytecode_selftest: hello listener did not observe Hello World\n");
    azl_engine_destroy(e);
    azl_bytecode_program_destroy(&prog);
    return -1;
  }
  azl_engine_destroy(e);
  azl_bytecode_program_destroy(&prog);
  fprintf(stderr, "azl_bytecode_selftest: ok (%s)\n", used ? used : "?");
  return 0;
}
