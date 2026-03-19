#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
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
} EngineState;

static void on_signal(int sig) {
  (void)sig;
  g_running = 0;
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

static void ensure_azl_dir(void) {
  struct stat st;
  if (stat(".azl", &st) == 0 && S_ISDIR(st.st_mode)) return;
  mkdir(".azl", 0755);
}

static void append_run_record(const EngineState *st) {
  ensure_azl_dir();
  FILE *fp = fopen(".azl/native_engine_runs.jsonl", "a");
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
  char req[16384];
  ssize_t n = read(cfd, req, sizeof(req) - 1);
  if (n <= 0) return;
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
             "\"combined\":\"%s\","
             "\"runtime\":{\"running\":%s,\"pid\":%d,\"exit_code\":%d}}",
             uptime, st->requests_total, st->combined_path,
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
    snprintf(body, sizeof(body),
             "{\"ok\":true,\"engine\":\"azl-native-engine\","
             "\"ollama_http_proxy\":true,\"ollama_proxy_path\":\"/api/ollama/generate\","
             "\"ollama_upstream_env\":\"OLLAMA_HOST\","
             "\"gguf_in_process\":false,"
             "\"error\":{\"code\":\"ERR_NATIVE_GGUF_NOT_IMPLEMENTED\","
             "\"message\":\"No in-process GGUF weights; use Ollama proxy or external runtime\"}}");
    write_response(cfd, 200, "OK", body);
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

  printf("native-engine: listening on http://%s:%d entry=%s\n", st->host, st->port, st->entry);
  fflush(stdout);

  while (g_running) {
    struct sockaddr_in ca;
    socklen_t calen = sizeof(ca);
    int cfd = accept(sfd, (struct sockaddr *)&ca, &calen);
    if (cfd < 0) {
      if (errno == EINTR) continue;
      usleep(20000);
      continue;
    }
    handle_conn(cfd, st);
    close(cfd);
  }

  close(sfd);
  return 0;
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: %s <bootstrap.bundle.azl> [::<entry.point>]\n", argv[0]);
    return 2;
  }
  EngineState st;
  memset(&st, 0, sizeof(st));
  snprintf(st.bundle_path, sizeof(st.bundle_path), "%s", argv[1]);
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
  if (argc >= 3 && argv[2][0] != '\0') {
    snprintf(st.entry, sizeof(st.entry), "%s", argv[2]);
  }
  struct stat cst;
  if (stat(st.combined_path, &cst) != 0) {
    fprintf(stderr, "native-engine: combined file missing: %s\n", st.combined_path);
    return 6;
  }

  signal(SIGINT, on_signal);
  signal(SIGTERM, on_signal);
  int start_rc = start_runtime_pipeline(&st);
  if (start_rc != 0) {
    fprintf(stderr, "native-engine: failed to launch runtime pipeline: %s\n", st.runtime_error);
    return start_rc;
  }
  append_run_record(&st);
  int rc_srv = run_server(&st);
  if (st.runtime_pid > 0) {
    kill(st.runtime_pid, SIGTERM);
    (void)waitpid(st.runtime_pid, NULL, 0);
  }
  return rc_srv;
}
