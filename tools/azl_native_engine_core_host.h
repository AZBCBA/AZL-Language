/* Embedded azl_core_engine — used for --use-native-core, --compile-azl, or auto compile/vm .azl input */
#ifndef AZL_NATIVE_ENGINE_CORE_HOST_H
#define AZL_NATIVE_ENGINE_CORE_HOST_H

#include "azl_core_engine.h"
#include <stdbool.h>

typedef struct AzlNativeCoreHost {
  AzlEngine *eng;
  AzlSysproxyBridge *bridge;
} AzlNativeCoreHost;

int azl_native_core_host_init(AzlNativeCoreHost *h);
void azl_native_core_host_shutdown(AzlNativeCoreHost *h);
void azl_native_core_host_poll(AzlNativeCoreHost *h);

/* userdata = AzlNativeCoreHost* (bridge taken from h) */
int azl_native_core_register_stdlib_net_http(AzlNativeCoreHost *h);

/* After register; uses OLLAMA_HOST, AZL_NATIVE_CORE_DEMO_MODEL */
void azl_native_core_emit_demo_ollama(AzlNativeCoreHost *h);

#endif
