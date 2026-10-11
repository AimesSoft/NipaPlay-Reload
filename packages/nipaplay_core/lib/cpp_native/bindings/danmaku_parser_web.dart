/// Web stub for DanmakuParser.
///
/// Provides the same public API as [danmaku_parser_io.dart] without
/// any `dart:ffi` / `package:ffi` imports, so it compiles on Web.
/// On Web the parser is never actually used.

/// Web stub — all methods return null/error, caller should fallback to Dart impl
class DanmakuParser {
  /// 解析 Bilibili 弹幕 XML，返回 JSON 字符串
  /// Web 不可用，返回 null 表示应使用 Dart fallback
  static String? parseXml(String xml) => null;

  /// 解析弹幕 JSON 数组，返回标准化 JSON 字符串
  /// Web 不可用，返回 null 表示应使用 Dart fallback
  static String? parseJson(String jsonStr) => null;

  /// 探测原生绑定是否可用
  static bool probeNativeBinding() => false;

  /// 解析弹幕列表并标准化 — Web 上总是 fallback 到 Dart compute()
  static Future<List<Map<String, dynamic>>> parseDanmakuListOptimized(
    List<dynamic>? danmakuList,
    Future<List<Map<String, dynamic>>> Function(List<dynamic>?) dartFallback,
  ) async {
    return dartFallback(danmakuList);
  }
}
