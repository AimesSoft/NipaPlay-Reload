/// Web stub for native FFI types.
///
/// Provides the same public API as [native_types_io.dart] (renamed from
/// native_types.dart) without any `dart:ffi` / `package:ffi` imports,
/// so it compiles on Web. On Web these types are never actually used.

/// Opaque handle — void* on native, dummy on Web.
typedef NpHandle = Object?;

/// NpResultCode — mirrors the native enum without FFI.
enum NpResultCode {
  ok,
  errInvalidArg,
  errNullPtr,
  errOom,
  errInternal,
  errNotFound,
}

/// Convert an integer code to [NpResultCode].
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
