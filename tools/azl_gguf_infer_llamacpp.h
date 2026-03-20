/* C ABI for optional in-process GGUF inference (implemented in azl_gguf_infer_llamacpp.cpp). */
#ifndef AZL_GGUF_INFER_LLAMACPP_H
#define AZL_GGUF_INFER_LLAMACPP_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Run one greedy completion. Writes UTF-8 text (prompt decoding + generated tokens, same order as
 * llama.cpp examples/simple) into out. On failure returns negative code and a short message in err.
 * Not thread-safe; azl-native-engine serves one connection at a time in the current implementation.
 */
int azl_llamacpp_gguf_infer(const char *model_path, const char *prompt, int n_predict, char *out,
                            size_t out_cap, char *err, size_t err_cap);

void azl_llamacpp_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif
