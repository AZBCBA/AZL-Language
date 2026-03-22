#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <ctype.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <strings.h>

#include "azl_native_engine_core_host.h"
#include "azl_compiler.h"
#include "azl_bytecode.h"

#ifdef AZL_WITH_LLAMACPP
#include "azl_gguf_infer_llamacpp.h"
#endif

/* Max bytes stored for one HTTP/1.x request (headers + body); excludes trailing NUL. */
#define ENGINE_HTTP_REQ_MAX (65535)

static volatile sig_atomic_t g_running = 1;

typedef struct {
  char bundle_path[1024];
  char combined_path[1024];
  char entry[256];
  int port;
  char host[64];
  char token[256];
  time_t started_at;
  unsigned long requests_total;
  pid_t runtime_pid;
  int runtime_exit_code;
  int runtime_running;
  long last_runtime_poll_ms;
  char runtime_error[512];
  char runtime_command[1024];
  int use_native_core;
  int native_core_demo;
  char compile_azl_path[1024];
  AzlNativeCoreHost native_core;
} EngineState;

static void on_signal(int sig) {
  (void)sig;
  g_running = 0;
}

/* Optional: run compiled .azl (emit hello → message) at startup; prints payload line. */
static void native_compile_hello_sink(AzlEngine *eng, const AzlEvent *ev, void *ud) {
  (void)eng;
  (void)ud;
  const char *msg = NULL;
  for (const AzlPayloadKV *p = ev->payload; p; p = p->next) {
    if (p->key && strcmp(p->key, "message") == 0) {
      msg = p->value ? p->value : "";
      break;
    }
  }
  if (msg) {
    printf("%s\n", msg);
    fflush(stdout);
  }
}

static const char *getenv_or(const char *k, const char *fallback) {
  const char *v = getenv(k);
  if (v == NULL || v[0] == '\0') return fallback;
  return v;
}

static long monotonic_millis(void) {
  struct timespec ts;
  if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
  return (long)(ts.tv_sec * 1000L + ts.tv_nsec / 1000000L);
}

static void safe_copy_line_value(char *dst, size_t dst_sz, const char *src) {
  if (dst_sz == 0) return;
  size_t n = strcspn(src, "\r\n");
  if (n >= dst_sz) n = dst_sz - 1;
  memcpy(dst, src, n);
  dst[n] = '\0';
}

static int write_all(int fd, const char *buf, size_t len) {
  size_t off = 0;
  while (off < len) {
    ssize_t n = write(fd, buf + off, len - off);
    if (n < 0) {
      if (errno == EINTR) continue;
      return -1;
    }
    if (n == 0) return -1;
    off += (size_t)n;
  }
  return 0;
}

/* Scan request headers (including status line) for Content-Length. Returns -1 if absent. */
static long header_block_content_length(const char *hdr, size_t hdr_len) {
  const char *p = hdr;
  const char *end = hdr + hdr_len;
  while (p < end) {
    const char *nl = memchr(p, '\n', (size_t)(end - p));
    if (!nl) break;
    size_t line_len = (size_t)(nl - p);
    if (line_len > 0 && nl[-1] == '\r') line_len--;
    if (line_len >= 15 && strncasecmp(p, "content-length:", 15) == 0) {
      const char *v = p + 15;
      const char *line_end = p + line_len;
      while (v < line_end && (*v == ' ' || *v == '\t')) v++;
      char *ep = NULL;
      long x = strtol(v, &ep, 10);
      if (ep != v && x >= 0) return x;
    }
    p = nl + 1;
  }
  return -1;
}

/*
 * Read one HTTP/1.x request (headers + body per Content-Length) into buf, NUL-terminated.
 * Returns total bytes stored, or -1 on I/O/protocol error.
 */
static ssize_t read_http_request_full(int cfd, char *buf, size_t cap) {
  if (cap < 512) return -1;
  const size_t max_body = cap > 8192 ? cap - 8192u : 0u;
  size_t total = 0;
  for (;;) {
    if (total >= cap) return -1;
    size_t chunk = cap - total;
    ssize_t r = read(cfd, buf + total, chunk);
    if (r < 0) {
      if (errno == EINTR) continue;
      return -1;
    }
    if (r == 0) {
      return -1;
    }
    total += (size_t)r;
    if (total > cap) return -1;
    buf[total] = '\0';

    const char *sep = strstr(buf, "\r\n\r\n");
    size_t header_end = 0;
    if (sep) {
      header_end = (size_t)(sep - buf + 4);
    } else {
      sep = strstr(buf, "\n\n");
      if (sep) header_end = (size_t)(sep - buf + 2);
    }
    if (header_end == 0) {
      if (total > 8192) return -1;
      continue;
    }
    if (header_end > total) return -1;

    long cl = header_block_content_length(buf, header_end);
    if (cl < 0) {
      return (ssize_t)total;
    }
    if (cl > (long)max_body) return -1;
    if ((size_t)cl > cap - header_end) return -1;
    size_t need = header_end + (size_t)cl;
    if (need > cap) return -1;
    while (total < need) {
      chunk = need - total;
      if (chunk > cap - total) return -1;
      r = read(cfd, buf + total, chunk);
      if (r < 0) {
        if (errno == EINTR) continue;
        return -1;
      }
      if (r == 0) return -1;
      total += (size_t)r;
      if (total > cap) return -1;
    }
    buf[total] = '\0';
    return (ssize_t)total;
  }
}

static void ensure_azl_dir(void) {
  struct stat st;
  if (stat(".azl", &st) == 0 && S_ISDIR(st.st_mode)) return;
  mkdir(".azl", 0755);
}

/* Create intermediate directories (POSIX mkdir -p subset). */
static int mkdir_p_path(const char *path) {
  char buf[512];
  size_t n = snprintf(buf, sizeof buf, "%s", path);
  if (n == 0 || n >= sizeof buf) return -1;
  for (size_t i = 1; i < n; i++) {
    if (buf[i] != '/') continue;
    buf[i] = '\0';
    if (mkdir(buf, 0755) != 0 && errno != EEXIST) return -1;
    buf[i] = '/';
  }
  if (mkdir(buf, 0755) != 0 && errno != EEXIST) return -1;
  return 0;
}

static const char *azl_state_dir(void) {
  const char *e = getenv("AZL_STATE_DIR");
  if (e && e[0]) return e;
  return ".azl/state";
}

static void append_run_record(const EngineState *st) {
  ensure_azl_dir();
  const char *sd = azl_state_dir();
  if (mkdir_p_path(sd) != 0) {
    fprintf(stderr, "native-engine: mkdir AZL_STATE_DIR %s: %s\n", sd, strerror(errno));
  }
  char path[512];
  snprintf(path, sizeof path, "%s/native_engine_runs.jsonl", sd);
  FILE *fp = fopen(path, "a");
  if (!fp) return;
  fprintf(fp,
          "{\"ts\":%ld,\"bundle\":\"%s\",\"combined\":\"%s\",\"entry\":\"%s\","
          "\"port\":%d,\"host\":\"%s\"}\n",
          (long)time(NULL), st->bundle_path, st->combined_path, st->entry, st->port, st->host);
  fclose(fp);
}

static int read_bootstrap_metadata(const char *bundle, char *combined, size_t combined_sz, char *entry, size_t entry_sz) {
  FILE *fp = fopen(bundle, "r");
  if (!fp) {
    fprintf(stderr, "native-engine: cannot open bundle %s: %s\n", bundle, strerror(errno));
    return 2;
  }
  char line[2048];
  if (!fgets(line, sizeof(line), fp)) {
    fclose(fp);
    fprintf(stderr, "native-engine: empty bundle\n");
    return 3;
  }
  if (strncmp(line, "# AZL-BOOTSTRAP v1", 18) != 0) {
    fclose(fp);
    fprintf(stderr, "native-engine: invalid bootstrap header\n");
    return 4;
  }
  combined[0] = '\0';
  entry[0] = '\0';
  while (fgets(line, sizeof(line), fp)) {
    if (strncmp(line, "## COMBINED: ", 13) == 0) {
      safe_copy_line_value(combined, combined_sz, line + 13);
    } else if (strncmp(line, "## ENTRY: ", 10) == 0) {
      safe_copy_line_value(entry, entry_sz, line + 10);
    } else if (line[0] == '\n' || line[0] == '\r') {
      break;
    }
  }
  fclose(fp);
  if (combined[0] == '\0' || entry[0] == '\0') {
    fprintf(stderr, "native-engine: missing COMBINED/ENTRY metadata\n");
    return 5;
  }
  return 0;
}

