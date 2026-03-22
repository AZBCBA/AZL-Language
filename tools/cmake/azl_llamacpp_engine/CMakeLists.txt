# Optional build: links azl-native-engine against a local llama.cpp tree (no vendored submodule).
# Usage: see scripts/build_azl_native_engine_with_llamacpp.sh
cmake_minimum_required(VERSION 3.14)
project(azl_native_llamacpp_engine C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT AZL_REPO_ROOT)
  get_filename_component(AZL_REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
endif()

if(NOT LLAMA_CPP_ROOT)
  if(DEFINED ENV{LLAMA_CPP_ROOT})
    set(LLAMA_CPP_ROOT "$ENV{LLAMA_CPP_ROOT}")
  endif()
endif()

if(NOT LLAMA_CPP_ROOT OR NOT EXISTS "${LLAMA_CPP_ROOT}/CMakeLists.txt")
  message(FATAL_ERROR "Set LLAMA_CPP_ROOT to the root of a llama.cpp checkout (contains CMakeLists.txt).")
endif()

set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

add_subdirectory("${LLAMA_CPP_ROOT}" "${CMAKE_BINARY_DIR}/_llama_cpp_build")

find_package(Threads REQUIRED)

add_executable(azl-native-engine
  "${AZL_REPO_ROOT}/tools/azl_native_engine.c"
  "${AZL_REPO_ROOT}/tools/azl_core_engine.c"
  "${AZL_REPO_ROOT}/tools/azl_native_engine_core_host.c"
  "${AZL_REPO_ROOT}/tools/azl_gguf_infer_llamacpp.cpp"
)

target_compile_definitions(azl-native-engine PRIVATE AZL_WITH_LLAMACPP=1)
target_include_directories(azl-native-engine PRIVATE "${AZL_REPO_ROOT}/tools")
target_link_libraries(azl-native-engine PRIVATE llama Threads::Threads)

set_target_properties(azl-native-engine PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${AZL_REPO_ROOT}/.azl/bin"
)
