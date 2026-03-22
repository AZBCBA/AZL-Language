/* azl_core_engine.c — arena-backed event engine, multi-listener dispatch, async sysproxy HTTP
 *
 * Build library:  gcc -std=c11 -Wall -Wextra -O2 -pthread -c tools/azl_core_engine.c -o .azl/azl_core_engine.o
 * Build selftest: gcc -std=c11 -Wall -Wextra -O2 -pthread -DAZL_CORE_ENGINE_SELFTEST tools/azl_core_engine.c -o .azl/azl_core_engine_selftest
 */
#define _GNU_SOURCE
#include "azl_core_engine.h"
#include "azl_bytecode.h"
#include "azl_compiler.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define AZL_MAX_LISTENERS 256u
#define AZL_MAX_QUEUE 1024u
#define AZL_NAME_MAX 64u
#define AZL_ASYNC_RING 256u
#define AZL_JOB_QUEUE 8u

static void copy_trunc_cstr(char *dst, size_t dstsz, const char *src) {
  if (!dst || dstsz == 0u)
    return;
  if (!src)
    src = "";
  size_t n = strlen(src);
  if (n >= dstsz)
    n = dstsz - 1u;
  memcpy(dst, src, n);
  dst[n] = '\0';
}

struct AzlArena {
  uint8_t *base;
  size_t cap;
  size_t off;
};

struct AzlEngine {
  AzlArena *arena;
  AzlListenerFn listeners_fn[AZL_MAX_LISTENERS];
  void *listeners_ud[AZL_MAX_LISTENERS];
  char listeners_name[AZL_MAX_LISTENERS][AZL_NAME_MAX];
  size_t n_listeners;

  char q_name[AZL_MAX_QUEUE][AZL_NAME_MAX];
  AzlPayloadKV *q_payload[AZL_MAX_QUEUE];
  unsigned q_head, q_tail, q_count;

  pthread_mutex_t q_mu;
  unsigned max_nesting;
  unsigned nesting;
  unsigned overflow_events;
  AzlEngineErrorFn err_cb;
  void *err_ud;
};

typedef enum {
  AZL_NOTE_CHUNK = 1,
  AZL_NOTE_DONE = 2,
  AZL_NOTE_ERR = 3,
} AzlAsyncKind;

typedef struct {
  AzlAsyncKind kind;
  char tag[64];
  char text[8192];
  char err_msg[256];
  AzlErr err_code;
} AzlAsyncNote;

struct AzlSysproxyBridge {
  AzlEngine *engine;
  char host[128];
  int port;
  long next_id;

  pthread_mutex_t job_mu;
  pthread_cond_t job_cv;
  int shutdown;
  unsigned job_count;
  AzlHttpJob jobs[AZL_JOB_QUEUE];

  pthread_mutex_t ring_mu;
  AzlAsyncNote ring[AZL_ASYNC_RING];
  unsigned ring_r, ring_w, ring_count;

  pthread_t worker;
};

/* --- Arena --- */

AzlArena *azl_arena_create(size_t capacity_bytes) {
  AzlArena *a = (AzlArena *)calloc(1, sizeof(AzlArena));
  if (!a)
    return NULL;
  a->base = (uint8_t *)malloc(capacity_bytes ? capacity_bytes : 4096u);
  if (!a->base) {
    free(a);
    return NULL;
  }
  a->cap = capacity_bytes ? capacity_bytes : 4096u;
  a->off = 0;
  return a;
}

void azl_arena_destroy(AzlArena *a) {
  if (!a)
    return;
  free(a->base);
  free(a);
}

void azl_arena_reset(AzlArena *a) {
  if (a)
    a->off = 0;
}

void *azl_arena_alloc(AzlArena *a, size_t size, size_t align) {
  if (!a || align == 0u)
    return NULL;
  size_t p = a->off;
  size_t mask = align - 1u;
  p = (p + mask) & ~mask;
  if (p > a->cap || size > a->cap - p)
    return NULL;
  void *out = a->base + p;
  a->off = p + size;
  return out;
}

char *azl_arena_strdup(AzlArena *a, const char *s) {
  if (!s)
    s = "";
  size_t n = strlen(s) + 1u;
  char *d = (char *)azl_arena_alloc(a, n, 1u);
  if (!d)
    return NULL;
  memcpy(d, s, n);
  return d;
}

/* --- Payload clone into engine arena --- */

static AzlPayloadKV *clone_payload(AzlEngine *e, const AzlPayloadKV *head, AzlErr *err_out) {
  *err_out = AZL_OK;
  if (!head)
    return NULL;
  AzlPayloadKV *out_head = NULL;
  AzlPayloadKV **prev_next = &out_head;
  const AzlPayloadKV *p = head;
  while (p) {
    AzlPayloadKV *n = (AzlPayloadKV *)azl_arena_alloc(e->arena, sizeof(AzlPayloadKV), sizeof(void *));
    if (!n) {
      *err_out = AZL_ERR_ARENA_OOM;
      return NULL;
    }
    n->key = azl_arena_strdup(e->arena, p->key ? p->key : "");
    n->value = azl_arena_strdup(e->arena, p->value ? p->value : "");
    if (!n->key || !n->value) {
      *err_out = AZL_ERR_ARENA_OOM;
      return NULL;
    }
    n->next = NULL;
    *prev_next = n;
    prev_next = &n->next;
    p = p->next;
  }
  return out_head;
}

