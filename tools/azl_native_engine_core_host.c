#define _GNU_SOURCE
#include "azl_native_engine_core_host.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

static const char *payload_cstr(const AzlEvent *ev, const char *key) {
  if (!ev || !key)
    return NULL;
  for (const AzlPayloadKV *p = ev->payload; p; p = p->next) {
    if (p->key && strcmp(p->key, key) == 0)
      return p->value ? p->value : "";
  }
  return NULL;
}

static void copy_or_empty(char *dst, size_t dstsz, const char *s) {
  if (!dst || dstsz == 0u)
    return;
  if (!s)
    s = "";
  size_t n = strlen(s);
  if (n >= dstsz)
    n = dstsz - 1u;
  memcpy(dst, s, n);
  dst[n] = '\0';
}

static int truthy_cstr(const char *s) {
  if (!s || !s[0])
    return 0;
  return (strcmp(s, "1") == 0 || strcasecmp(s, "true") == 0);
}

static void cb_stream_chunk(AzlEngine *eng, const AzlEvent *ev, void *ud) {
  (void)eng;
  (void)ud;
  const char *tag = payload_cstr(ev, "request_tag");
  const char *line = payload_cstr(ev, "line");
  if (!tag)
    tag = "";
  if (!line)
    line = "";
  printf("[net.http.stream_chunk] tag=%s line=%s\n", tag, line);
  fflush(stdout);
}

static void cb_complete(AzlEngine *eng, const AzlEvent *ev, void *ud) {
  (void)eng;
  (void)ud;
  const char *tag = payload_cstr(ev, "request_tag");
  printf("[net.http.complete] tag=%s\n", tag ? tag : "");
  fflush(stdout);
}

static void cb_error(AzlEngine *eng, const AzlEvent *ev, void *ud) {
  (void)eng;
  (void)ud;
  const char *tag = payload_cstr(ev, "request_tag");
  const char *code = payload_cstr(ev, "code");
  const char *msg = payload_cstr(ev, "message");
  fprintf(stderr, "[net.http.error] tag=%s code=%s msg=%s\n", tag ? tag : "", code ? code : "",
          msg ? msg : "");
  fflush(stderr);
}

static void cb_request_async(AzlEngine *eng, const AzlEvent *ev, void *ud) {
  AzlNativeCoreHost *h = (AzlNativeCoreHost *)ud;
  if (!h || !h->bridge)
    return;

  const char *url = payload_cstr(ev, "url");
  if (!url || !url[0]) {
    AzlPayloadKV k0 = {"request_tag", (char *)payload_cstr(ev, "request_tag"), NULL};
    if (!k0.value)
      k0.value = "";
    AzlPayloadKV k1 = {"code", "8", NULL};
    AzlPayloadKV k2 = {"message", "net.http.request_async: missing url", NULL};
    k0.next = &k1;
    k1.next = &k2;
    azl_engine_emit(eng, "net.http.error", &k0);
    return;
  }

  AzlHttpJob job;
  memset(&job, 0, sizeof(job));
  copy_or_empty(job.url, sizeof(job.url), url);
  const char *meth = payload_cstr(ev, "method");
  copy_or_empty(job.method, sizeof(job.method), meth && meth[0] ? meth : "GET");
  const char *body = payload_cstr(ev, "body");
  copy_or_empty(job.body, sizeof(job.body), body ? body : "");
  const char *rt = payload_cstr(ev, "request_tag");
  copy_or_empty(job.request_tag, sizeof(job.request_tag), rt && rt[0] ? rt : "default");

  const char *tmo = payload_cstr(ev, "timeout_sec");
  job.timeout_sec = (tmo && tmo[0]) ? atoi(tmo) : 30;
  if (job.timeout_sec <= 0)
    job.timeout_sec = 30;

  const char *sl = payload_cstr(ev, "stream_lines");
  job.split_response_lines = truthy_cstr(sl) ? 1 : 0;

  if (azl_bridge_submit_http(h->bridge, &job) != AZL_OK) {
    AzlPayloadKV k0 = {"request_tag", job.request_tag, NULL};
    AzlPayloadKV k1 = {"code", "2", NULL};
    AzlPayloadKV k2 = {"message", "bridge job queue full", NULL};
    k0.next = &k1;
    k1.next = &k2;
    azl_engine_emit(eng, "net.http.error", &k0);
  }
}

