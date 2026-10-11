import 'dart:ffi';
import 'package:ffi/ffi.dart' show Utf8;

/// NpHandle — 不透明句柄，对应 C++ 侧的 void*
/// 在 32-bit 平台 (armeabi-v7a) 为 4 字节，64-bit 为 8 字节
/// Dart 侧始终使用 Pointer<Void>，FFI 自动适配
typedef NpHandle = Pointer<Void>;

/// NpResultCode — 统一结果码，对应 C++ 侧的 NpResultCode 枚举
enum NpResultCode {
  ok,
  errInvalidArg,
  errNullPtr,
  errOom,
  errInternal,
  errNotFound,
}

/// NpString — C → Dart 字符串结构体
/// 对应 C++ 侧的 NpString
final class NpString extends Struct {
  external Pointer<Utf8> data;
  @Int32()
  external int length;
}

/// NpResult — 带错误信息的结果
/// 对应 C++ 侧的 NpResult
final class NpResult extends Struct {
  @Int32()
  external int code;

  external Pointer<Utf8> message;
}

/// 将 C NpResult.code 转换为 Dart NpResultCode 枚举
NpResultCode npResultCodeFromInt(int code) {
  return switch (code) {
    0 => NpResultCode.ok,
    1 => NpResultCode.errInvalidArg,
    2 => NpResultCode.errNullPtr,
    3 => NpResultCode.errOom,
    4 => NpResultCode.errInternal,
    5 => NpResultCode.errNotFound,
    _ => NpResultCode.errInternal,
  };
}