static void update_runtime_state(EngineState *st) {
  long now_ms = monotonic_millis();
  if (st->last_runtime_poll_ms > 0 && now_ms > 0) {
    if ((now_ms - st->last_runtime_poll_ms) < 500) return;
  }
  st->last_runtime_poll_ms = now_ms;

  if (st->use_native_core) {
    st->runtime_running = 1;
    return;
  }

  if (st->runtime_pid <= 0) {
    st->runtime_running = 0;
    return;
  }
  int status = 0;
  pid_t w = waitpid(st->runtime_pid, &status, WNOHANG);
  if (w == 0) {
    st->runtime_running = 1;
    return;
  }
  if (w == st->runtime_pid) {
    st->runtime_running = 0;
    if (WIFEXITED(status)) {
      st->runtime_exit_code = WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
      st->runtime_exit_code = 128 + WTERMSIG(status);
    } else {
      st->runtime_exit_code = 1;
    }
    st->runtime_pid = -1;
    return;
  }
  if (errno != ECHILD) {
    st->runtime_running = 0;
    st->runtime_exit_code = 1;
    safe_copy_line_value(st->runtime_error, sizeof(st->runtime_error), "runtime_waitpid_failed");
  }
}

static int start_runtime_pipeline(EngineState *st) {
  const char *cmd = getenv("AZL_NATIVE_RUNTIME_CMD");
  if (!cmd || cmd[0] == '\0') {
    snprintf(st->runtime_error, sizeof(st->runtime_error),
             "missing AZL_NATIVE_RUNTIME_CMD");
    return 14;
  }

  setenv("AZL_BOOTSTRAP_BUNDLE", st->bundle_path, 1);
  setenv("AZL_COMBINED_PATH", st->combined_path, 1);
  setenv("AZL_ENTRY", st->entry, 1);
  snprintf(st->runtime_command, sizeof(st->runtime_command), "%s", cmd);

  pid_t pid = fork();
  if (pid < 0) {
    snprintf(st->runtime_error, sizeof(st->runtime_error),
             "fork failed: %s", strerror(errno));
    return 15;
  }
  if (pid == 0) {
    execl("/bin/sh", "sh", "-lc", cmd, (char *)NULL);
    _exit(127);
  }

  st->runtime_pid = pid;
  st->runtime_running = 1;
  st->runtime_exit_code = 0;
  st->runtime_error[0] = '\0';
  return 0;
}

/* Minimal JSON: extract "field":"..." string value (supports \\ and \"). */
static int json_extract_string_field(const char *body, const char *field, char *out, size_t outsz) {
  char key[64];
  (void)snprintf(key, sizeof(key), "\"%s\"", field);
  const char *k = strstr(body, key);
  if (!k) return -1;
  const char *c = strchr(k + strlen(key), ':');
  if (!c) return -1;
  c++;
  while (*c == ' ' || *c == '\t' || *c == '\n' || *c == '\r') c++;
  if (*c != '"') return -1;
  c++;
  size_t j = 0;
  while (*c && j + 1 < outsz) {
    if (*c == '\\') {
      c++;
      if (*c == 'n') out[j++] = '\n';
      else if (*c == 't') out[j++] = '\t';
      else if (*c == 'r') { /* skip */ }
      else if (*c) out[j++] = *c;
      if (*c) c++;
      continue;
    }
    if (*c == '"') break;
    out[j++] = *c++;
  }
  out[j] = '\0';
  return 0;
}

static int json_extract_int_field(const char *body, const char *field, int *out, int default_val) {
  char key[64];
  (void)snprintf(key, sizeof(key), "\"%s\"", field);
  const char *k = strstr(body, key);
  if (!k) {
    *out = default_val;
    return -1;
  }
  const char *c = strchr(k + strlen(key), ':');
  if (!c) {
    *out = default_val;
    return -1;
  }
  c++;
  while (*c == ' ' || *c == '\t') c++;
  *out = atoi(c);
  if (*out <= 0) *out = default_val;
  return 0;
}

static void write_response(int fd, int status, const char *status_text, const char *body);

static void json_escape_text(const char *in, char *out, size_t outsz) {
  size_t j = 0;
  if (!in) {
    out[0] = '\0';
    return;
  }
  for (size_t i = 0; in[i] && j + 2 < outsz; i++) {
    unsigned char c = (unsigned char)in[i];
    if (c == '"' || c == '\\') {
      out[j++] = '\\';
      out[j++] = (char)c;
    } else if (c == '\n') {
      out[j++] = '\\';
      out[j++] = 'n';
    } else if (c == '\r') {
      /* skip */
    } else if (c < 32) {
      /* skip control */
    } else {
      out[j++] = (char)c;
    }
  }
  out[j] = '\0';
}

/* llama.cpp n_gpu_layers: AZL_LLAMA_NGL wins; else AZL_LLM_GPU_LAYERS (model-agnostic). */
static int azl_llm_n_gpu_layers_from_env(void) {
  const char *a = getenv("AZL_LLAMA_NGL");
  if (a && a[0] != '\0') return atoi(a);
  const char *b = getenv("AZL_LLM_GPU_LAYERS");
  if (b && b[0] != '\0') return atoi(b);
  return 0;
}

static int azl_llm_ngl_env_is_set(void) {
  const char *a = getenv("AZL_LLAMA_NGL");
  if (a && a[0] != '\0') return 1;
  const char *b = getenv("AZL_LLM_GPU_LAYERS");
  if (b && b[0] != '\0') return 1;
  return 0;
}

#define GGUF_READ_MAX (192 * 1024)
#define CHAT_SESS_MAX 64
#define CHAT_SESS_ID_MAX 96
#define CHAT_SESS_HIST_MAX (96 * 1024)
#define CHAT_SESS_DIR ".azl/chat_sessions"

typedef struct {
  int in_use;
  int loaded_from_disk;
  char id[CHAT_SESS_ID_MAX];
  char history[CHAT_SESS_HIST_MAX];
} ChatSession;

static ChatSession g_chat_sessions[CHAT_SESS_MAX];

static int session_id_is_valid(const char *sid) {
  if (!sid || sid[0] == '\0') return 0;
  size_t n = strlen(sid);
  if (n == 0 || n >= CHAT_SESS_ID_MAX) return 0;
  for (size_t i = 0; i < n; i++) {
    unsigned char c = (unsigned char)sid[i];
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' ||
        c == '-' || c == '.') {
      continue;
    }
    return 0;
  }
  return 1;
}

static void ensure_chat_sessions_dir(void) {
  ensure_azl_dir();
  struct stat st;
  if (stat(CHAT_SESS_DIR, &st) == 0 && S_ISDIR(st.st_mode)) return;
  (void)mkdir(CHAT_SESS_DIR, 0755);
}

static int chat_session_build_path(const char *sid, char *out, size_t outsz) {
  if (!session_id_is_valid(sid)) return -1;
  int n = snprintf(out, outsz, CHAT_SESS_DIR "/%s.txt", sid);
  if (n <= 0 || (size_t)n >= outsz) return -1;
  return 0;
}

static void chat_session_load_history(ChatSession *sess) {
  if (!sess || sess->loaded_from_disk) return;
  sess->loaded_from_disk = 1;
  char p[512];
  if (chat_session_build_path(sess->id, p, sizeof(p)) != 0) return;
  FILE *fp = fopen(p, "r");
  if (!fp) return;
  size_t rn = fread(sess->history, 1, sizeof(sess->history) - 1, fp);
  fclose(fp);
  sess->history[rn] = '\0';
}

static void chat_session_save_history(const ChatSession *sess) {
  if (!sess) return;
  char p[512];
  if (chat_session_build_path(sess->id, p, sizeof(p)) != 0) return;
  ensure_chat_sessions_dir();
  FILE *fp = fopen(p, "w");
  if (!fp) return;
  (void)fwrite(sess->history, 1, strlen(sess->history), fp);
  fclose(fp);
}

static void chat_session_reset_history(ChatSession *sess) {
  if (!sess) return;
  sess->history[0] = '\0';
  char p[512];
  if (chat_session_build_path(sess->id, p, sizeof(p)) == 0) (void)unlink(p);
}

static ChatSession *chat_session_get_or_create(const char *sid) {
  if (!session_id_is_valid(sid)) return NULL;
  for (int i = 0; i < CHAT_SESS_MAX; i++) {
    if (g_chat_sessions[i].in_use && strcmp(g_chat_sessions[i].id, sid) == 0) {
      chat_session_load_history(&g_chat_sessions[i]);
      return &g_chat_sessions[i];
    }
  }
  for (int i = 0; i < CHAT_SESS_MAX; i++) {
    if (!g_chat_sessions[i].in_use) {
      g_chat_sessions[i].in_use = 1;
      g_chat_sessions[i].loaded_from_disk = 0;
      (void)snprintf(g_chat_sessions[i].id, sizeof(g_chat_sessions[i].id), "%s", sid);
      g_chat_sessions[i].history[0] = '\0';
      chat_session_load_history(&g_chat_sessions[i]);
      return &g_chat_sessions[i];
    }
  }
  return NULL;
}