/* --- Engine --- */

AzlEngine *azl_engine_create(size_t arena_capacity, unsigned max_queue_events,
                             unsigned max_dispatch_nesting) {
  (void)max_queue_events;
  AzlEngine *e = (AzlEngine *)calloc(1, sizeof(AzlEngine));
  if (!e)
    return NULL;
  e->arena = azl_arena_create(arena_capacity ? arena_capacity : (size_t)1u << 20);
  if (!e->arena) {
    free(e);
    return NULL;
  }
  e->max_nesting = max_dispatch_nesting ? max_dispatch_nesting : 64u;
  if (pthread_mutex_init(&e->q_mu, NULL) != 0) {
    azl_arena_destroy(e->arena);
    free(e);
    return NULL;
  }
  return e;
}

void azl_engine_destroy(AzlEngine *e) {
  if (!e)
    return;
  pthread_mutex_destroy(&e->q_mu);
  azl_arena_destroy(e->arena);
  free(e);
}

void azl_engine_set_error_callback(AzlEngine *eng, AzlEngineErrorFn cb, void *userdata) {
  if (!eng)
    return;
  eng->err_cb = cb;
  eng->err_ud = userdata;
}

AzlArena *azl_engine_arena(AzlEngine *e) { return e ? e->arena : NULL; }

unsigned azl_engine_dispatch_depth(const AzlEngine *e) { return e ? e->nesting : 0u; }

unsigned azl_engine_overflow_events(const AzlEngine *e) { return e ? e->overflow_events : 0u; }

void azl_engine_reset_arena_if_idle(AzlEngine *e) {
  if (!e)
    return;
  pthread_mutex_lock(&e->q_mu);
  int idle = (e->q_count == 0u);
  pthread_mutex_unlock(&e->q_mu);
  if (idle && e->nesting == 0u)
    azl_arena_reset(e->arena);
}

AzlErr azl_engine_register_listener(AzlEngine *e, const char *event_name, AzlListenerFn fn,
                                    void *userdata) {
  if (!e || !event_name || !fn)
    return AZL_ERR_INVALID;
  if (e->n_listeners >= AZL_MAX_LISTENERS)
    return AZL_ERR_QUEUE_FULL;
  size_t n = strlen(event_name);
  if (n >= AZL_NAME_MAX)
    return AZL_ERR_INVALID;
  memcpy(e->listeners_name[e->n_listeners], event_name, n + 1u);
  e->listeners_fn[e->n_listeners] = fn;
  e->listeners_ud[e->n_listeners] = userdata;
  e->n_listeners++;
  return AZL_OK;
}

static AzlErr queue_push(AzlEngine *e, const char *event_name, AzlPayloadKV *payload_owned) {
  pthread_mutex_lock(&e->q_mu);
  if (e->q_count >= AZL_MAX_QUEUE) {
    pthread_mutex_unlock(&e->q_mu);
    return AZL_ERR_QUEUE_FULL;
  }
  size_t n = strlen(event_name);
  if (n >= AZL_NAME_MAX) {
    pthread_mutex_unlock(&e->q_mu);
    return AZL_ERR_INVALID;
  }
  unsigned slot = e->q_tail;
  memcpy(e->q_name[slot], event_name, n + 1u);
  e->q_payload[slot] = payload_owned;
  e->q_tail = (e->q_tail + 1u) % AZL_MAX_QUEUE;
  e->q_count++;
  pthread_mutex_unlock(&e->q_mu);
  return AZL_OK;
}

static int queue_pop(AzlEngine *e, AzlEvent *out_ev) {
  pthread_mutex_lock(&e->q_mu);
  if (e->q_count == 0u) {
    pthread_mutex_unlock(&e->q_mu);
    return 0;
  }
  unsigned slot = e->q_head;
  memcpy(out_ev->name, e->q_name[slot], AZL_NAME_MAX);
  out_ev->payload = e->q_payload[slot];
  e->q_payload[slot] = NULL;
  e->q_head = (e->q_head + 1u) % AZL_MAX_QUEUE;
  e->q_count--;
  pthread_mutex_unlock(&e->q_mu);
  return 1;
}

AzlErr azl_engine_emit_enqueue(AzlEngine *e, const char *event_name, const AzlPayloadKV *payload_head) {
  if (!e || !event_name)
    return AZL_ERR_INVALID;
  AzlErr er = AZL_OK;
  AzlPayloadKV *owned = clone_payload(e, payload_head, &er);
  if (er != AZL_OK)
    return er;
  return queue_push(e, event_name, owned);
}

void azl_engine_process(AzlEngine *e) {
  if (!e)
    return;
  for (;;) {
    AzlEvent ev;
    memset(&ev, 0, sizeof(ev));
    if (!queue_pop(e, &ev))
      break;

    if (e->nesting >= e->max_nesting) {
      e->overflow_events++;
      if (e->err_cb)
        e->err_cb(e, AZL_ERR_DISPATCH_DEPTH,
                  "event dispatch nesting exceeded fixed-depth guard (drop event)", e->err_ud);
      continue;
    }

    e->nesting++;
    /* Multi-listener: invoke every registration matching the name (ordered). */
    for (size_t i = 0; i < e->n_listeners; i++) {
      if (strcmp(e->listeners_name[i], ev.name) == 0)
        e->listeners_fn[i](e, &ev, e->listeners_ud[i]);
    }
    e->nesting--;
  }
}

