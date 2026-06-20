import 'native_types_io.dart';

/// 统一错误处理 — Result<T> 模式
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

/// FFI 异常
class NativeException implements Exception {
  final NpResultCode code;
  final String? message;

  const NativeException(this.code, [this.message]);

  @override
  String toString() =>
      'NativeException($code${message != null ? ": $message" : ""})';
}
