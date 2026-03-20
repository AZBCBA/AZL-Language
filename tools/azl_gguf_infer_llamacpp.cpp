#include "azl_gguf_infer_llamacpp.h"

#include "llama.h"

#include <algorithm>
#include <clocale>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace {

struct ModelCache {
  std::string path;
  llama_model *model = nullptr;
};

ModelCache g_model;
bool g_backends_loaded = false;

static void set_err(char *err, size_t err_cap, const char *msg) {
  if (!err || err_cap == 0) return;
  (void)snprintf(err, err_cap, "%s", msg ? msg : "unknown");
}

static void unload_model_locked() {
  if (g_model.model) {
    llama_model_free(g_model.model);
    g_model.model = nullptr;
  }
  g_model.path.clear();
}

static int append_piece(const llama_vocab *vocab, llama_token id, std::string *acc, char *err, size_t err_cap) {
  char buf[256];
  int n = llama_token_to_piece(vocab, id, buf, sizeof(buf), 0, true);
  if (n < 0) {
    set_err(err, err_cap, "token_to_piece_failed");
    return -1;
  }
  acc->append(buf, (size_t)n);
  return 0;
}

} /* namespace */

void azl_llamacpp_shutdown(void) { unload_model_locked(); }

int azl_llamacpp_gguf_infer(const char *model_path, const char *prompt, int n_predict, char *out, size_t out_cap,
                            char *err, size_t err_cap) {
  if (!model_path || model_path[0] == '\0' || !prompt || !out || out_cap == 0) {
    set_err(err, err_cap, "bad_args");
    return -1;
  }
  if (n_predict < 0) n_predict = 0;
  if (n_predict > 8192) n_predict = 8192;

  std::setlocale(LC_NUMERIC, "C");

  if (!g_backends_loaded) {
    ggml_backend_load_all();
    g_backends_loaded = true;
  }

  if (g_model.path != model_path) {
    unload_model_locked();
    llama_model_params model_params = llama_model_default_params();
    const char *ngl = std::getenv("AZL_LLAMA_NGL");
    if (ngl && ngl[0] != '\0') {
      model_params.n_gpu_layers = std::atoi(ngl);
    } else {
      model_params.n_gpu_layers = 0;
    }
    g_model.model = llama_model_load_from_file(model_path, model_params);
    if (!g_model.model) {
      set_err(err, err_cap, "model_load_failed");
      return -2;
    }
    g_model.path = model_path;
  }

  llama_model *model = g_model.model;
  const llama_vocab *vocab = llama_model_get_vocab(model);

  const int n_prompt = -llama_tokenize(vocab, prompt, std::strlen(prompt), NULL, 0, true, true);
  if (n_prompt <= 0) {
    set_err(err, err_cap, "tokenize_size_failed");
    return -3;
  }

  std::vector<llama_token> prompt_tokens((size_t)n_prompt);
  if (llama_tokenize(vocab, prompt, std::strlen(prompt), prompt_tokens.data(), n_prompt, true, true) < 0) {
    set_err(err, err_cap, "tokenize_failed");
    return -4;
  }

  llama_context_params ctx_params = llama_context_default_params();
  const int n_ctx_need = n_prompt + n_predict + 64;
  ctx_params.n_ctx = (uint32_t)n_ctx_need;
  ctx_params.n_batch = (uint32_t)std::max(n_prompt, 512);
  ctx_params.no_perf = true;

  llama_context *ctx = llama_init_from_model(model, ctx_params);
  if (!ctx) {
    set_err(err, err_cap, "context_create_failed");
    return -5;
  }

  auto sparams = llama_sampler_chain_default_params();
  sparams.no_perf = true;
  llama_sampler *smpl = llama_sampler_chain_init(sparams);
  llama_sampler_chain_add(smpl, llama_sampler_init_greedy());

  std::string acc;
  acc.reserve((size_t)n_predict * 4u + 256u);

  for (llama_token id : prompt_tokens) {
    if (append_piece(vocab, id, &acc, err, err_cap) != 0) {
      llama_sampler_free(smpl);
      llama_free(ctx);
      return -6;
    }
  }

  llama_batch batch = llama_batch_get_one(prompt_tokens.data(), (int32_t)prompt_tokens.size());

  if (llama_model_has_encoder(model)) {
    if (llama_encode(ctx, batch) != 0) {
      llama_sampler_free(smpl);
      llama_free(ctx);
      set_err(err, err_cap, "encode_failed");
      return -7;
    }
    llama_token decoder_start_token_id = llama_model_decoder_start_token(model);
    if (decoder_start_token_id == LLAMA_TOKEN_NULL) {
      decoder_start_token_id = llama_vocab_bos(vocab);
    }
    batch = llama_batch_get_one(&decoder_start_token_id, 1);
  }

  for (int n_pos = 0; n_pos + batch.n_tokens < n_prompt + n_predict;) {
    if (llama_decode(ctx, batch) != 0) {
      llama_sampler_free(smpl);
      llama_free(ctx);
      set_err(err, err_cap, "decode_failed");
      return -8;
    }
    n_pos += batch.n_tokens;

    llama_token new_token_id = llama_sampler_sample(smpl, ctx, -1);
    if (llama_vocab_is_eog(vocab, new_token_id)) {
      break;
    }
    if (append_piece(vocab, new_token_id, &acc, err, err_cap) != 0) {
      llama_sampler_free(smpl);
      llama_free(ctx);
      return -9;
    }
    if (acc.size() + 256u >= out_cap) {
      llama_sampler_free(smpl);
      llama_free(ctx);
      set_err(err, err_cap, "output_too_large");
      return -10;
    }
    batch = llama_batch_get_one(&new_token_id, 1);
  }

  llama_sampler_free(smpl);
  llama_free(ctx);

  if (acc.size() + 1u > out_cap) {
    set_err(err, err_cap, "output_too_large");
    return -10;
  }
  std::memcpy(out, acc.c_str(), acc.size() + 1);
  return 0;
}
