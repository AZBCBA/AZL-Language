/* Minimal bytecode VM for native core (Phase: self-hosting / Python independence).
 * Bundle format: JSON with const string pool + flat opcode array (see tools/testdata/vm_hello_world.json).
 */
#ifndef AZL_BYTECODE_H
#define AZL_BYTECODE_H

#include "azl_core_engine.h"
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define AZL_BC_CONST_MAX 128u
#define AZL_BC_CODE_MAX 512u
#define AZL_BC_STR_MAX 256u

typedef struct AzlBytecodeInstr {
  uint8_t op;
  uint32_t a;
  uint32_t b;
  uint32_t c;
} AzlBytecodeInstr;

typedef struct AzlBytecodeProgram {
  char (*consts)[AZL_BC_STR_MAX];
  size_t nconst;
  AzlBytecodeInstr *code;
  size_t ncode;
} AzlBytecodeProgram;

void azl_bytecode_program_init_empty(AzlBytecodeProgram *p);
void azl_bytecode_program_destroy(AzlBytecodeProgram *p);

/* Parse JSON bundle into heap-owned program. Returns 0 on success. */
int azl_bytecode_load_json(const char *json, size_t json_len, AzlBytecodeProgram *out, char *errbuf,
                           size_t errbuf_sz);

/* Execute program: OP_EMIT -> azl_engine_emit; OP_HALT stops; OP_NOP no-op. */
AzlErr azl_vm_exec_block(AzlEngine *eng, const AzlBytecodeProgram *prog);

/* Run JSON hello-world bundle test; returns 0 on success. */
int azl_bytecode_selftest(void);

#ifdef __cplusplus
}
#endif
#endif
