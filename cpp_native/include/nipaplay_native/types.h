#pragma once
#include <stdint.h>

// 不透明句柄 — Dart 侧作为 Pointer<Void>
// 64-bit 平台: 8 字节; 32-bit 平台 (armeabi-v7a): 4 字节
// Dart 侧统一使用 Pointer<Void>，FFI 自动适配
typedef void* NpHandle;

// 统一结果码
typedef enum NpResultCode : int32_t {
    NP_OK              = 0,
    NP_ERR_INVALID_ARG = 1,
    NP_ERR_NULL_PTR    = 2,
    NP_ERR_OOM         = 3,
    NP_ERR_INTERNAL    = 4,
    NP_ERR_NOT_FOUND   = 5,
} NpResultCode;

// 带错误信息的结果
typedef struct NpResult {
    NpResultCode code;
    const char* message;  // 仅在 code != NP_OK 时有效，UTF-8，指向静态字符串
} NpResult;

// C → Dart 字符串（Dart 侧负责调用 np_string_free 释放）
typedef struct NpString {
    const char* data;   // UTF-8，null-terminated，由 np_string_alloc 分配
    int32_t length;     // 不含 null terminator
} NpString;
