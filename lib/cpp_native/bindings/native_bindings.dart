import 'dart:ffi';
import 'package:ffi/ffi.dart' show Utf8;
import '../native_library.dart';
import '../types/native_types.dart';
import '../types/native_layout_types.dart';

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

  // ──── DanmakuLayoutEngine ────
  static final npLayoutCreate = _dylib.lookupFunction<
      Pointer<Void> Function(),
      NpHandle Function()>('np_layout_create');

  static final npLayoutDestroy = _dylib.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(NpHandle)>('np_layout_destroy');

  static final npLayoutConfigure = _dylib.lookupFunction<
      NpResult Function(Pointer<Void>, Pointer<NpDanmakuItem>, Int32,
          Double, Double, Double, Double, Double, Double,
          Int32, Double, Double),
      NpResult Function(NpHandle, Pointer<NpDanmakuItem>, int,
          double, double, double, double, double, double,
          int, double, double)>('np_layout_configure');

  static final npLayoutFrame = _dylib.lookupFunction<
      NpResult Function(Pointer<Void>, Double,
          Pointer<NpLayoutResult>, Int32, Pointer<Int32>),
      NpResult Function(NpHandle, double,
          Pointer<NpLayoutResult>, int, Pointer<Int32>)>('np_layout_frame');

  static final npLayoutFrameRaw = _dylib.lookupFunction<
      NpResult Function(Pointer<Void>, Double,
          Pointer<NpFrameRawOutput>, Int32, Pointer<Int32>),
      NpResult Function(NpHandle, double,
          Pointer<NpFrameRawOutput>, int, Pointer<Int32>)>('np_layout_frame_raw');

  // ──── SimilarityEngine ────
  static final npSimCheckBatch = _dylib.lookupFunction<
      NpResult Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<NpString>),
      NpResult Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<NpString>)>(
      'np_sim_check_batch');

  static final npSimPairSimilarity = _dylib.lookupFunction<
      Double Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
      double Function(Pointer<Utf8>, Pointer<Utf8>, int)>(
      'np_sim_pair_similarity');
}