AzlErr azl_engine_emit(AzlEngine *e, const char *event_name, const AzlPayloadKV *payload_head) {
  AzlErr r = azl_engine_emit_enqueue(e, event_name, payload_head);
  if (r != AZL_OK)
    return r;
  azl_engine_process(e);
  return AZL_OK;
}

/* --- Minimal JSON helpers for sysproxy responses --- */

static int json_extract_ok(const char *line, int *ok_out) {
  const char *p = strstr(line, "\"ok\"");
  if (!p)
    return -1;
  p = strchr(p, ':');
  if (!p)
    return -1;
  p++;
  while (*p == ' ' || *p == '\t')
    p++;
  if (strncmp(p, "true", 4) == 0)
    *ok_out = 1;
  else if (strncmp(p, "false", 5) == 0)
    *ok_out = 0;
  else
    return -1;
  return 0;
}

/* Copy unescaped JSON string starting at opening quote after "data": */
static int json_extract_data_string(const char *line, char *out, size_t outsz) {
  const char *key = strstr(line, "\"data\"");
  if (!key)
    return -1;
  const char *p = strchr(key, ':');
  if (!p)
    return -1;
  p++;
  while (*p == ' ' || *p == '\t')
    p++;
  if (*p != '"')
    return -1;
  p++;
  size_t w = 0;
  while (*p && w + 1 < outsz) {
    if (*p == '\\' && p[1]) {
      p++;
      char c = *p++;
      if (c == 'n')
        out[w++] = '\n';
      else if (c == 'r')
        out[w++] = '\r';
      else if (c == 't')
        out[w++] = '\t';
      else if (c == '\\' || c == '"')
        out[w++] = c;
      else
        out[w++] = c;
    } else if (*p == '"')
      break;
    else
      out[w++] = *p++;
  }
  out[w] = '\0';
  return 0;
}

static int json_extract_error_string(const char *line, char *out, size_t outsz) {
  const char *key = strstr(line, "\"error\"");
  if (!key)
    key = strstr(line, "\"msg\"");
  if (!key)
    return -1;
  const char *p = strchr(key, ':');
  if (!p)
    return -1;
  p++;
  while (*p == ' ' || *p == '\t')
    p++;
  if (*p != '"')
    return -1;
  p++;
  size_t w = 0;
  while (*p && *p != '"' && w + 1 < outsz) {
    if (*p == '\\' && p[1])
      p++;
    out[w++] = *p++;
  }
  out[w] = '\0';
  return 0;
}

static int append_json_str_esc(char *buf, size_t bufsz, size_t *pos, const char *src) {
  const unsigned char *b = (const unsigned char *)src;
  for (; *b; b++) {
    if (*b == '\\' || *b == '"') {
      if (*pos + 2 >= bufsz)
        return -1;
      buf[(*pos)++] = '\\';
      buf[(*pos)++] = (char)*b;
    } else if (*b == '\n') {
      if (*pos + 2 >= bufsz)
        return -1;
      buf[(*pos)++] = '\\';
      buf[(*pos)++] = 'n';
    } else if (*b == '\r') {
      if (*pos + 2 >= bufsz)
        return -1;
      buf[(*pos)++] = '\\';
      buf[(*pos)++] = 'r';
    } else if (*b < 0x20u) {
      int nn = snprintf(buf + *pos, bufsz - *pos, "\\u%04x", *b);
      if (nn < 0 || (size_t)nn >= bufsz - *pos)
        return -1;
      *pos += (size_t)nn;
    } else {
      if (*pos + 1 >= bufsz)
        return -1;
      buf[(*pos)++] = (char)*b;
    }
  }
  return 0;
}

/* --- TCP sysproxy line exchange --- */

static AzlErr tcp_http_client(const char *host, int port, long id, const AzlHttpJob *job,
                              char *resp_buf, size_t resp_sz) {
  int s = socket(AF_INET, SOCK_STREAM, 0);
  if (s < 0)
    return AZL_ERR_NET_IO;
  struct sockaddr_in a;
  memset(&a, 0, sizeof(a));
  a.sin_family = AF_INET;
  a.sin_port = htons((uint16_t)port);
  if (inet_pton(AF_INET, host, &a.sin_addr) != 1) {
    close(s);
    return AZL_ERR_NET_IO;
  }
  if (connect(s, (struct sockaddr *)&a, sizeof(a)) < 0) {
    close(s);
    return AZL_ERR_NET_IO;
  }

  char req[70000];
  size_t pos = 0;
  int nh = snprintf(req, sizeof(req), "{\"id\":%ld,\"op\":\"http_client\",\"url\":\"", id);
  if (nh < 0 || (size_t)nh >= sizeof(req)) {
    close(s);
    return AZL_ERR_INVALID;
  }
  pos = (size_t)nh;
  if (append_json_str_esc(req, sizeof(req), &pos, job->url) != 0) {
    close(s);
    return AZL_ERR_INVALID;
  }
  const char *meth = job->method[0] ? job->method : "GET";
  nh = snprintf(req + pos, sizeof(req) - pos, "\",\"method\":\"%s\"", meth);
  if (nh < 0 || pos + (size_t)nh >= sizeof(req)) {
    close(s);
    return AZL_ERR_INVALID;
  }
  pos += (size_t)nh;

  if (strcmp(meth, "POST") == 0 && job->body[0]) {
    if (pos + 11 >= sizeof(req)) {
      close(s);
      return AZL_ERR_INVALID;
    }
    memcpy(req + pos, ",\"body\":\"", 9u);
    pos += 9u;
    if (append_json_str_esc(req, sizeof(req), &pos, job->body) != 0) {
      close(s);
      return AZL_ERR_INVALID;
    }
    if (pos + 4 >= sizeof(req)) {
      close(s);
      return AZL_ERR_INVALID;
    }
    memcpy(req + pos, "\"}\n", 4u);
    pos += 3u;
  } else {
    if (pos + 16 >= sizeof(req)) {
      close(s);
      return AZL_ERR_INVALID;
    }
    memcpy(req + pos, ",\"body\":\"\"}\n", 12u);
    pos += 11u;
  }
  req[pos] = '\0';

  size_t total = strlen(req);
  size_t sent = 0;
  while (sent < total) {
    ssize_t n = write(s, req + sent, total - sent);
    if (n < 0) {
      close(s);
      return AZL_ERR_NET_IO;
    }
    sent += (size_t)n;
  }

  size_t rp = 0;
  while (rp + 1 < resp_sz) {
    char c;
    ssize_t n = read(s, &c, 1);
    if (n <= 0) {
      close(s);
      return AZL_ERR_NET_IO;
    }
    resp_buf[rp++] = c;
    if (c == '\n')
      break;
  }
  resp_buf[rp] = '\0';
  close(s);
  return AZL_OK;
}

