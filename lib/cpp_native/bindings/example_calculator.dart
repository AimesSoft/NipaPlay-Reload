import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../native_library.dart';
import '../types/native_types.dart';
import '../types/native_result.dart';
import 'native_bindings.dart';

class ExampleCalculator implements Finalizable {
  NpHandle _handle;
  bool _isReleased = false;

  // NativeFinalizer：当 Dart 对象被 GC 回收时自动调用 destroy
  // 必须使用 lookup 获取原生函数指针，不能使用 lookupFunction 返回的 Dart 函数对象
  static final _finalizer = NativeFinalizer(
    NativeLibrary.instance.lookup<
        NativeFunction<Void Function(Pointer<Void>)>
      >('np_example_destroy'),
  );

  ExampleCalculator._(this._handle) {
    _finalizer.attach(this, _handle, detach: this, externalSize: 256);
  }

  /// 工厂构造：创建 C++ 引擎实例
  factory ExampleCalculator() {
    final handle = NativeBindings.npExampleCreate();
    if (handle == nullptr) {
      throw NativeException(
          NpResultCode.errNullPtr, 'failed to create ExampleCalculator');
    }
    return ExampleCalculator._(handle);
  }

  int add(int a, int b) {
    _checkReleased();
    return NativeBindings.npExampleAdd(_handle, a, b);
  }

  NativeResult<String> processText(String input) {
    _checkReleased();
    final cInput = input.toNativeUtf8();
    final outString = calloc<NpString>();
    try {
      final result = NativeBindings.npExampleProcessText(
        _handle,
        cInput,
        outString,
      );
      final code = npResultCodeFromInt(result.code);
      if (code != NpResultCode.ok) {
        final msg = result.message != nullptr
            ? result.message.cast<Utf8>().toDartString()
            : null;
        return NativeResult.err(code, msg);
      }
      final text = outString.ref.data.cast<Utf8>().toDartString(
            length: outString.ref.length,
          );
      NativeBindings.npStringFree(outString);
      return NativeResult.ok(text);
    } finally {
      calloc.free(cInput);
      calloc.free(outString);
    }
  }

  void dispose() {
    if (!_isReleased) {
      _finalizer.detach(this);
      NativeBindings.npExampleDestroy(_handle);
      _isReleased = true;
    }
  }

  void _checkReleased() {
    if (_isReleased) throw StateError('ExampleCalculator used after dispose');
  }
}
