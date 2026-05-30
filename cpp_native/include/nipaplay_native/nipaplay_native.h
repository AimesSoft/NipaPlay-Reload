#pragma once
#include "export.h"
#include "types.h"

#ifdef __cplusplus
extern "C" {
#endif

// ──── 库级 API ────
NIPAPLAY_NATIVE_EXPORT int32_t np_get_version(void);

// ──── 内存管理 ────
NIPAPLAY_NATIVE_EXPORT void np_string_free(NpString* str);

// ──── 示例模块：ExampleCalculator ────
NIPAPLAY_NATIVE_EXPORT NpHandle np_example_create(void);
NIPAPLAY_NATIVE_EXPORT void     np_example_destroy(NpHandle handle);
NIPAPLAY_NATIVE_EXPORT int32_t  np_example_add(NpHandle handle, int32_t a, int32_t b);
NIPAPLAY_NATIVE_EXPORT NpResult np_example_process_text(
    NpHandle handle, const char* input, NpString* output);

#ifdef __cplusplus
}
#endif
