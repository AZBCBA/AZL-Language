/* Minimal AZL → AzlBytecodeProgram (native compiler front-end, no JSON). */
#ifndef AZL_COMPILER_H
#define AZL_COMPILER_H

#include "azl_bytecode.h"
#include <stddef.h>

/* Compile source into heap-owned program (caller must azl_bytecode_program_destroy). */
int azl_compile_source(const char *src, size_t src_len, AzlBytecodeProgram *out, char *errbuf, size_t errbuf_sz);

int azl_compile_file(const char *path, AzlBytecodeProgram *out, char *errbuf, size_t errbuf_sz);

/* Compile path and discard program; 0 if input is in the native compile/vm subset. */
int azl_compile_file_check(const char *path, char *errbuf, size_t errbuf_sz);

/* Compile inline Hello-World .azl and run VM; returns 0 on success. */
int azl_compiler_selftest(void);

#endif
