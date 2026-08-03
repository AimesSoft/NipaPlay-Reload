#ifndef FLUTTER_PLUGIN_FVP_PLUGIN_H_
#define FLUTTER_PLUGIN_FVP_PLUGIN_H_

#include <stdint.h>
#include <stdbool.h>

#if defined(_WIN32)
#define FVP_EXPORT __declspec(dllexport)
#else
#define FVP_EXPORT __attribute__((visibility("default")))
#endif

#if defined(__cplusplus)
extern "C" {
#endif

FVP_EXPORT bool MdkIsEmulator();
FVP_EXPORT void* MdkGetPlayerVid(int64_t tex_id);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_FVP_PLUGIN_H_
