import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';

import '../native_library.dart';
import '../types/native_types.dart';
import '../types/native_result.dart';
import 'native_bindings.dart';

/// 批量查重结果
class SimilarityResult {
  final List<SimilarityPair> pairs;
  final List<List<int>> groups;

  const SimilarityResult({required this.pairs, required this.groups});

  factory SimilarityResult.empty() =>
      const SimilarityResult(pairs: [], groups: []);

  factory SimilarityResult.fromJson(Map<String, dynamic> json) {
    final pairsJson = json['pairs'] as List? ?? [];
    final groupsJson = json['groups'] as List? ?? [];
    return SimilarityResult(
      pairs: pairsJson
          .map((p) => SimilarityPair.fromJson(p as Map<String, dynamic>))
          .toList(),
      groups: groupsJson
          .map((g) => (g as List).map((i) => i as int).toList())
          .toList(),
    );
  }
}

/// 相似对
class SimilarityPair {
  final int sourceIndex;
  final int targetIndex;
  final String reason;
  final int distance;
  final double score;

  const SimilarityPair({
    required this.sourceIndex,
    required this.targetIndex,
    required this.reason,
    required this.distance,
    required this.score,
  });

  factory SimilarityPair.fromJson(Map<String, dynamic> json) {
    return SimilarityPair(
      sourceIndex: json['source_index'] as int,
      targetIndex: json['target_index'] as int,
      reason: json['reason'] as String,
      distance: json['distance'] as int,
      score: (json['score'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'source_index': sourceIndex,
        'target_index': targetIndex,
        'reason': reason,
        'distance': distance,
        'score': score,
      };
}

/// 弹幕条目输入
class DanmakuSimItem {
  final String text;
  final int mode; // 0=scroll, 1=top, 2=bottom
  final double timeSeconds;

  const DanmakuSimItem({
    required this.text,
    required this.mode,
    required this.timeSeconds,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'mode': mode,
        'time_seconds': timeSeconds,
      };
}

/// 相似度配置
class SimilarityConfig {
  final int maxDist;
  final int maxCosine;
  final bool usePinyin;
  final bool crossMode;
  final double timeWindow;

  const SimilarityConfig({
    this.maxDist = 3,
    this.maxCosine = 70,
    this.usePinyin = true,
    this.crossMode = false,
    this.timeWindow = 45.0,
  });

  Map<String, dynamic> toJson() => {
        'max_dist': maxDist,
        'max_cosine': maxCosine,
        'use_pinyin': usePinyin,
        'cross_mode': crossMode,
        'time_window': timeWindow,
      };
}

/// C++ 弹幕相似度引擎的 Dart FFI 封装
///
/// 通过 cpp_native (nipaplay_native DLL) 直接调用 C++ 相似度引擎，
/// 绕过 Rust 链路，避免 Rust-C++ FFI 开销。
class SimilarityEngine {
  /// 批量查重：输入弹幕列表和配置，返回相似结果。
  /// 如果引擎不可用，返回空结果。
  static SimilarityResult checkSimilarity(
      List<DanmakuSimItem> items, SimilarityConfig config) {
    if (items.isEmpty) return SimilarityResult.empty();

    final itemsJson = json.encode(items.map((i) => i.toJson()).toList());
    final configJson = json.encode(config.toJson());

    final itemsPtr = itemsJson.toNativeUtf8();
    final configPtr = configJson.toNativeUtf8();
    final outputPtr = calloc<NpString>();

    try {
      final result = NativeBindings.npSimCheckBatch(
          itemsPtr, configPtr, outputPtr);

      final code = npResultCodeFromInt(result.code);
      if (code != NpResultCode.ok) {
        return SimilarityResult.empty();
      }

      final output = outputPtr.ref;
      if (output.data == nullptr) {
        return SimilarityResult.empty();
      }

      try {
        final resultStr = output.data.cast<Utf8>().toDartString();
        final decoded = json.decode(resultStr);
        if (decoded is Map<String, dynamic>) {
          return SimilarityResult.fromJson(decoded);
        }
        return SimilarityResult.empty();
      } finally {
        // 用 np_string_free 释放 C++ 分配的字符串
        NativeBindings.npStringFree(outputPtr);
      }
    } catch (_) {
      return SimilarityResult.empty();
    } finally {
      malloc.free(itemsPtr);
      malloc.free(configPtr);
      calloc.free(outputPtr);
    }
  }

  /// 单对相似度：输入两段文本，返回 0.0-1.0 分数。
  static double pairSimilarity(String textA, String textB,
      {bool usePinyin = true}) {
    final aPtr = textA.toNativeUtf8();
    final bPtr = textB.toNativeUtf8();

    try {
      return NativeBindings.npSimPairSimilarity(
          aPtr, bPtr, usePinyin ? 1 : 0);
    } catch (_) {
      return 0.0;
    } finally {
      malloc.free(aPtr);
      malloc.free(bPtr);
    }
  }
}