static int policy_decide_prompt(const char *prompt, char *reason, size_t reason_sz) {
  int max_chars = 4000;
  const char *mc = getenv("AZL_POLICY_MAX_PROMPT_CHARS");
  if (mc && mc[0] != '\0') {
    int v = atoi(mc);
    if (v > 0) max_chars = v;
  }
  int block_secrets = 1;
  const char *bs = getenv("AZL_POLICY_BLOCK_SECRETS");
  if (bs && bs[0] == '0') block_secrets = 0;

  char lower[12288];
  size_t plen = strlen(prompt);
  if (plen >= sizeof(lower)) plen = sizeof(lower) - 1;
  for (size_t i = 0; i < plen; i++) {
    char c = prompt[i];
    if (c >= 'A' && c <= 'Z') c = (char)(c - 'A' + 'a');
    lower[i] = c;
  }
  lower[plen] = '\0';
  (void)snprintf(reason, reason_sz, "%s", "allowed");
  if ((int)plen > max_chars) {
    (void)snprintf(reason, reason_sz, "%s", "prompt_too_long");
    return 1;
  }
  if (strstr(lower, "ignore previous instructions") != NULL) {
    (void)snprintf(reason, reason_sz, "%s", "prompt_injection_pattern");
    return 1;
  }
  if (block_secrets &&
      (strstr(lower, "api_key") != NULL || strstr(lower, "password") != NULL ||
       strstr(lower, "private key") != NULL || strstr(lower, "secret token") != NULL)) {
    (void)snprintf(reason, reason_sz, "%s", "secret_exfiltration_pattern");
    return 1;
  }
  return 0;
}

static void policy_audit_append(const char *decision, const char *reason, size_t prompt_chars) {
  ensure_azl_dir();
  const char *sd = azl_state_dir();
  if (mkdir_p_path(sd) != 0) {
    fprintf(stderr, "native-engine: mkdir AZL_STATE_DIR %s: %s\n", sd, strerror(errno));
  }
  char apath[512];
  snprintf(apath, sizeof apath, "%s/policy_infer_audit.jsonl", sd);
  FILE *af = fopen(apath, "a");
  if (!af) return;
  char esc_reason[256];
  json_escape_text(reason, esc_reason, sizeof(esc_reason));
  fprintf(af,
          "{\"ts\":%ld,\"path\":\"/api/llm/policy_infer\",\"decision\":\"%s\",\"reason\":\"%s\","
          "\"prompt_chars\":%zu}\n",
          (long)time(NULL), decision, esc_reason, prompt_chars);
  fclose(af);
}

/* Drop llama-cli interactive header up through the "> ..." prompt line (stdout is a TTY-shaped transcript). */
static void trim_llama_cli_stdout_prefix(char *s) {
  if (!s || !s[0]) return;
  char *pa = strstr(s, "\n> ");
  if (!pa) return;
  char *body = strchr(pa + 2, '\n');
  if (!body) return;
  body++;
  while (*body == '\n') body++;
  if (*body && body != s) memmove(s, body, strlen(body) + 1);
}

/* Strip llama-cli footer lines that leak to stdout (timings, "Exiting..."). Use the *last* "[ Prompt:"
 * match so we do not truncate model text that happens to contain that substring earlier. */
static void trim_llama_cli_stdout_noise(char *s) {
  if (!s || !s[0]) return;
  char *last = NULL;
  for (char *scan = s; (scan = strstr(scan, "[ Prompt:")) != NULL;) {
    last = scan;
    scan += 1;
  }
  if (last) {
    char *line = last;
    while (line > s && line[-1] != '\n') line--;
    *line = '\0';
  }
  char *ex = strstr(s, "Exiting...");
  if (ex) {
    char *line = ex;
    while (line > s && line[-1] != '\n') line--;
    *line = '\0';
  }
  size_t n = strlen(s);
  while (n > 0 && isspace((unsigned char)s[n - 1])) {
    s[n - 1] = '\0';
    n--;
  }
}

static int gguf_infer_text(const char *prompt, int n_predict, char *out, size_t outsz, char *backend,
                           size_t backend_sz, char *err, size_t err_sz) {
  if (!prompt || !out || outsz == 0) return -1;
  const char *gguf = getenv("AZL_GGUF_PATH");
  if (!gguf || gguf[0] == '\0') {
    (void)snprintf(err, err_sz, "%s", "AZL_GGUF_PATH_unset");
    return -2;
  }
  struct stat gst;
  if (stat(gguf, &gst) != 0 || !S_ISREG(gst.st_mode)) {
    (void)snprintf(err, err_sz, "%s", "AZL_GGUF_PATH_not_a_file");
    return -3;
  }
  if (n_predict < 1) n_predict = 1;
  if (n_predict > 8192) n_predict = 8192;
#ifdef AZL_WITH_LLAMACPP
  {
    const char *force_cli = getenv("AZL_GGUF_USE_CLI");
    if (!(force_cli && force_cli[0] == '1')) {
      char outb[GGUF_READ_MAX + 1];
      char errb[512];
      int ir = azl_llamacpp_gguf_infer(gguf, prompt, n_predict, outb, sizeof(outb), errb, sizeof(errb));
      if (ir != 0) {
        (void)snprintf(err, err_sz, "llamacpp_infer_failed:%d:%s", ir, errb);
        return -4;
      }
      (void)snprintf(out, outsz, "%s", outb);
      (void)snprintf(backend, backend_sz, "%s", "llama_cpp");
      return 0;
    }
  }
#endif
  char tpl[] = "/tmp/azl_gguf_p_XXXXXX";
  int pfd = mkstemp(tpl);
  if (pfd < 0) {
    (void)snprintf(err, err_sz, "%s", "mkstemp_failed");
    return -5;
  }
  size_t plen = strlen(prompt);
  if (write_all(pfd, prompt, plen) != 0) {
    close(pfd);
    unlink(tpl);
    (void)snprintf(err, err_sz, "%s", "prompt_write_failed");
    return -6;
  }
  close(pfd);
  const char *cli = getenv("AZL_LLAMA_CLI");
  if (!cli || cli[0] == '\0') cli = "llama-cli";
  char nbuf[32];
  (void)snprintf(nbuf, sizeof(nbuf), "%d", n_predict);
  int pipefd[2];
  if (pipe(pipefd) != 0) {
    unlink(tpl);
    (void)snprintf(err, err_sz, "%s", "pipe_failed");
    return -7;
  }
  pid_t pid = fork();
  if (pid < 0) {
    close(pipefd[0]);
    close(pipefd[1]);
    unlink(tpl);
    (void)snprintf(err, err_sz, "%s", "fork_failed");
    return -8;
  }
  if (pid == 0) {
    close(pipefd[0]);
    int dn = open("/dev/null", O_WRONLY);
    if (dn >= 0) {
      (void)dup2(dn, STDERR_FILENO);
      close(dn);
    }
    if (dup2(pipefd[1], STDOUT_FILENO) < 0) _exit(126);
    close(pipefd[1]);
    const char *use_no_cnv = getenv("AZL_LLAMA_SKIP_NO_CNV");
    const char *simple_io = getenv("AZL_LLAMA_SIMPLE_IO");
    int cli_ngl = azl_llm_n_gpu_layers_from_env();
    char ngbuf[32];
    char *argv[24];
    int ai = 0;
    argv[ai++] = (char *)cli;
    argv[ai++] = "-m";
    argv[ai++] = (char *)gguf;
    if (cli_ngl > 0) {
      (void)snprintf(ngbuf, sizeof(ngbuf), "%d", cli_ngl);
      argv[ai++] = "-ngl";
      argv[ai++] = ngbuf;
    }
    argv[ai++] = "-f";
    argv[ai++] = tpl;
    argv[ai++] = "-n";
    argv[ai++] = nbuf;
    if (!(use_no_cnv && use_no_cnv[0] == '1')) argv[ai++] = "-no-cnv";
    if (simple_io && simple_io[0] == '1') argv[ai++] = "--simple-io";
    /* Newer llama-cli enables conversation/interactive mode when a chat template exists; without this,
     * -f prompt can wait for stdin forever (breaks gguf_infer + benchmarks). */
    argv[ai++] = "--single-turn";
    argv[ai++] = "--no-display-prompt";
    argv[ai++] = "--no-warmup";
    argv[ai++] = NULL;
    (void)execvp(cli, argv);
    _exit(127);
  }
  close(pipefd[1]);
  char raw[GGUF_READ_MAX + 1];
  size_t total = 0;
  for (;;) {
    ssize_t rn = read(pipefd[0], raw + total, GGUF_READ_MAX - total);
    if (rn <= 0) break;
    total += (size_t)rn;
    if (total >= GGUF_READ_MAX) break;
  }
  close(pipefd[0]);
  int wst = 0;
  (void)waitpid(pid, &wst, 0);
  unlink(tpl);
  raw[total] = '\0';
  if (!WIFEXITED(wst) || WEXITSTATUS(wst) != 0) {
    (void)snprintf(err, err_sz, "%s", "llama_cli_failed");
    return -9;
  }
  trim_llama_cli_stdout_prefix(raw);
  trim_llama_cli_stdout_noise(raw);
  (void)snprintf(out, outsz, "%s", raw);
  (void)snprintf(backend, backend_sz, "%s", "llama_cli");
  return 0;
}

