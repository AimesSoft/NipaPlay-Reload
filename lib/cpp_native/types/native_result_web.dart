/// Web stub for native result types.
///
/// Provides the same public API as [native_result_io.dart] (renamed from
/// native_result.dart) without any `dart:ffi` / `package:ffi` imports,
/// so it compiles on Web. On Web these types are never actually used.

import 'native_types_web.dart';

/// Unified error handling — Result<T> pattern
class NativeResult<T> {
  final T? value;
  final NpResultCode code;
  final String? errorMessage;

  const NativeResult.ok(T v)
      : value = v,
        code = NpResultCode.ok,
        errorMessage = null;

  const NativeResult.err(this.code, [this.errorMessage]) : value = null;

  bool get isOk => code == NpResultCode.ok;

  T get requireValue =>
      isOk ? value! : throw NativeException(code, errorMessage);
}

/// FFI exception
class NativeException implements Exception {
  final NpResultCode code;
  final String? message;

  const NativeException(this.code, [this.message]);

  @override
  String toString() =>
      'NativeException($code${message != null ? ": $message" : ""})';
}