int azl_native_core_host_init(AzlNativeCoreHost *h) {
  if (!h)
    return -1;
  h->eng = NULL;
  h->bridge = NULL;
  h->eng = azl_engine_create((size_t)1u << 20, 1024u, 64u);
  if (!h->eng)
    return -1;
  h->bridge = azl_bridge_create(h->eng, NULL, 0);
  if (!h->bridge) {
    azl_engine_destroy(h->eng);
    h->eng = NULL;
    return -1;
  }
  return 0;
}

void azl_native_core_host_shutdown(AzlNativeCoreHost *h) {
  if (!h)
    return;
  if (h->bridge) {
    azl_bridge_destroy(h->bridge);
    h->bridge = NULL;
  }
  if (h->eng) {
    azl_engine_destroy(h->eng);
    h->eng = NULL;
  }
}

void azl_native_core_host_poll(AzlNativeCoreHost *h) {
  if (!h || !h->bridge || !h->eng)
    return;
  azl_bridge_poll(h->bridge);
  azl_engine_process(h->eng);
}

int azl_native_core_register_stdlib_net_http(AzlNativeCoreHost *h) {
  if (!h || !h->eng)
    return -1;
  if (azl_engine_register_listener(h->eng, "net.http.stream_chunk", cb_stream_chunk, h) != AZL_OK)
    return -1;
  if (azl_engine_register_listener(h->eng, "net.http.complete", cb_complete, h) != AZL_OK)
    return -1;
  if (azl_engine_register_listener(h->eng, "net.http.error", cb_error, h) != AZL_OK)
    return -1;
  if (azl_engine_register_listener(h->eng, "net.http.request_async", cb_request_async, h) != AZL_OK)
    return -1;
  /* Alias matching stdlib internal emit */
  if (azl_engine_register_listener(h->eng, "net.http._native_submit", cb_request_async, h) != AZL_OK)
    return -1;

  const char *root = getenv("AZL_REPO_ROOT");
  char path[512];
  if (root && root[0])
    snprintf(path, sizeof(path), "%s/azl/stdlib/net/http.azl", root);
  else
    snprintf(path, sizeof(path), "azl/stdlib/net/http.azl");
  FILE *fp = fopen(path, "r");
  if (fp) {
    fclose(fp);
    fprintf(stderr, "native-engine: native-core stdlib surface (C listeners) aligned with %s\n", path);
  } else {
    fprintf(stderr,
            "native-engine: native-core stdlib net.http listeners registered (optional %s not found)\n",
            path);
  }
  return 0;
}

void azl_native_core_emit_demo_ollama(AzlNativeCoreHost *h) {
  if (!h || !h->eng || !h->bridge)
    return;
  const char *oh = getenv("OLLAMA_HOST");
  if (!oh || !oh[0])
    oh = "http://127.0.0.1:11434";
  const char *model = getenv("AZL_NATIVE_CORE_DEMO_MODEL");
  if (!model || !model[0])
    model = "llama3.2:1b";

  char url[512];
  snprintf(url, sizeof(url), "%s/api/generate", oh);
  char body[1024];
  snprintf(body, sizeof(body),
           "{\"model\":\"%s\",\"prompt\":\"Say OK in one word.\",\"stream\":true,\"options\":{\"num_predict\":16}}",
           model);

  AzlPayloadKV k_url = {"url", url, NULL};
  AzlPayloadKV k_meth = {"method", "POST", &k_url};
  AzlPayloadKV k_body = {"body", body, &k_meth};
  AzlPayloadKV k_tag = {"request_tag", "ollama_demo", &k_body};
  AzlPayloadKV k_tmo = {"timeout_sec", "120", &k_tag};
  AzlPayloadKV k_sl = {"stream_lines", "true", &k_tmo};
  (void)azl_engine_emit(h->eng, "net.http.request_async", &k_sl);
}
