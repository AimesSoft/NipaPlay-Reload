import 'dart:ffi';
import '../native_library.dart';
import '../types/native_types.dart';

class NativeBindings {
  static final _dylib = NativeLibrary.instance;

  // ──── 库级 API ────
  static final npGetVersion = _dylib.lookupFunction<
      Int32 Function(),
      int Function()>('np_get_version');

  static final npStringFree = _dylib.lookupFunction<
      Void Function(Pointer<NpString>),
      void Function(Pointer<NpString>)>('np_string_free');

  // ──── ExampleCalculator ────
  static final npExampleCreate = _dylib.lookupFunction<
      Pointer<Void> Function(),
      NpHandle Function()>('np_example_create');

  static final npExampleDestroy = _dylib.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(NpHandle)>('np_example_destroy');

  static final npExampleAdd = _dylib.lookupFunction<
      Int32 Function(Pointer<Void>, Int32, Int32),
      int Function(NpHandle, int, int)>('np_example_add');

  static final npExampleProcessText = _dylib.lookupFunction<
      NpResult Function(Pointer<Void>, Pointer<Utf8>, Pointer<NpString>),
      NpResult Function(NpHandle, Pointer<Utf8>, Pointer<NpString>)>(
      'np_example_process_text');
}
