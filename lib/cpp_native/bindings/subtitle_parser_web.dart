/// Web stub for SubtitleParser.
///
/// Provides the same public API as [subtitle_parser_io.dart] without
/// any `dart:ffi` / `package:ffi` imports, so it compiles on Web.
/// On Web the parser is never actually used.

import 'dart:typed_data';

/// Web stub — 与 Dart 侧 SubtitleParseResult 类型解耦，
/// 返回 null 表示应使用 Dart fallback
class NativeSubtitleParser {
  /// 解析字节数据
  /// Web 不可用，返回 null 表示应使用 Dart fallback
  static Map<String, dynamic>? parseBytes(
    Uint8List bytes, {
    String? hintPath,
  }) => null;

  /// 探测原生绑定是否可用
  static bool probeNativeBinding() => false;
}
