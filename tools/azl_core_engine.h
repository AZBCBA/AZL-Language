/* azl_core_engine.h — native event core + arena payloads + async sysproxy HTTP bridge
 *
 * ERROR_SYSTEM alignment (docs/ERROR_SYSTEM.md):
 *   - IO/Network + Timeout: AZL_ERR_NET_TIMEOUT, AZL_ERR_NET_IO
 *   - Runtime: AZL_ERR_DISPATCH_DEPTH (event recursion guard), AZL_ERR_QUEUE_FULL
 *
 * Sysproxy wire format matches tools/sysproxy.c NDJSON over TCP
 * (see docs/LLM_INFRASTRUCTURE_AUDIT.md — http_client op).
 */
#ifndef AZL_CORE_ENGINE_H
#define AZL_CORE_ENGINE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum AzlErr {
  AZL_OK = 0,
  AZL_ERR_DISPATCH_DEPTH = 1,
  AZL_ERR_QUEUE_FULL = 2,
  AZL_ERR_ARENA_OOM = 3,
  AZL_ERR_NET_TIMEOUT = 4,
  AZL_ERR_NET_IO = 5,
  AZL_ERR_PARSE = 6,
  AZL_ERR_THREAD = 7,
  AZL_ERR_INVALID = 8,
} AzlErr;

typedef struct AzlArena AzlArena;
typedef struct AzlEngine AzlEngine;
typedef struct AzlSysproxyBridge AzlSysproxyBridge;

typedef struct AzlPayloadKV {
  const char *key;
  const char *value;
  struct AzlPayloadKV *next;
} AzlPayloadKV;

typedef struct AzlEvent {
  char name[64];
  AzlPayloadKV *payload;
} AzlEvent;

typedef void (*AzlListenerFn)(AzlEngine *engine, const AzlEvent *event, void *userdata);

typedef void (*AzlEngineErrorFn)(AzlEngine *engine, AzlErr code, const char *message,
                                 void *userdata);

/* --- Bytecode VM opcodes (native core; loader/exec in tools/azl_bytecode.c) --- */
typedef enum AzlOpcode {
  AZL_OP_NOP = 0,
  AZL_OP_HALT = 1,
  AZL_OP_LOAD_CONST = 2,
  AZL_OP_EMIT = 3,
  /* Numeric 4–5 are rejected by azl_vm_exec_block and by the JSON loader (not language support). */
  AZL_OP_REJECTED_LEGACY_4 = 4,
  AZL_OP_REJECTED_LEGACY_5 = 5,
  AZL_OP_STORE_VAR = 6,
  AZL_OP_LOAD_VAR = 7,
  AZL_OP_JUMP = 8,
  AZL_OP_JUMP_IF_FALSE = 9,
  AZL_OP_EQ = 10,
} AzlOpcode;

/* --- Arena: bump allocator, reset between bursts (zero freelist fragmentation) --- */
AzlArena *azl_arena_create(size_t capacity_bytes);
void azl_arena_destroy(AzlArena *a);
void azl_arena_reset(AzlArena *a);
void *azl_arena_alloc(AzlArena *a, size_t size, size_t align);
char *azl_arena_strdup(AzlArena *a, const char *s);

/* --- Core engine --- */
AzlEngine *azl_engine_create(size_t arena_capacity, unsigned max_queue_events,
                             unsigned max_dispatch_nesting);
void azl_engine_destroy(AzlEngine *e);

void azl_engine_set_error_callback(AzlEngine *e, AzlEngineErrorFn cb, void *userdata);

AzlErr azl_engine_register_listener(AzlEngine *e, const char *event_name, AzlListenerFn fn,
                                    void *userdata);

/* Copy into arena; enqueue only (safe if called from bridge worker via ring — use poll on main). */
AzlErr azl_engine_emit_enqueue(AzlEngine *e, const char *event_name, const AzlPayloadKV *payload_head);

/* Enqueue then drain (single-threaded hosts / listeners). */
AzlErr azl_engine_emit(AzlEngine *e, const char *event_name, const AzlPayloadKV *payload_head);

/* Drain until empty (nested emit from listeners re-enters; guarded by max_dispatch_nesting). */
void azl_engine_process(AzlEngine *e);

AzlArena *azl_engine_arena(AzlEngine *e);
unsigned azl_engine_dispatch_depth(const AzlEngine *e);
unsigned azl_engine_overflow_events(const AzlEngine *e);

/* When queue is empty and not inside dispatch, reset bump pointer (reuse arena for next burst). */
void azl_engine_reset_arena_if_idle(AzlEngine *e);

/* --- Async HTTP bridge (worker thread; main loop calls poll to inject events) --- */

typedef struct AzlHttpJob {
  char url[2048];
  char method[16];
  char body[65536];
  char request_tag[64];
  int timeout_sec; /* enforced on direct curl path; sysproxy uses its own curl -m unless unset */
  int split_response_lines; /* if non-zero, each line becomes net.http.stream_chunk */
} AzlHttpJob;

/* tcp_host / tcp_port: if tcp_host is NULL, reads AZL_SYSPROXY_TCP (host:port).
 * If neither is set and tcp_port==0, uses curl only (honors job.timeout_sec; maps
 * curl exit 28 to AZL_ERR_NET_TIMEOUT). If tcp_port>0, connects to that TCP port. */
AzlSysproxyBridge *azl_bridge_create(AzlEngine *engine, const char *tcp_host, int tcp_port);
void azl_bridge_destroy(AzlSysproxyBridge *b);

/* Non-blocking from caller's perspective: enqueues work for worker. */
AzlErr azl_bridge_submit_http(AzlSysproxyBridge *b, const AzlHttpJob *job);

/* Main thread: move completed async work into the engine via emit_enqueue (returns notes injected). */
int azl_bridge_poll(AzlSysproxyBridge *b);

#ifdef __cplusplus
}
#endif
#endif /* AZL_CORE_ENGINE_H */