static int policy_infer_text(const char *prompt, int n_predict, char *out, size_t outsz, char *backend,
                             size_t backend_sz, char *reason, size_t reason_sz, char *err, size_t err_sz) {
  int blocked = policy_decide_prompt(prompt, reason, reason_sz);
  policy_audit_append(blocked ? "blocked" : "allowed", reason, strlen(prompt));
  if (blocked) return -10;
  return gguf_infer_text(prompt, n_predict, out, outsz, backend, backend_sz, err, err_sz);
}

static int request_json_has_true_flag(const char *body, const char *field) {
  if (!body || !field) return 0;
  char pat[96];
  (void)snprintf(pat, sizeof(pat), "\"%s\":true", field);
  if (strstr(body, pat)) return 1;
  (void)snprintf(pat, sizeof(pat), "\"%s\": true", field);
  if (strstr(body, pat)) return 1;
  return 0;
}

static void trim_ascii_whitespace(char *s) {
  if (!s || s[0] == '\0') return;
  size_t n = strlen(s);
  size_t i = 0;
  while (i < n && isspace((unsigned char)s[i])) i++;
  if (i > 0) {
    memmove(s, s + i, n - i + 1);
    n = strlen(s);
  }
  while (n > 0 && isspace((unsigned char)s[n - 1])) {
    s[n - 1] = '\0';
    n--;
  }
}

static void trim_end_of_text_marker(char *s) {
  if (!s || s[0] == '\0') return;
  const char *marker = "[end of text]";
  size_t ml = strlen(marker);
  size_t n = strlen(s);
  while (n > 0 && isspace((unsigned char)s[n - 1])) n--;
  if (n >= ml && strncmp(s + (n - ml), marker, ml) == 0) {
    s[n - ml] = '\0';
  }
  trim_ascii_whitespace(s);
}

/* Remove prompt echo / wrappers from chat answers before persisting and returning. */
static void sanitize_chat_answer(const char *prompt, char *answer, size_t answer_cap) {
  (void)answer_cap;
  if (!answer || answer[0] == '\0') return;
  trim_ascii_whitespace(answer);

  if (prompt && prompt[0] != '\0') {
    size_t pl = strlen(prompt);
    if (strncmp(answer, prompt, pl) == 0) {
      memmove(answer, answer + pl, strlen(answer + pl) + 1);
    }
  }

  /* llama-cli may echo a transcript: "Conversation:" / "User:" lines and one or more "Assistant:"
   * markers. Use the last "\nAssistant:" so we keep the real completion (not an empty slot). */
  if (strstr(answer, "Conversation:") != NULL &&
      (strstr(answer, "System:") != NULL || strstr(answer, "User:") != NULL)) {
    char *scan = answer;
    char *last = NULL;
    while ((scan = strstr(scan, "\nAssistant:")) != NULL) {
      last = scan;
      scan += 11;
    }
    if (last) {
      char *body = last + 11;
      while (*body == '\n' || *body == '\r') body++;
      if (strncmp(body, "Assistant:", 10) == 0) {
        body += 10;
        while (*body == '\n' || *body == '\r' || isspace((unsigned char)*body)) body++;
      }
      memmove(answer, body, strlen(body) + 1);
    }
  }

  trim_ascii_whitespace(answer);
  if (strncmp(answer, "Assistant:", 10) == 0) {
    memmove(answer, answer + 10, strlen(answer + 10) + 1);
  }
  trim_end_of_text_marker(answer);
}

static void handle_gguf_infer(int cfd, const char *req, ssize_t n, EngineState *st) {
  (void)st;
  const char *body_start = strstr(req, "\r\n\r\n");
  if (body_start) body_start += 4;
  else {
    body_start = strstr(req, "\n\n");
    if (body_start) body_start += 2;
    else body_start = req;
  }
  size_t body_len = (size_t)(req + n - body_start);
  if (body_len > 16384) body_len = 16384;
  char *body_copy = malloc(body_len + 1);
  if (!body_copy) {
    write_response(cfd, 500, "Internal Server Error", "{\"ok\":false,\"error\":\"oom\"}");
    return;
  }
  memcpy(body_copy, body_start, body_len);
  body_copy[body_len] = '\0';

  char prompt[12288] = {0};
  if (json_extract_string_field(body_copy, "prompt", prompt, sizeof(prompt)) != 0) {
    free(body_copy);
    write_response(cfd, 400, "Bad Request", "{\"ok\":false,\"error\":\"missing_prompt_json\"}");
    return;
  }
  int n_predict = 64;
  (void)json_extract_int_field(body_copy, "n_predict", &n_predict, 64);
  free(body_copy);
  char out[GGUF_READ_MAX + 1];
  char backend[32];
  char err[512];
  int gr = gguf_infer_text(prompt, n_predict, out, sizeof(out), backend, sizeof(backend), err, sizeof(err));
  if (gr != 0) {
    char eesc[1024];
    json_escape_text(err, eesc, sizeof(eesc));
    char resp[1400];
    (void)snprintf(resp, sizeof(resp),
                   "{\"ok\":false,\"error\":\"gguf_infer_failed\",\"code\":%d,\"message\":\"%s\","
                   "\"hint\":\"Check AZL_GGUF_PATH, llama-cli/llama.cpp, and model compatibility.\"}",
                   gr, eesc);
    write_response(cfd, 502, "Bad Gateway", resp);
    return;
  }
  size_t esc_cap = GGUF_READ_MAX * 2 + 16;
  char *esc = malloc(esc_cap);
  if (!esc) {
    write_response(cfd, 500, "Internal Server Error", "{\"ok\":false,\"error\":\"oom\"}");
    return;
  }
  json_escape_text(out, esc, esc_cap);
  size_t resp_cap = strlen(esc) + 256;
  char *resp = malloc(resp_cap);
  if (!resp) {
    free(esc);
    write_response(cfd, 500, "Internal Server Error", "{\"ok\":false,\"error\":\"oom\"}");
    return;
  }
  (void)snprintf(resp, resp_cap, "{\"ok\":true,\"backend\":\"%s\",\"text\":\"%s\"}", backend, esc);
  free(esc);
  write_response(cfd, 200, "OK", resp);
  free(resp);
}

static void handle_policy_infer(int cfd, const char *req, ssize_t n, EngineState *st) {
  (void)st;
  const char *body_start = strstr(req, "\r\n\r\n");
  if (body_start) body_start += 4;
  else {
    body_start = strstr(req, "\n\n");
    if (body_start) body_start += 2;
    else body_start = req;
  }
  size_t body_len = (size_t)(req + n - body_start);
  if (body_len > 16384) body_len = 16384;
  char *body_copy = malloc(body_len + 1);
  if (!body_copy) {
    write_response(cfd, 500, "Internal Server Error", "{\"ok\":false,\"error\":\"oom\"}");
    return;
  }
  memcpy(body_copy, body_start, body_len);
  body_copy[body_len] = '\0';

  char prompt[12288] = {0};
  if (json_extract_string_field(body_copy, "prompt", prompt, sizeof(prompt)) != 0) {
    free(body_copy);
    write_response(cfd, 400, "Bad Request", "{\"ok\":false,\"error\":\"missing_prompt_json\"}");
    return;
  }
  free(body_copy);

  int n_predict = 64;
  (void)json_extract_int_field(body_start, "n_predict", &n_predict, 64);
  char out[GGUF_READ_MAX + 1];
  char backend[32];
  char reason[256];
  char err[512];
  int pr = policy_infer_text(prompt, n_predict, out, sizeof(out), backend, sizeof(backend), reason,
                             sizeof(reason), err, sizeof(err));
  if (pr == -10) {
    char esc_reason[256];
    json_escape_text(reason, esc_reason, sizeof(esc_reason));
    char resp[1024];
    (void)snprintf(resp, sizeof(resp),
                   "{\"ok\":false,\"error\":\"policy_blocked\",\"reason\":\"%s\","
                   "\"hint\":\"Adjust prompt or policy env AZL_POLICY_* if intended.\"}",
                   esc_reason);
    write_response(cfd, 403, "Forbidden", resp);
    return;
  }
  if (pr != 0) {
    char esc_err[1024];
    json_escape_text(err, esc_err, sizeof(esc_err));
    char resp[1500];
    (void)snprintf(resp, sizeof(resp),
                   "{\"ok\":false,\"error\":\"policy_infer_failed\",\"code\":%d,\"message\":\"%s\"}",
                   pr, esc_err);
    write_response(cfd, 502, "Bad Gateway", resp);
    return;
  }
  size_t esc_cap = GGUF_READ_MAX * 2 + 16;
  char *esc_text = malloc(esc_cap);
  if (!esc_text) {
    write_response(cfd, 500, "Internal Server Error", "{\"ok\":false,\"error\":\"oom\"}");
    return;
  }
  json_escape_text(out, esc_text, esc_cap);
  char esc_reason[256];
  json_escape_text(reason, esc_reason, sizeof(esc_reason));
  size_t resp_cap = strlen(esc_text) + 512;
  char *resp = malloc(resp_cap);
  if (!resp) {
    free(esc_text);
    write_response(cfd, 500, "Internal Server Error", "{\"ok\":false,\"error\":\"oom\"}");
    return;
  }
  (void)snprintf(resp, resp_cap,
                 "{\"ok\":true,\"backend\":\"%s\",\"policy\":\"allowed\",\"reason\":\"%s\",\"text\":\"%s\"}",
                 backend, esc_reason, esc_text);
  free(esc_text);
  write_response(cfd, 200, "OK", resp);
  free(resp);
}

