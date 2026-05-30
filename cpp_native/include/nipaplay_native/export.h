#pragma once

#if defined(_WIN32)
  #ifdef NIPAPLAY_NATIVE_BUILDING
    #define NIPAPLAY_NATIVE_EXPORT __declspec(dllexport)
  #else
    #define NIPAPLAY_NATIVE_EXPORT __declspec(dllimport)
  #endif
#elif defined(__APPLE__)
  #define NIPAPLAY_NATIVE_EXPORT __attribute__((visibility("default")))
#else
  #define NIPAPLAY_NATIVE_EXPORT __attribute__((visibility("default")))
#endif
