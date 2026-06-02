import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/cpp_native/bindings/similarity_engine.dart';

/// 通过 cpp_native (nipaplay_native DLL) 同步调用 C++ 相似度引擎。
///
/// 绕过 flutter_rust_bridge 和 Rust 链路，直接调用原生 C++ 实现。
/// 如果 C++ DLL 未加载或符号不存在，所有方法安全降级返回默认值。
class SimilarityFfiService {
  static SimilarityFfiService? _instance;
  static SimilarityFfiService get instance =>
      _instance ??= SimilarityFfiService._();

  SimilarityFfiService._() {
    _init();
  }

  bool _available = false;

  /// 引擎是否可用
  bool get available => _available;

  void _init() {
    if (kIsWeb) return; // Web 不支持 FFI

    // 使用 probeNativeBinding() 探测 DLL + 符号是否可用。
    // 不使用 pairSimilarity() 因为它会吞掉 FFI 异象并返回 0.0，
    // 导致此处始终认为可用。
    try {
      SimilarityEngine.probeNativeBinding();
      _available = true;
      debugPrint('[SimilarityFFI] ✅ nipaplay_native DLL 加载成功，引擎可用');
    } catch (e) {
      _available = false;
      debugPrint('[SimilarityFFI] ❌ nipaplay_native DLL 加载失败: $e');
    }
  }

  /// 批量查重：输入弹幕列表和配置，返回相似结果 JSON 字符串。
  /// 如果引擎不可用，返回 '{}'。
  String checkSimilarity(List<Map<String, dynamic>> items, Map<String, dynamic> config) {
    if (!_available) {
      debugPrint('[SimilarityFFI] checkSimilarity: 引擎不可用，返回空结果');
      return '{}';
    }

    try {
      // 转换 Map → DanmakuSimItem
      final simItems = items.map((item) => DanmakuSimItem(
        text: item['text'] as String? ?? '',
        mode: item['mode'] as int? ?? 0,
        timeSeconds: (item['time_seconds'] as num?)?.toDouble() ?? 0.0,
      )).toList();

      // 转换 Map → SimilarityConfig
      final simConfig = SimilarityConfig(
        maxDist: config['max_dist'] as int? ?? 5,
        maxCosine: config['max_cosine'] as int? ?? 45,
        usePinyin: config['use_pinyin'] as bool? ?? true,
        crossMode: config['cross_mode'] as bool? ?? true,
        timeWindow: (config['time_window'] as num?)?.toDouble() ?? 30.0,
      );

      debugPrint('[SimilarityFFI] checkSimilarity: 输入 ${items.length} 条弹幕, config=$config');

      final result = SimilarityEngine.checkSimilarity(simItems, simConfig);

      // 转换结果为 JSON 字符串（保持与旧 Rust FFI 兼容的输出格式）
      final jsonMap = <String, dynamic>{
        'pairs': result.pairs.map((p) => {
          'source_index': p.sourceIndex,
          'target_index': p.targetIndex,
          'reason': p.reason,
          'distance': p.distance,
          'score': p.score,
        }).toList(),
        'groups': result.groups,
      };

      final resultJson = json.encode(jsonMap);

      // 诊断
      try {
        final pairCount = result.pairs.length;
        final groupCount = result.groups.length;
        debugPrint('[SimilarityFFI] checkSimilarity: 结果 groups=$groupCount pairs=$pairCount');
      } catch (_) {}

      return resultJson;
    } catch (e) {
      debugPrint('[SimilarityFFI] checkSimilarity 异常: $e');
      return '{}';
    }
  }

  /// 单对相似度：输入两段文本，返回 0.0-1.0 分数。
  /// 如果引擎不可用，返回 0.0。
  double pairSimilarity(String textA, String textB, {bool usePinyin = true}) {
    if (!_available) return 0.0;

    try {
      return SimilarityEngine.pairSimilarity(textA, textB, usePinyin: usePinyin);
    } catch (e) {
      debugPrint('[SimilarityFFI] pairSimilarity 异常: $e');
      return 0.0;
    }
  }
}