static void handle_chat_session(int cfd, const char *req, ssize_t n, EngineState *st) {
  (void)st;
  const char *body_start = strstr(req, "\r\n\r\n");
  if (body_start) body_start += 4;
  else {
    body_start = strstr(req, "\n\n");
    if (body_start) body_start += 2;
    else body_start = req;
  }
  size_t body_len = (size_t)(req + n - body_start);
  if (body_len > 32768) body_len = 32768;
  char *body_copy = malloc(body_len + 1);
  if (!body_copy) {
    write_response(cfd, 500, "Internal Server Error", "{\"ok\":false,\"error\":\"oom\"}");
    return;
  }
  memcpy(body_copy, body_start, body_len);
  body_copy[body_len] = '\0';

  char sid[CHAT_SESS_ID_MAX] = {0};
  char message[8192] = {0};
  if (json_extract_string_field(body_copy, "session_id", sid, sizeof(sid)) != 0) {
    free(body_copy);
    write_response(cfd, 400, "Bad Request", "{\"ok\":false,\"error\":\"missing_session_id\"}");
    return;
  }
  if (!session_id_is_valid(sid)) {
    free(body_copy);
    write_response(cfd, 400, "Bad Request",
                   "{\"ok\":false,\"error\":\"invalid_session_id\",\"hint\":\"Use [A-Za-z0-9_.-], max 95 chars.\"}");
    return;
  }
  if (json_extract_string_field(body_copy, "message", message, sizeof(message)) != 0) {
    free(body_copy);
    write_response(cfd, 400, "Bad Request", "{\"ok\":false,\"error\":\"missing_message\"}");
    return;
  }
  int n_predict = 512;
  (void)json_extract_int_field(body_copy, "n_predict", &n_predict, 512);
  if (n_predict < 1) n_predict = 1;
  if (n_predict > 2048) n_predict = 2048;
  int reset = request_json_has_true_flag(body_copy, "reset");
  free(body_copy);

  ChatSession *sess = chat_session_get_or_create(sid);
  if (!sess) {
    write_response(cfd, 503, "Service Unavailable", "{\"ok\":false,\"error\":\"session_capacity_exceeded\"}");
    return;
  }
  if (reset) chat_session_reset_history(sess);

  size_t hlen = strlen(sess->history);
  size_t mlen = strlen(message);
  if (hlen + mlen + 96 >= sizeof(sess->history)) {
    size_t keep = sizeof(sess->history) / 2;
    if (hlen > keep) {
      memmove(sess->history, sess->history + (hlen - keep), keep);
      sess->history[keep] = '\0';
      hlen = keep;
    } else {
      sess->history[0] = '\0';
      hlen = 0;
    }
  }
  (void)snprintf(sess->history + hlen, sizeof(sess->history) - hlen, "\nUser: %s", message);

  /* History can be up to CHAT_SESS_HIST_MAX; stack snprintf into 12KiB tripped -Werror=format-truncation on -Os CI. */
  static const char kChatWrapPrefix[] =
      "System: You are a helpful assistant in AZL terminal chat. Respond naturally to what the user wrote "
      "(including greetings and typos). Follow safety/policy; do not leak secrets. Prefer clear, complete "
      "sentences—do not stop mid-phrase.\n"
      "Conversation:\n";
  static const char kChatWrapSuffix[] = "\nAssistant:";
  const size_t wp = sizeof(kChatWrapPrefix) - 1u;
  const size_t ws = sizeof(kChatWrapSuffix) - 1u;
  const size_t hl = strlen(sess->history);
  const size_t need = wp + hl + ws + 1u;
  if (need < wp + ws + 1u) {
    write_response(cfd, 500, "Internal Server Error", "{\"ok\":false,\"error\":\"chat_prompt_size_overflow\"}");
    return;
  }
  char *prompt = malloc(need);
  if (!prompt) {
    write_response(cfd, 500, "Internal Server Error", "{\"ok\":false,\"error\":\"oom\"}");
    return;
  }
  memcpy(prompt, kChatWrapPrefix, wp);
  memcpy(prompt + wp, sess->history, hl);
  memcpy(prompt + wp + hl, kChatWrapSuffix, ws + 1u);

  char answer[GGUF_READ_MAX + 1];
  char backend[32];
  char reason[256];
  char err[512];
  int ir = policy_infer_text(prompt, n_predict, answer, sizeof(answer), backend, sizeof(backend), reason,
                             sizeof(reason), err, sizeof(err));
  if (ir == -10) {
    char esc_reason[256];
    json_escape_text(reason, esc_reason, sizeof(esc_reason));
    char resp[1024];
    (void)snprintf(resp, sizeof(resp),
                   "{\"ok\":false,\"error\":\"policy_blocked\",\"reason\":\"%s\","
                   "\"hint\":\"Adjust prompt or AZL_POLICY_* if intended.\"}",
                   esc_reason);
    write_response(cfd, 403, "Forbidden", resp);
    free(prompt);
    return;
  }
  if (ir != 0) {
    char esc_err[1024];
    json_escape_text(err, esc_err, sizeof(esc_err));
    char resp[1500];
    (void)snprintf(resp, sizeof(resp), "{\"ok\":false,\"error\":\"chat_infer_failed\",\"code\":%d,\"message\":\"%s\"}",
                   ir, esc_err);
    write_response(cfd, 502, "Bad Gateway", resp);
    free(prompt);
    return;
  }
  sanitize_chat_answer(prompt, answer, sizeof(answer));
  free(prompt);
  hlen = strlen(sess->history);
  size_t alen = strlen(answer);
  if (hlen + alen + 20 >= sizeof(sess->history)) {
    size_t keep = sizeof(sess->history) / 2;
    if (hlen > keep) {
      memmove(sess->history, sess->history + (hlen - keep), keep);
      sess->history[keep] = '\0';
    } else {
      sess->history[0] = '\0';
    }
  }
  (void)snprintf(sess->history + strlen(sess->history), sizeof(sess->history) - strlen(sess->history),
                 "\nAssistant: %s\n", answer);
  chat_session_save_history(sess);

  size_t esc_cap = GGUF_READ_MAX * 2 + 16;
  char *esc_text = malloc(esc_cap);
  if (!esc_text) {
    write_response(cfd, 500, "Internal Server Error", "{\"ok\":false,\"error\":\"oom\"}");
    return;
  }
  json_escape_text(answer, esc_text, esc_cap);
  size_t resp_cap = strlen(esc_text) + 512;
  char *resp = malloc(resp_cap);
  if (!resp) {
    free(esc_text);
    write_response(cfd, 500, "Internal Server Error", "{\"ok\":false,\"error\":\"oom\"}");
    return;
  }
  (void)snprintf(resp, resp_cap,
                 "{\"ok\":true,\"session_id\":\"%s\",\"backend\":\"%s\",\"text\":\"%s\",\"persisted\":true}", sid,
                 backend, esc_text);
  free(esc_text);
  write_response(cfd, 200, "OK", resp);
  free(resp);
}