/* Direct curl (streaming-friendly body read); used when no sysproxy TCP or for timeout control */
static AzlErr curl_one_shot(const AzlHttpJob *job, char *out, size_t outsz) {
  int tmo = job->timeout_sec > 0 ? job->timeout_sec : 30;
  char tmp[128] = "/tmp/azl_core_http_XXXXXX";
  int fd = mkstemp(tmp);
  if (fd < 0)
    return AZL_ERR_NET_IO;
  close(fd);

  char cmd[72000];
  if (strcmp(job->method, "POST") == 0 && job->body[0]) {
    FILE *f = fopen(tmp, "w");
    if (!f) {
      unlink(tmp);
      return AZL_ERR_NET_IO;
    }
    fputs(job->body, f);
    fclose(f);
    snprintf(cmd, sizeof(cmd),
             "curl -sS --max-time %d -X POST -H 'Content-Type: application/json' -d @'%s' '%s' "
             "2>/dev/null",
             tmo, tmp, job->url);
  } else {
    snprintf(cmd, sizeof(cmd), "curl -sS --max-time %d '%s' 2>/dev/null", tmo, job->url);
  }

  FILE *pipe = popen(cmd, "r");
  if (!pipe) {
    unlink(tmp);
    return AZL_ERR_NET_IO;
  }
  size_t rn = 0;
  while (rn + 1 < outsz) {
    int c = fgetc(pipe);
    if (c == EOF)
      break;
    out[rn++] = (char)c;
  }
  out[rn] = '\0';
  int st = pclose(pipe);
  unlink(tmp);
  if (st == -1)
    return AZL_ERR_NET_IO;
  if (WIFEXITED(st) && WEXITSTATUS(st) == 28) /* curl timeout */
    return AZL_ERR_NET_TIMEOUT;
  return AZL_OK;
}

static void ring_push_note(AzlSysproxyBridge *b, const AzlAsyncNote *n) {
  pthread_mutex_lock(&b->ring_mu);
  if (b->ring_count < AZL_ASYNC_RING) {
    b->ring[b->ring_w] = *n;
    b->ring_w = (b->ring_w + 1u) % AZL_ASYNC_RING;
    b->ring_count++;
  }
  pthread_mutex_unlock(&b->ring_mu);
}

static int ring_pop_note(AzlSysproxyBridge *b, AzlAsyncNote *n) {
  pthread_mutex_lock(&b->ring_mu);
  if (b->ring_count == 0u) {
    pthread_mutex_unlock(&b->ring_mu);
    return 0;
  }
  *n = b->ring[b->ring_r];
  b->ring_r = (b->ring_r + 1u) % AZL_ASYNC_RING;
  b->ring_count--;
  pthread_mutex_unlock(&b->ring_mu);
  return 1;
}

