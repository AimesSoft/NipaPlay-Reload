import 'dart:ffi';
import 'package:ffi/ffi.dart' show Utf8;

import 'native_types_io.dart';

/// NpSubtitleEntry — 字幕条目结构
/// 对应 C++ 侧的 NpSubtitleEntry
/// 字段顺序必须与 C 结构体完全一致，Dart FFI 按声明顺序排列
///
/// 64-bit 布局: 56B
///   offset  0: int32_t start_time_ms (4B)
///   offset  4: int32_t end_time_ms   (4B)
///   offset  8: NpString content      (16B: Pointer(8B) + Int32(4B) + pad(4B))
///   offset 24: NpString style        (16B)
///   offset 40: NpString name         (16B)
///
/// 32-bit 布局: 32B (NpString = 8B, 无 padding)
final class NpSubtitleEntry extends Struct {
  @Int32()
  external int startTimeMs;

  @Int32()
  external int endTimeMs;

  external NpString content;

  external NpString style;

  external NpString name;
}

/// NpSubtitleParseResult — 字幕解析结果结构
/// 对应 C++ 侧的 NpSubtitleParseResult
/// 堆分配，由 np_subtitle_free_result 统一释放
///
/// 64-bit 布局: 48B
///   offset  0: NpResultCode code           (4B + pad 4B)
///   offset  8: const char* error_message    (8B)
///   offset 16: NpSubtitleEntry* entries     (8B)
///   offset 24: int32_t entry_count          (4B)
///   offset 28: int32_t format_code          (4B)
///   offset 32: NpString detected_encoding   (16B)
///
/// format_code: 0=ass, 1=srt, 2=subviewer, 3=microdvd, -1=unknown
final class NpSubtitleParseResult extends Struct {
  @Int32()
  external int code;

  external Pointer<Utf8> errorMessage;

  external Pointer<NpSubtitleEntry> entries;

  @Int32()
  external int entryCount;

  @Int32()
  external int formatCode;

  external NpString detectedEncoding;
}