static void write_response(int fd, int status, const char *status_text, const char *body) {
  char header[4096];
  int body_len = (int)strlen(body);
  int n = snprintf(
      header, sizeof(header),
      "HTTP/1.1 %d %s\r\n"
      "Content-Type: application/json\r\n"
      "Content-Length: %d\r\n"
      "Connection: close\r\n"
      "\r\n",
      status, status_text, body_len);
  if (n > 0) {
    (void)write_all(fd, header, (size_t)n);
    (void)write_all(fd, body, (size_t)body_len);
  }
}

#define PROXY_LLSRV_RESP_MAX (512 * 1024)

/* POST body -> llama.cpp llama-server /completion (model stays loaded in server). */
static void handle_llama_server_completion_proxy(int cfd, const char *req, ssize_t n) {
  const char *base = getenv("AZL_LLAMA_SERVER_URL");
  if (!base || base[0] == '\0') {
    write_response(
        cfd, 503, "Service Unavailable",
        "{\"ok\":false,\"error\":\"AZL_LLAMA_SERVER_URL_unset\","
        "\"hint\":\"Run llama-server with your .gguf, then export AZL_LLAMA_SERVER_URL=http://127.0.0.1:PORT\"}");
    return;
  }
  char url[2048];
  size_t bl = strlen(base);
  while (bl > 0 && (base[bl - 1] == '/' || base[bl - 1] == ' ')) bl--;
  int un = snprintf(url, sizeof(url), "%.*s/completion", (int)bl, base);
  if (un <= 0 || (size_t)un >= sizeof(url)) {
    write_response(cfd, 500, "Internal Server Error",
                  "{\"ok\":false,\"error\":\"llama_server_url_too_long\"}");
    return;
  }

  const char *body_start = strstr(req, "\r\n\r\n");
  if (body_start) body_start += 4;
  else {
    body_start = strstr(req, "\n\n");
    if (body_start) body_start += 2;
    else body_start = req;
  }
  size_t body_len = (size_t)(req + n - body_start);
  if (body_len > 12000) body_len = 12000;

  char tmp_path[80];
  snprintf(tmp_path, sizeof(tmp_path), "/tmp/azl_llsrv_%d.json", (int)getpid());
  FILE *tf = fopen(tmp_path, "w");
  if (!tf) {
    write_response(cfd, 500, "Internal Server Error", "{\"ok\":false,\"error\":\"tmpfile_failed\"}");
    return;
  }
  fwrite(body_start, 1, body_len, tf);
  fclose(tf);

  char cmd[4096];
  (void)snprintf(cmd, sizeof(cmd),
                 "curl -sS -g -m 300 -X POST -H 'Content-Type: application/json' -d @%s '%s' 2>/dev/null",
                 tmp_path, url);
  FILE *pipe = popen(cmd, "r");
  if (!pipe) {
    unlink(tmp_path);
    write_response(cfd, 502, "Bad Gateway", "{\"ok\":false,\"error\":\"llama_server_curl_failed\"}");
    return;
  }
  char *resp = malloc(PROXY_LLSRV_RESP_MAX + 1);
  if (!resp) {
    pclose(pipe);
    unlink(tmp_path);
    write_response(cfd, 500, "Internal Server Error", "{\"ok\":false,\"error\":\"oom\"}");
    return;
  }
  size_t total = 0;
  for (;;) {
    ssize_t rn = fread(resp + total, 1, PROXY_LLSRV_RESP_MAX - total, pipe);
    if (rn <= 0) break;
    total += (size_t)rn;
    if (total >= PROXY_LLSRV_RESP_MAX) break;
  }
  (void)pclose(pipe);
  unlink(tmp_path);
  resp[total] = '\0';

  if (total == 0) {
    free(resp);
    write_response(cfd, 502, "Bad Gateway",
                  "{\"ok\":false,\"error\":\"llama_server_empty_response\","
                  "\"hint\":\"Is llama-server running? Try GET $AZL_LLAMA_SERVER_URL/health\"}");
    return;
  }
  write_response(cfd, 200, "OK", resp);
  free(resp);
}

static bool is_public_path(const char *path) {
  return strcmp(path, "/healthz") == 0 || strcmp(path, "/health") == 0 || strcmp(path, "/readyz") == 0 ||
         strcmp(path, "/status") == 0 || strcmp(path, "/segment") == 0 ||
         strcmp(path, "/api/llm/capabilities") == 0;
}

static bool needs_runtime_poll(const char *path) {
  return strcmp(path, "/readyz") == 0 || strcmp(path, "/status") == 0 ||
         strcmp(path, "/api/exec_state") == 0 || strcmp(path, "/api/state") == 0 ||
         strcmp(path, "/api/connectivity") == 0;
}

static bool has_valid_bearer(const char *req, const char *token) {
  if (!token || token[0] == '\0') return false;
  const char *p = strstr(req, "\nAuthorization:");
  if (!p) p = strstr(req, "\r\nAuthorization:");
  if (!p) return false;
  const char *b = strstr(p, "Bearer ");
  if (!b) return false;
  b += 7;
  while (*b == ' ') b++;
  char got[256];
  size_t i = 0;
  while (*b && *b != '\r' && *b != '\n' && i + 1 < sizeof(got)) got[i++] = *b++;
  got[i] = '\0';
  return strcmp(got, token) == 0;
}

