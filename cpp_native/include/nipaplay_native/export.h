#pragma once

#if defined(_WIN32)
  #ifdef NIPAPLAY_NATIVE_BUILDING
    #define NIPAPLAY_NATIVE_EXPORT __declspec(dllexport)
  #else
    #define NIPAPLAY_NATIVE_EXPORT __declspec(dllimport)
  #endif
#elif defined(__APPLE__)
  // used: 标记为 dead_strip 根。np_* 符号只被 Dart FFI 运行期
  // DynamicLibrary.process() 查找，链接期无引用，Xcode
  // DEAD_CODE_STRIPPING 会把整批符号裁掉（实测 np_string_free
  // dlsym 找不到，弹幕解析静默回退 Dart）。
  #define NIPAPLAY_NATIVE_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#else
  #define NIPAPLAY_NATIVE_EXPORT __attribute__((visibility("default")))
#endif
