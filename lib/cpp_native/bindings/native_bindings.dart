import 'dart:ffi';
import 'package:ffi/ffi.dart' show Utf8;
import '../native_library.dart';
import '../types/native_types_io.dart';
import '../types/native_layout_types.dart';
import '../types/native_subtitle_types_io.dart';

class NativeBindings {
  static final _dylib = NativeLibrary.instance;

  // ──── 库级 API ────
  static final npGetVersion = _dylib.lookupFunction<
      Int32 Function(),
      int Function()>('np_get_version');

  static final npStringFree = _dylib.lookupFunction<
      Void Function(Pointer<NpString>),
      void Function(Pointer<NpString>)>('np_string_free');

  // 通用指针释放 — 用于释放 FFI 分配的缓冲区（与 C 侧 malloc/free 对齐）
  static final npFreePtr = _dylib.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('np_free_ptr');

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

  // ──── SimilarityEngine（有状态对象，复用 ~4 MB scratch buffer）───
  static final npSimCreate = _dylib.lookupFunction<
      Pointer<Void> Function(),
      NpHandle Function()>('np_sim_create');

  static final npSimDestroy = _dylib.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(NpHandle)>('np_sim_destroy');

  static final npSimCheckBatch = _dylib.lookupFunction<
      NpResult Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<NpString>),
      NpResult Function(NpHandle, Pointer<Utf8>, Pointer<Utf8>, Pointer<NpString>)>(
      'np_sim_check_batch');

  static final npSimPairSimilarity = _dylib.lookupFunction<
      Double Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
      double Function(Pointer<Utf8>, Pointer<Utf8>, int)>(
      'np_sim_pair_similarity');

  // ──── DanmakuParser ────
  // content_len 使用 Int64 避免大文件（>2GB UTF-8）溢出
  static final npDanmakuParseXml = _dylib.lookupFunction<
      NpResult Function(Pointer<Utf8>, Int64, Pointer<NpString>),
      NpResult Function(Pointer<Utf8>, int, Pointer<NpString>)>(
      'np_danmaku_parse_xml');

  static final npDanmakuParseJson = _dylib.lookupFunction<
      NpResult Function(Pointer<Utf8>, Int64, Pointer<NpString>),
      NpResult Function(Pointer<Utf8>, int, Pointer<NpString>)>(
      'np_danmaku_parse_json');

  // ──── SubtitleParser ────
  // np_subtitle_parse_bytes: 解析字节数据，返回堆分配的 NpSubtitleParseResult*
  // data: 原始字节指针（可能为任意编码，不假设 UTF-8）
  // len: 字节长度（Int32，字幕文件通常 < 2GB）
  // hint_path: 可选文件路径提示（可传 nullptr）
  static final npSubtitleParseBytes = _dylib.lookupFunction<
      Pointer<NpSubtitleParseResult> Function(
          Pointer<Uint8>, Int32, Pointer<Utf8>),
      Pointer<NpSubtitleParseResult> Function(
          Pointer<Uint8>, int, Pointer<Utf8>)>('np_subtitle_parse_bytes');

  // np_subtitle_free_result: 释放解析结果（entries 中所有 NpString + entries + result 本身）
  static final npSubtitleFreeResult = _dylib.lookupFunction<
      Void Function(Pointer<NpSubtitleParseResult>),
      void Function(Pointer<NpSubtitleParseResult>)>(
      'np_subtitle_free_result');
}