static void handle_conn(int cfd, EngineState *st) {
  char req[ENGINE_HTTP_REQ_MAX + 1u];
  ssize_t n = read_http_request_full(cfd, req, ENGINE_HTTP_REQ_MAX);
  if (n <= 0) return;
  if ((size_t)n >= sizeof(req)) return;
  req[n] = '\0';
  st->requests_total++;

  char method[16] = {0};
  char path[2048] = {0};
  if (sscanf(req, "%15s %2047s", method, path) != 2) {
    write_response(cfd, 400, "Bad Request", "{\"ok\":false,\"error\":\"bad_request\"}");
    return;
  }
  char *q = strchr(path, '?');
  if (q) *q = '\0';

  if (needs_runtime_poll(path)) {
    update_runtime_state(st);
  }

  bool authorized = is_public_path(path) || has_valid_bearer(req, st->token);
  if (!authorized) {
    write_response(cfd, 401, "Unauthorized", "{\"ok\":false,\"error\":\"unauthorized\"}");
    return;
  }

  char body[4096];
  if (strcmp(path, "/healthz") == 0 || strcmp(path, "/health") == 0) {
    snprintf(body, sizeof(body), "{\"ok\":true,\"service\":\"azl-native-engine\",\"entry\":\"%s\"}", st->entry);
    write_response(cfd, 200, "OK", body);
    return;
  }
  if (strcmp(path, "/readyz") == 0) {
    if (st->runtime_running) {
      snprintf(body, sizeof(body), "{\"status\":\"ready\",\"engine\":\"native\",\"runtime\":\"running\"}");
      write_response(cfd, 200, "OK", body);
    } else {
      snprintf(body, sizeof(body),
               "{\"status\":\"not_ready\",\"engine\":\"native\",\"runtime\":\"stopped\","
               "\"runtime_exit_code\":%d}",
               st->runtime_exit_code);
      write_response(cfd, 503, "Service Unavailable", body);
    }
    return;
  }
  if (strcmp(path, "/status") == 0) {
    long uptime = (long)(time(NULL) - st->started_at);
    snprintf(body, sizeof(body),
             "{\"status\":\"ok\",\"engine\":\"native\",\"uptime_sec\":%ld,\"requests_total\":%lu,"
             "\"combined\":\"%s\",\"native_core\":%s,"
             "\"runtime\":{\"running\":%s,\"pid\":%d,\"exit_code\":%d}}",
             uptime, st->requests_total, st->combined_path, st->use_native_core ? "true" : "false",
             st->runtime_running ? "true" : "false", (int)st->runtime_pid, st->runtime_exit_code);
    write_response(cfd, 200, "OK", body);
    return;
  }
  if (strcmp(path, "/api/exec_state") == 0) {
    snprintf(body, sizeof(body),
             "{\"ok\":true,\"running\":%s,\"pid\":%d,\"exit_code\":%d,\"combined\":\"%s\"}",
             st->runtime_running ? "true" : "false", (int)st->runtime_pid, st->runtime_exit_code, st->combined_path);
    write_response(cfd, 200, "OK", body);
    return;
  }
  if (strcmp(path, "/api/connectivity") == 0) {
    snprintf(body, sizeof(body),
             "{\"ok\":true,\"engine\":\"native\",\"runtime_running\":%s,\"api_reachable\":true}",
             st->runtime_running ? "true" : "false");
    write_response(cfd, 200, "OK", body);
    return;
  }
  if (strcmp(path, "/api/state") == 0) {
    snprintf(body, sizeof(body),
             "{\"ok\":true,\"mode\":\"native\",\"entry\":\"%s\","
             "\"runtime\":{\"running\":%s,\"pid\":%d,\"exit_code\":%d},"
             "\"error\":\"%s\"}",
             st->entry, st->runtime_running ? "true" : "false", (int)st->runtime_pid,
             st->runtime_exit_code, st->runtime_error);
    write_response(cfd, 200, "OK", body);
    return;
  }
  if (strcmp(path, "/segment") == 0) {
    snprintf(body, sizeof(body), "{\"status\":\"segment_ready\",\"engine\":\"native\"}");
    write_response(cfd, 200, "OK", body);
    return;
  }
  /* GET /api/llm/capabilities — honest native LLM surface (orchestration / audits) */
  if (strcmp(path, "/api/llm/capabilities") == 0 && strcmp(method, "GET") == 0) {
    const char *gp = getenv("AZL_GGUF_PATH");
    int gp_ok = 0;
    struct stat gst;
    if (gp && gp[0] != '\0' && stat(gp, &gst) == 0 && S_ISREG(gst.st_mode)) gp_ok = 1;
    const char *lsu = getenv("AZL_LLAMA_SERVER_URL");
    int ls_ok = (lsu && lsu[0] != '\0');
    int llm_ngl = azl_llm_n_gpu_layers_from_env();
    int llm_ngl_set = azl_llm_ngl_env_is_set();
    char cap[8192];
#ifdef AZL_WITH_LLAMACPP
    int cn = snprintf(
        cap, sizeof(cap),
        "{\"ok\":true,\"engine\":\"azl-native-engine\","
        "\"ollama_http_proxy\":true,\"ollama_proxy_path\":\"/api/ollama/generate\","
        "\"ollama_upstream_env\":\"OLLAMA_HOST\","
        "\"gguf_in_process\":true,\"gguf_embedded_llamacpp\":true,"
        "\"gguf_cli_infer\":%s,\"gguf_infer_path\":\"/api/llm/gguf_infer\","
        "\"policy_guard_enabled\":true,\"policy_infer_path\":\"/api/llm/policy_infer\","
        "\"chat_session_path\":\"/api/llm/chat_session\","
        "\"gguf_model_configured\":%s,"
        "\"llama_server_http_proxy\":%s,\"llama_server_completion_path\":\"/api/llm/llama_server/completion\","
        "\"llama_server_upstream_configured\":%s,"
        "\"llm_n_gpu_layers\":%d,\"llm_n_gpu_layers_env_set\":%s,"
        "\"llm_n_gpu_layers_env_keys\":\"AZL_LLAMA_NGL|AZL_LLM_GPU_LAYERS\","
        "\"llm_gpu_stack\":\"llama.cpp\","
        "\"error\":null}",
        gp_ok ? "true" : "false", gp_ok ? "true" : "false", ls_ok ? "true" : "false",
        ls_ok ? "true" : "false", llm_ngl, llm_ngl_set ? "true" : "false");
#else
    int cn = snprintf(
        cap, sizeof(cap),
        "{\"ok\":true,\"engine\":\"azl-native-engine\","
        "\"ollama_http_proxy\":true,\"ollama_proxy_path\":\"/api/ollama/generate\","
        "\"ollama_upstream_env\":\"OLLAMA_HOST\","
        "\"gguf_in_process\":false,"
        "\"gguf_cli_infer\":%s,\"gguf_infer_path\":\"/api/llm/gguf_infer\","
        "\"policy_guard_enabled\":true,\"policy_infer_path\":\"/api/llm/policy_infer\","
        "\"chat_session_path\":\"/api/llm/chat_session\","
        "\"gguf_model_configured\":%s,"
        "\"llama_server_http_proxy\":%s,\"llama_server_completion_path\":\"/api/llm/llama_server/completion\","
        "\"llama_server_upstream_configured\":%s,"
        "\"llm_n_gpu_layers\":%d,\"llm_n_gpu_layers_env_set\":%s,"
        "\"llm_n_gpu_layers_env_keys\":\"AZL_LLAMA_NGL|AZL_LLM_GPU_LAYERS\","
        "\"llm_gpu_stack\":\"llama.cpp\","
        "\"error\":{\"code\":\"ERR_NATIVE_GGUF_NOT_IN_PROCESS\","
        "\"message\":\"Weights are not linked inside this binary; use POST /api/llm/gguf_infer "
        "(set AZL_GGUF_PATH to a .gguf file and install llama.cpp llama-cli) or "
        "build with scripts/build_azl_native_engine_with_llamacpp.sh (in-process llama.cpp), or "
        "POST /api/llm/llama_server/completion (llama-server + AZL_LLAMA_SERVER_URL) or "
        "POST /api/ollama/generate (Ollama).\"}}",
        gp_ok ? "true" : "false", gp_ok ? "true" : "false", ls_ok ? "true" : "false",
        ls_ok ? "true" : "false", llm_ngl, llm_ngl_set ? "true" : "false");
#endif
    if (cn > 0 && (size_t)cn < sizeof(cap))
      write_response(cfd, 200, "OK", cap);
    else
      write_response(cfd, 500, "Internal Server Error", "{\"ok\":false,\"error\":\"capabilities_overflow\"}");
    return;
  }

  /* POST /api/llm/gguf_infer: run local llama-cli on AZL_GGUF_PATH (no Ollama) */
  if (strcmp(path, "/api/llm/gguf_infer") == 0 && strcmp(method, "POST") == 0) {
    handle_gguf_infer(cfd, req, n, st);
    return;
  }

  /* POST /api/llm/policy_infer: policy-gated GGUF inference with audit trail */
  if (strcmp(path, "/api/llm/policy_infer") == 0 && strcmp(method, "POST") == 0) {
    handle_policy_infer(cfd, req, n, st);
    return;
  }
  if (strcmp(path, "/api/llm/chat_session") == 0 && strcmp(method, "POST") == 0) {
    handle_chat_session(cfd, req, n, st);
    return;
  }

  /* POST /api/llm/llama_server/completion -> llama-server /completion (model loaded once upstream) */
  if (strcmp(path, "/api/llm/llama_server/completion") == 0 && strcmp(method, "POST") == 0) {
    handle_llama_server_completion_proxy(cfd, req, n);
    return;
  }

  /* POST /api/ollama/generate: proxy to Ollama for LLM benchmark */
  if (strcmp(path, "/api/ollama/generate") == 0 && strcmp(method, "POST") == 0) {
    const char *ollama_host = getenv("OLLAMA_HOST");
    if (!ollama_host || ollama_host[0] == '\0') ollama_host = "http://127.0.0.1:11434";
    const char *body_start = strstr(req, "\r\n\r\n");
    if (body_start) body_start += 4;
    else {
      body_start = strstr(req, "\n\n");
      if (body_start) body_start += 2;
      else body_start = req;
    }
    size_t body_len = (size_t)(req + n - body_start);
    if (body_len > 8192) body_len = 8192;
    char tmp_path[64];
    snprintf(tmp_path, sizeof(tmp_path), "/tmp/azl_ollama_%d.json", (int)getpid());
    FILE *tf = fopen(tmp_path, "w");
    if (tf) {
      fwrite(body_start, 1, body_len, tf);
      fclose(tf);
      char cmd[1024];
      snprintf(cmd, sizeof(cmd),
               "curl -sS -m 120 -X POST -H 'Content-Type: application/json' -d @%s '%s/api/generate' 2>/dev/null",
               tmp_path, ollama_host);
      FILE *curl_pipe = popen(cmd, "r");
      if (curl_pipe) {
        char resp[65536];
        size_t rn = fread(resp, 1, sizeof(resp) - 1, curl_pipe);
        resp[rn] = '\0';
        pclose(curl_pipe);
        if (rn > 0) {
          write_response(cfd, 200, "OK", resp);
        } else {
          write_response(cfd, 502, "Bad Gateway",
                        "{\"ok\":false,\"error\":\"ollama_no_response\"}");
        }
      } else {
        write_response(cfd, 502, "Bad Gateway",
                      "{\"ok\":false,\"error\":\"ollama_curl_failed\"}");
      }
      unlink(tmp_path);
    } else {
      write_response(cfd, 500, "Internal Server Error",
                    "{\"ok\":false,\"error\":\"ollama_tmpfile_failed\"}");
    }
    return;
  }

  snprintf(body, sizeof(body), "{\"ok\":false,\"error\":\"not_found\",\"path\":\"%s\"}", path);
  write_response(cfd, 404, "Not Found", body);
}

