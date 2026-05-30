/// Web stub for SimilarityFfiService.
///
/// Provides the same public API as [similarity_ffi_service_io.dart] without
/// any `dart:ffi` / `package:ffi` / `dart:io` imports, so it compiles on Web.
/// On Web the FFI service is never actually used.

/// 通过 Dart FFI 同步调用 Rust 相似度引擎（Web stub）。
///
/// Web 平台不支持 FFI，所有方法安全降级返回默认值。
class SimilarityFfiService {
  static SimilarityFfiService? _instance;
  static SimilarityFfiService get instance =>
      _instance ??= SimilarityFfiService._();

  SimilarityFfiService._();

  /// 引擎是否可用 — Web 上始终为 false
  bool get available => false;

  /// 批量查重：Web 上返回 '{}'
  String checkSimilarity(
      List<Map<String, dynamic>> items, Map<String, dynamic> config) {
    return '{}';
  }

  /// 单对相似度：Web 上返回 0.0
  double pairSimilarity(String textA, String textB, {bool usePinyin = true}) {
    return 0.0;
  }
}