static void run_http_job(AzlSysproxyBridge *b, const AzlHttpJob *job) {
  char resp[131072];
  AzlErr transport = AZL_OK;

  if (b->port > 0) {
    long id = ++b->next_id;
    transport = tcp_http_client(b->host, b->port, id, job, resp, sizeof(resp));
    if (transport != AZL_OK) {
      AzlAsyncNote n;
      memset(&n, 0, sizeof(n));
      n.kind = AZL_NOTE_ERR;
      copy_trunc_cstr(n.tag, sizeof(n.tag), job->request_tag);
      n.err_code = transport;
      snprintf(n.err_msg, sizeof(n.err_msg), "sysproxy_tcp failed");
      ring_push_note(b, &n);
      return;
    }
    int ok = 0;
    if (json_extract_ok(resp, &ok) != 0 || !ok) {
      AzlAsyncNote n;
      memset(&n, 0, sizeof(n));
      n.kind = AZL_NOTE_ERR;
      copy_trunc_cstr(n.tag, sizeof(n.tag), job->request_tag);
      n.err_code = AZL_ERR_NET_IO;
      if (json_extract_error_string(resp, n.err_msg, sizeof(n.err_msg)) != 0)
        snprintf(n.err_msg, sizeof(n.err_msg), "http_client rejected");
      ring_push_note(b, &n);
      return;
    }
    char data[65536];
    if (json_extract_data_string(resp, data, sizeof(data)) != 0) {
      AzlAsyncNote n;
      memset(&n, 0, sizeof(n));
      n.kind = AZL_NOTE_ERR;
      copy_trunc_cstr(n.tag, sizeof(n.tag), job->request_tag);
      n.err_code = AZL_ERR_PARSE;
      snprintf(n.err_msg, sizeof(n.err_msg), "missing data field");
      ring_push_note(b, &n);
      return;
    }
    if (job->split_response_lines) {
      char *save = NULL;
      char *line;
      char bufcpy[sizeof(data)];
      copy_trunc_cstr(bufcpy, sizeof(bufcpy), data);
      for (line = strtok_r(bufcpy, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
        AzlAsyncNote n;
        memset(&n, 0, sizeof(n));
        n.kind = AZL_NOTE_CHUNK;
        copy_trunc_cstr(n.tag, sizeof(n.tag), job->request_tag);
        copy_trunc_cstr(n.text, sizeof(n.text), line);
        ring_push_note(b, &n);
      }
    } else {
      AzlAsyncNote n;
      memset(&n, 0, sizeof(n));
      n.kind = AZL_NOTE_CHUNK;
      copy_trunc_cstr(n.tag, sizeof(n.tag), job->request_tag);
      copy_trunc_cstr(n.text, sizeof(n.text), data);
      ring_push_note(b, &n);
    }
  } else {
    char body[131072];
    transport = curl_one_shot(job, body, sizeof(body));
    if (transport == AZL_ERR_NET_TIMEOUT) {
      AzlAsyncNote n;
      memset(&n, 0, sizeof(n));
      n.kind = AZL_NOTE_ERR;
      copy_trunc_cstr(n.tag, sizeof(n.tag), job->request_tag);
      n.err_code = AZL_ERR_NET_TIMEOUT;
      snprintf(n.err_msg, sizeof(n.err_msg), "network timeout (curl exit 28)");
      ring_push_note(b, &n);
      return;
    }
    if (transport != AZL_OK) {
      AzlAsyncNote n;
      memset(&n, 0, sizeof(n));
      n.kind = AZL_NOTE_ERR;
      copy_trunc_cstr(n.tag, sizeof(n.tag), job->request_tag);
      n.err_code = transport;
      snprintf(n.err_msg, sizeof(n.err_msg), "curl transport failed");
      ring_push_note(b, &n);
      return;
    }
    if (job->split_response_lines) {
      char *save = NULL;
      char bufcpy[sizeof(body)];
      copy_trunc_cstr(bufcpy, sizeof(bufcpy), body);
      char *line;
      for (line = strtok_r(bufcpy, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
        AzlAsyncNote n;
        memset(&n, 0, sizeof(n));
        n.kind = AZL_NOTE_CHUNK;
        copy_trunc_cstr(n.tag, sizeof(n.tag), job->request_tag);
        copy_trunc_cstr(n.text, sizeof(n.text), line);
        ring_push_note(b, &n);
      }
    } else {
      AzlAsyncNote n;
      memset(&n, 0, sizeof(n));
      n.kind = AZL_NOTE_CHUNK;
      copy_trunc_cstr(n.tag, sizeof(n.tag), job->request_tag);
      copy_trunc_cstr(n.text, sizeof(n.text), body);
      ring_push_note(b, &n);
    }
  }

  AzlAsyncNote done;
  memset(&done, 0, sizeof(done));
  done.kind = AZL_NOTE_DONE;
  copy_trunc_cstr(done.tag, sizeof(done.tag), job->request_tag);
  ring_push_note(b, &done);
}

static void *bridge_worker_main(void *arg) {
  AzlSysproxyBridge *b = (AzlSysproxyBridge *)arg;
  for (;;) {
    pthread_mutex_lock(&b->job_mu);
    while (!b->shutdown && b->job_count == 0u)
      pthread_cond_wait(&b->job_cv, &b->job_mu);
    if (b->shutdown && b->job_count == 0u) {
      pthread_mutex_unlock(&b->job_mu);
      break;
    }
    AzlHttpJob job = b->jobs[0];
    for (unsigned i = 1u; i < b->job_count; i++)
      b->jobs[i - 1u] = b->jobs[i];
    b->job_count--;
    pthread_mutex_unlock(&b->job_mu);

    run_http_job(b, &job);
  }
  return NULL;
}

AzlSysproxyBridge *azl_bridge_create(AzlEngine *engine, const char *tcp_host, int tcp_port) {
  if (!engine)
    return NULL;
  AzlSysproxyBridge *b = (AzlSysproxyBridge *)calloc(1, sizeof(AzlSysproxyBridge));
  if (!b)
    return NULL;
  b->engine = engine;
  const char *env = getenv("AZL_SYSPROXY_TCP");
  if (tcp_host && tcp_host[0]) {
    copy_trunc_cstr(b->host, sizeof(b->host), tcp_host);
    b->port = tcp_port;
  } else if (env && env[0]) {
    const char *colon = strchr(env, ':');
    if (colon) {
      size_t hl = (size_t)(colon - env);
      if (hl >= sizeof(b->host))
        hl = sizeof(b->host) - 1u;
      memcpy(b->host, env, hl);
      b->host[hl] = '\0';
      b->port = atoi(colon + 1);
    } else {
      strcpy(b->host, "127.0.0.1");
      b->port = atoi(env);
    }
  } else {
    strcpy(b->host, "127.0.0.1");
    /* tcp_port == 0 and no AZL_SYSPROXY_TCP: curl-only path (honors job.timeout_sec). */
    b->port = tcp_port;
  }

  pthread_mutex_init(&b->job_mu, NULL);
  pthread_cond_init(&b->job_cv, NULL);
  pthread_mutex_init(&b->ring_mu, NULL);

  if (pthread_create(&b->worker, NULL, bridge_worker_main, b) != 0) {
    pthread_mutex_destroy(&b->ring_mu);
    pthread_cond_destroy(&b->job_cv);
    pthread_mutex_destroy(&b->job_mu);
    free(b);
    return NULL;
  }
  return b;
}

void azl_bridge_destroy(AzlSysproxyBridge *b) {
  if (!b)
    return;
  pthread_mutex_lock(&b->job_mu);
  b->shutdown = 1;
  pthread_cond_signal(&b->job_cv);
  pthread_mutex_unlock(&b->job_mu);
  pthread_join(b->worker, NULL);
  pthread_cond_destroy(&b->job_cv);
  pthread_mutex_destroy(&b->job_mu);
  pthread_mutex_destroy(&b->ring_mu);
  free(b);
}

AzlErr azl_bridge_submit_http(AzlSysproxyBridge *b, const AzlHttpJob *job) {
  if (!b || !job || !job->url[0])
    return AZL_ERR_INVALID;
  pthread_mutex_lock(&b->job_mu);
  if (b->job_count >= AZL_JOB_QUEUE) {
    pthread_mutex_unlock(&b->job_mu);
    return AZL_ERR_QUEUE_FULL;
  }
  b->jobs[b->job_count++] = *job;
  pthread_cond_signal(&b->job_cv);
  pthread_mutex_unlock(&b->job_mu);
  return AZL_OK;
}

#define AZL_VM_STACK_MAX 128
#define AZL_VM_VAR_MAX 64

static const char *vm_const_get(const AzlBytecodeProgram *p, uint32_t idx) {
  if (!p || idx >= p->nconst)
    return NULL;
  return p->consts[idx];
}

typedef enum AzlVmRunKind { AZL_VM_RUN_MAIN = 0, AZL_VM_RUN_LISTENER = 1 } AzlVmRunKind;

static int vm_jump_tgt_ok(size_t tgt, size_t range_lo, size_t range_hi_excl, size_t ncode) {
  if (tgt >= ncode)
    return 0;
  if (tgt < range_lo || tgt >= range_hi_excl)
    return 0;
  return 1;
}

/* Per-activation operand stack; shared vars across main and listen handlers. */
static AzlErr azl_vm_exec_loop(AzlEngine *eng, const AzlBytecodeProgram *prog, uint32_t *vars, size_t *pc_io,
                               size_t range_lo, size_t range_hi_excl, AzlVmRunKind kind) {
  if (!eng || !prog || !prog->code || !vars || !pc_io)
    return AZL_ERR_INVALID;
  if (range_hi_excl > prog->ncode || range_lo > range_hi_excl)
    return AZL_ERR_INVALID;
  if (*pc_io < range_lo || *pc_io > range_hi_excl)
    return AZL_ERR_INVALID;

  uint32_t stack[AZL_VM_STACK_MAX];
  int sp = 0;

#define VM_PUSH(v)                                                                               \
  do {                                                                                           \
    if (sp >= AZL_VM_STACK_MAX)                                                                  \
      return AZL_ERR_INVALID;                                                                    \
    stack[sp++] = (v);                                                                           \
  } while (0)
#define VM_POP(out)                                                                              \
  do {                                                                                           \
    if (sp <= 0)                                                                                 \
      return AZL_ERR_INVALID;                                                                    \
    (out) = stack[--sp];                                                                         \
  } while (0)

  size_t pc = *pc_io;
  while (pc < range_hi_excl) {
    const AzlBytecodeInstr *in = &prog->code[pc];
    switch ((AzlOpcode)in->op) {
    case AZL_OP_HALT:
      if (kind == AZL_VM_RUN_LISTENER)
        return AZL_ERR_INVALID;
      *pc_io = pc + 1u;
      return AZL_OK;
    case AZL_OP_LISTENER_END:
      if (kind == AZL_VM_RUN_MAIN)
        return AZL_ERR_INVALID;
      *pc_io = pc + 1u;
      return AZL_OK;
    case AZL_OP_NOP:
      pc++;
      break;
    case AZL_OP_REJECTED_LEGACY_4:
    case AZL_OP_REJECTED_LEGACY_5:
    case AZL_OP_LISTENER_REG:
    case AZL_OP_ENTER_MAIN:
      return AZL_ERR_INVALID;
    case AZL_OP_LOAD_CONST:
      if (in->a >= prog->nconst)
        return AZL_ERR_INVALID;
      VM_PUSH(in->a);
      pc++;
      break;
    case AZL_OP_STORE_VAR:
      if (in->a >= AZL_VM_VAR_MAX)
        return AZL_ERR_INVALID;
      {
        uint32_t v;
        VM_POP(v);
        if (v >= prog->nconst)
          return AZL_ERR_INVALID;
        vars[in->a] = v;
      }
      pc++;
      break;
    case AZL_OP_LOAD_VAR:
      if (in->a >= AZL_VM_VAR_MAX)
        return AZL_ERR_INVALID;
      if (vars[in->a] == UINT32_MAX)
        return AZL_ERR_INVALID;
      if (vars[in->a] >= prog->nconst)
        return AZL_ERR_INVALID;
      VM_PUSH(vars[in->a]);
      pc++;
      break;
    case AZL_OP_JUMP:
      if (!vm_jump_tgt_ok((size_t)in->a, range_lo, range_hi_excl, prog->ncode))
        return AZL_ERR_INVALID;
      pc = (size_t)in->a;
      break;
    case AZL_OP_JUMP_IF_FALSE:
      if (!vm_jump_tgt_ok((size_t)in->a, range_lo, range_hi_excl, prog->ncode))
        return AZL_ERR_INVALID;
      {
        uint32_t v;
        VM_POP(v);
        const char *sv = vm_const_get(prog, v);
        const char *sf = vm_const_get(prog, in->b);
        if (!sv || !sf)
          return AZL_ERR_INVALID;
        if (strcmp(sv, sf) == 0)
          pc = (size_t)in->a;
        else
          pc++;
      }
      break;
    case AZL_OP_EQ:
      if (in->a >= prog->nconst || in->b >= prog->nconst)
        return AZL_ERR_INVALID;
      {
        uint32_t ri, li;
        VM_POP(ri);
        VM_POP(li);
        const char *sl = vm_const_get(prog, li);
        const char *sr = vm_const_get(prog, ri);
        if (!sl || !sr)
          return AZL_ERR_INVALID;
        if (strcmp(sl, sr) == 0)
          VM_PUSH(in->a);
        else
          VM_PUSH(in->b);
      }
      pc++;
      break;
    case AZL_OP_EMIT: {
      const char *ev = vm_const_get(prog, in->a);
      const char *k = vm_const_get(prog, in->b);
      const char *v = vm_const_get(prog, in->c);
      if (!ev || !k || !v)
        return AZL_ERR_INVALID;
      AzlPayloadKV kv = {k, v, NULL};
      AzlErr r = azl_engine_emit(eng, ev, &kv);
      if (r != AZL_OK)
        return r;
      pc++;
      break;
    }
    case AZL_OP_EMIT_VAR: {
      const char *ev = vm_const_get(prog, in->a);
      const char *k = vm_const_get(prog, in->b);
      if (!ev || !k)
        return AZL_ERR_INVALID;
      if (in->c >= AZL_VM_VAR_MAX)
        return AZL_ERR_INVALID;
      if (vars[in->c] == UINT32_MAX)
        return AZL_ERR_INVALID;
      if (vars[in->c] >= prog->nconst)
        return AZL_ERR_INVALID;
      const char *v = vm_const_get(prog, vars[in->c]);
      if (!v)
        return AZL_ERR_INVALID;
      AzlPayloadKV kv = {k, v, NULL};
      AzlErr r = azl_engine_emit(eng, ev, &kv);
      if (r != AZL_OK)
        return r;
      pc++;
      break;
    }
    default:
      return AZL_ERR_INVALID;
    }
  }
#undef VM_POP
#undef VM_PUSH
  if (kind == AZL_VM_RUN_LISTENER)
    return AZL_ERR_INVALID;
  *pc_io = pc;
  return AZL_ERR_INVALID;
}

typedef struct AzlVmListenerUd {
  const AzlBytecodeProgram *prog;
  uint32_t *vars;
  size_t h_start;
  size_t h_end;
} AzlVmListenerUd;

static void azl_vm_listener_trampoline(AzlEngine *eng, const AzlEvent *ev, void *ud) {
  (void)ev;
  AzlVmListenerUd *L = (AzlVmListenerUd *)ud;
  if (!L || !L->prog || !L->vars || L->h_start >= L->h_end || L->h_end > L->prog->ncode)
    return;
  size_t pc = L->h_start;
  AzlErr er = azl_vm_exec_loop(eng, L->prog, L->vars, &pc, L->h_start, L->h_end, AZL_VM_RUN_LISTENER);
  if (er != AZL_OK && eng && eng->err_cb)
    eng->err_cb(eng, er, "native vm listen handler failed", eng->err_ud);
}

/* Native VM: OP_EMIT / OP_EMIT_VAR use azl_engine_emit (multi-listener dispatch in engine order). */
AzlErr azl_vm_exec_block(AzlEngine *eng, const AzlBytecodeProgram *prog) {
  if (!eng || !prog || !prog->code)
    return AZL_ERR_INVALID;

  uint32_t vars[AZL_VM_VAR_MAX];
  for (size_t i = 0; i < AZL_VM_VAR_MAX; i++)
    vars[i] = UINT32_MAX;

  if (prog->ncode == 0u)
    return AZL_ERR_INVALID;

  if (prog->code[0].op != AZL_OP_LISTENER_REG) {
    size_t pc = 0;
    return azl_vm_exec_loop(eng, prog, vars, &pc, 0u, prog->ncode, AZL_VM_RUN_MAIN);
  }

  AzlVmListenerUd uds[AZL_MAX_LISTENERS];
  size_t n_reg = 0;
  size_t scan = 0;
  while (scan < prog->ncode && prog->code[scan].op == AZL_OP_LISTENER_REG) {
    const AzlBytecodeInstr *in = &prog->code[scan];
    const char *nm = vm_const_get(prog, in->a);
    if (!nm || !nm[0])
      return AZL_ERR_INVALID;
    if (in->b >= in->c || (size_t)in->c > prog->ncode)
      return AZL_ERR_INVALID;
    if (n_reg >= AZL_MAX_LISTENERS)
      return AZL_ERR_QUEUE_FULL;
    uds[n_reg].prog = prog;
    uds[n_reg].vars = vars;
    uds[n_reg].h_start = (size_t)in->b;
    uds[n_reg].h_end = (size_t)in->c;
    AzlErr lr = azl_engine_register_listener(eng, nm, azl_vm_listener_trampoline, &uds[n_reg]);
    if (lr != AZL_OK)
      return lr;
    n_reg++;
    scan++;
  }
  if (scan >= prog->ncode || prog->code[scan].op != AZL_OP_ENTER_MAIN)
    return AZL_ERR_INVALID;
  size_t main_pc = (size_t)prog->code[scan].a;
  if (main_pc > prog->ncode)
    return AZL_ERR_INVALID;
  size_t main_end = prog->ncode;
  for (size_t i = 0; i < n_reg; i++) {
    if (uds[i].h_start < main_end)
      main_end = uds[i].h_start;
  }
  if (main_pc >= main_end)
    return AZL_ERR_INVALID;
  size_t mpc = main_pc;
  return azl_vm_exec_loop(eng, prog, vars, &mpc, main_pc, main_end, AZL_VM_RUN_MAIN);
}

int azl_bridge_poll(AzlSysproxyBridge *b) {
  if (!b)
    return 0;
  int n = 0;
  AzlAsyncNote note;
  while (ring_pop_note(b, &note)) {
    AzlEngine *e = b->engine;
    if (note.kind == AZL_NOTE_CHUNK) {
      AzlPayloadKV kv0 = {"request_tag", note.tag, NULL};
      AzlPayloadKV kv1 = {"line", note.text, NULL};
      kv0.next = &kv1;
      azl_engine_emit_enqueue(e, "net.http.stream_chunk", &kv0);
    } else if (note.kind == AZL_NOTE_DONE) {
      AzlPayloadKV kv = {"request_tag", note.tag, NULL};
      azl_engine_emit_enqueue(e, "net.http.complete", &kv);
    } else if (note.kind == AZL_NOTE_ERR) {
      AzlPayloadKV k0 = {"request_tag", note.tag, NULL};
      AzlPayloadKV k1 = {"code", "", NULL};
      char codebuf[32];
      snprintf(codebuf, sizeof(codebuf), "%d", (int)note.err_code);
      k1.value = codebuf;
      AzlPayloadKV k2 = {"message", note.err_msg, NULL};
      k0.next = &k1;
      k1.next = &k2;
      /* codebuf stack lifetime OK: emit_enqueue strdup into arena before return */
      azl_engine_emit_enqueue(e, "net.http.error", &k0);
    }
    n++;
  }
  return n;
}

#ifdef AZL_CORE_ENGINE_SELFTEST

static int g_depth_max_seen;
static int g_multi_count;

static void on_ping(AzlEngine *eng, const AzlEvent *ev, void *ud) {
  (void)ud;
  (void)ev;
  (void)eng;
  g_multi_count++;
}

static void on_emit_nested(AzlEngine *eng, const AzlEvent *ev, void *ud) {
  (void)ud;
  if (strcmp(ev->name, "outer") == 0) {
    AzlPayloadKV z = {NULL, NULL, NULL};
    azl_engine_emit(eng, "inner", &z);
  }
}

static void on_depth(AzlEngine *eng, const AzlEvent *ev, void *ud) {
  (void)ev;
  (void)ud;
  unsigned d = azl_engine_dispatch_depth(eng);
  if (d > (unsigned)g_depth_max_seen)
    g_depth_max_seen = (int)d;
  AzlPayloadKV z = {NULL, NULL, NULL};
  azl_engine_emit(eng, "recurse", &z);
}

int main(void) {
  AzlEngine *e = azl_engine_create(1u << 16, AZL_MAX_QUEUE, 4u);
  if (!e)
    return 1;

  g_multi_count = 0;
  azl_engine_register_listener(e, "ping", on_ping, NULL);
  azl_engine_register_listener(e, "ping", on_ping, NULL);
  AzlPayloadKV kv = {"k", "v", NULL};
  azl_engine_emit(e, "ping", &kv);
  if (g_multi_count != 2) {
    fprintf(stderr, "multi-listener: want 2 got %d\n", g_multi_count);
    return 2;
  }

  g_depth_max_seen = 0;
  azl_engine_register_listener(e, "recurse", on_depth, NULL);
  azl_engine_emit(e, "recurse", &kv);
  if (g_depth_max_seen < 4 || azl_engine_overflow_events(e) == 0u) {
    fprintf(stderr, "expected depth guard / overflow (max_nesting=4)\n");
    return 3;
  }

  azl_engine_destroy(e);

  e = azl_engine_create(1u << 20, AZL_MAX_QUEUE, 64u);
  azl_engine_register_listener(e, "outer", on_emit_nested, NULL);
  azl_engine_emit(e, "outer", &kv);
  azl_engine_destroy(e);

  if (azl_bytecode_selftest() != 0)
    return 4;

  if (azl_compiler_selftest() != 0)
    return 5;

  printf("azl_core_engine_selftest: ok\n");
  return 0;
}

#endif /* AZL_CORE_ENGINE_SELFTEST */