static int run_server(EngineState *st) {
  int sfd = socket(AF_INET, SOCK_STREAM, 0);
  if (sfd < 0) {
    fprintf(stderr, "native-engine: socket failed: %s\n", strerror(errno));
    return 10;
  }
  int on = 1;
  setsockopt(sfd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on));

  struct sockaddr_in sa;
  memset(&sa, 0, sizeof(sa));
  sa.sin_family = AF_INET;
  sa.sin_port = htons((unsigned short)st->port);
  if (inet_pton(AF_INET, st->host, &sa.sin_addr) != 1) {
    fprintf(stderr, "native-engine: invalid host: %s\n", st->host);
    close(sfd);
    return 11;
  }
  if (bind(sfd, (struct sockaddr *)&sa, sizeof(sa)) < 0) {
    fprintf(stderr, "native-engine: bind %s:%d failed: %s\n", st->host, st->port, strerror(errno));
    close(sfd);
    return 12;
  }
  if (listen(sfd, 128) < 0) {
    fprintf(stderr, "native-engine: listen failed: %s\n", strerror(errno));
    close(sfd);
    return 13;
  }

  printf("native-engine: listening on http://%s:%d entry=%s%s%s\n", st->host, st->port, st->entry,
         st->use_native_core ? " native_core=1" : "", st->native_core_demo ? " native_core_demo=1" : "");
  fflush(stdout);

  struct sockaddr_in ca;
  socklen_t calen = sizeof(ca);

  if (st->use_native_core) {
    int fl = fcntl(sfd, F_GETFL, 0);
    if (fl >= 0)
      (void)fcntl(sfd, F_SETFL, fl | O_NONBLOCK);
  }

  while (g_running) {
    if (st->use_native_core) {
      struct pollfd pfd;
      pfd.fd = sfd;
      pfd.events = POLLIN;
      int pr = poll(&pfd, 1, 50);
      if (pr < 0) {
        if (errno == EINTR)
          continue;
        usleep(20000);
        continue;
      }
      if (pr > 0 && (pfd.revents & (POLLERR | POLLHUP | POLLNVAL)))
        break;
      if (pr > 0 && (pfd.revents & POLLIN)) {
        for (;;) {
          int cfd = accept(sfd, (struct sockaddr *)&ca, &calen);
          if (cfd < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)
              break;
            usleep(1000);
            break;
          }
          handle_conn(cfd, st);
          close(cfd);
        }
      }
      azl_native_core_host_poll(&st->native_core);
    } else {
      calen = sizeof(ca);
      int cfd = accept(sfd, (struct sockaddr *)&ca, &calen);
      if (cfd < 0) {
        if (errno == EINTR)
          continue;
        usleep(20000);
        continue;
      }
      handle_conn(cfd, st);
      close(cfd);
    }
  }

  close(sfd);
  return 0;
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr,
            "usage: %s [--use-native-core] [--native-core-demo] <bootstrap.bundle.azl> [::<entry.point>]\n",
            argv[0]);
    fprintf(stderr,
            "  --use-native-core   Embed azl_core_engine; skip AZL_NATIVE_RUNTIME_CMD child (benchmark).\n");
    fprintf(stderr,
            "  --native-core-demo  After start, emit async Ollama /api/generate (needs curl; OLLAMA_HOST).\n");
    fprintf(stderr,
            "  --compile-azl PATH  With --use-native-core: compile .azl subset to bytecode and vm_exec.\n");
    return 2;
  }
  EngineState st;
  memset(&st, 0, sizeof(st));
  const char *bundle_arg = NULL;
  const char *entry_arg = NULL;
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--use-native-core") == 0) {
      st.use_native_core = 1;
      continue;
    }
    if (strcmp(argv[i], "--native-core-demo") == 0) {
      st.native_core_demo = 1;
      continue;
    }
    if (strcmp(argv[i], "--compile-azl") == 0) {
      if (i + 1 >= argc) {
        fprintf(stderr, "native-engine: --compile-azl requires a path\n");
        return 2;
      }
      snprintf(st.compile_azl_path, sizeof(st.compile_azl_path), "%s", argv[++i]);
      continue;
    }
    if (!bundle_arg)
      bundle_arg = argv[i];
    else if (!entry_arg)
      entry_arg = argv[i];
    else {
      fprintf(stderr, "native-engine: unexpected argument: %s\n", argv[i]);
      return 2;
    }
  }
  if (!bundle_arg) {
    fprintf(stderr, "native-engine: missing bootstrap bundle path\n");
    return 2;
  }
  if (st.native_core_demo && !st.use_native_core) {
    fprintf(stderr, "native-engine: --native-core-demo requires --use-native-core\n");
    return 2;
  }
  if (st.compile_azl_path[0] != '\0' && !st.use_native_core) {
    fprintf(stderr, "native-engine: --compile-azl requires --use-native-core\n");
    return 2;
  }
  snprintf(st.bundle_path, sizeof(st.bundle_path), "%s", bundle_arg);
  st.started_at = time(NULL);
  st.port = atoi(getenv_or("AZL_BUILD_API_PORT", "8080"));
  if (st.port <= 0 || st.port > 65535) st.port = 8080;
  snprintf(st.host, sizeof(st.host), "%s", getenv_or("AZL_BIND_HOST", "127.0.0.1"));
  snprintf(st.token, sizeof(st.token), "%s", getenv_or("AZL_API_TOKEN", ""));
  st.runtime_pid = -1;
  st.runtime_exit_code = 0;
  st.runtime_running = 0;
  st.last_runtime_poll_ms = 0;
  st.runtime_error[0] = '\0';
  st.runtime_command[0] = '\0';

  int rc = read_bootstrap_metadata(st.bundle_path, st.combined_path, sizeof(st.combined_path), st.entry, sizeof(st.entry));
  if (rc != 0) return rc;
  if (entry_arg && entry_arg[0] != '\0') {
    snprintf(st.entry, sizeof(st.entry), "%s", entry_arg);
  }
  struct stat cst;
  if (stat(st.combined_path, &cst) != 0) {
    fprintf(stderr, "native-engine: combined file missing: %s\n", st.combined_path);
    return 6;
  }

  signal(SIGINT, on_signal);
  signal(SIGTERM, on_signal);

  /* Native core: event + HTTP bridge + bytecode VM live in-process; no AZL_NATIVE_RUNTIME_CMD
   * child (no Python minimal_runtime / C minimal interpreter subprocess for event logic). */
  if (st.use_native_core) {
    char cwdbuf[512];
    if (getenv("AZL_REPO_ROOT") == NULL && getcwd(cwdbuf, sizeof(cwdbuf)) != NULL)
      setenv("AZL_REPO_ROOT", cwdbuf, 0);
    memset(&st.native_core, 0, sizeof(st.native_core));
    if (azl_native_core_host_init(&st.native_core) != 0) {
      fprintf(stderr, "native-engine: azl_native_core_host_init failed\n");
      return 16;
    }
    if (azl_native_core_register_stdlib_net_http(&st.native_core) != 0) {
      fprintf(stderr, "native-engine: azl_native_core_register_stdlib_net_http failed\n");
      azl_native_core_host_shutdown(&st.native_core);
      return 17;
    }
    if (st.compile_azl_path[0] != '\0') {
      azl_engine_register_listener(st.native_core.eng, "hello", native_compile_hello_sink, NULL);
      AzlBytecodeProgram bcprog;
      azl_bytecode_program_init_empty(&bcprog);
      char cerr[512];
      if (azl_compile_file(st.compile_azl_path, &bcprog, cerr, sizeof(cerr)) != 0) {
        fprintf(stderr, "native-engine: --compile-azl %s: %s\n", st.compile_azl_path, cerr);
        azl_native_core_host_shutdown(&st.native_core);
        return 18;
      }
      if (azl_vm_exec_block(st.native_core.eng, &bcprog) != AZL_OK) {
        fprintf(stderr, "native-engine: vm_exec after --compile-azl failed\n");
        azl_bytecode_program_destroy(&bcprog);
        azl_native_core_host_shutdown(&st.native_core);
        return 19;
      }
      azl_bytecode_program_destroy(&bcprog);
    }
    if (st.native_core_demo)
      azl_native_core_emit_demo_ollama(&st.native_core);
    st.runtime_running = 1;
    st.runtime_pid = -1;
    snprintf(st.runtime_command, sizeof(st.runtime_command), "embedded:azl_core_engine");
    st.runtime_error[0] = '\0';
  } else {
    int start_rc = start_runtime_pipeline(&st);
    if (start_rc != 0) {
      fprintf(stderr, "native-engine: failed to launch runtime pipeline: %s\n", st.runtime_error);
      return start_rc;
    }
  }
  append_run_record(&st);
  int rc_srv = run_server(&st);
  if (st.use_native_core) {
    azl_native_core_host_shutdown(&st.native_core);
  } else if (st.runtime_pid > 0) {
    kill(st.runtime_pid, SIGTERM);
    (void)waitpid(st.runtime_pid, NULL, 0);
  }
  return rc_srv;
}
