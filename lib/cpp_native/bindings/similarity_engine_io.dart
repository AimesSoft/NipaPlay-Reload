import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../native_library.dart';
import '../types/native_types_io.dart';
import '../types/native_result_io.dart';
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
    this.maxDist = 5,
    this.maxCosine = 45,
    this.usePinyin = true,
    this.crossMode = true,
    this.timeWindow = 30.0,
  });

  Map<String, dynamic> toJson() => {
        'max_dist': maxDist,
        'max_cosine': maxCosine,
        'use_pinyin': usePinyin,
        'cross_mode': crossMode,
        'time_window': timeWindow,
      };
}

/// C++ 弹幕相似度引擎的 Dart FFI 封装（有状态对象）
///
/// 引擎实例持有 ~4 MB scratch buffer，跨调用复用避免重复分配。
/// 使用 NativeFinalizer 保证 C++ 对象在 GC 时被释放。
class SimilarityEngine implements Finalizable {
  NpHandle _handle;
  bool _isReleased = false;

  static final _finalizer = NativeFinalizer(
    NativeLibrary.instance.lookup<
        NativeFunction<Void Function(Pointer<Void>)>>('np_sim_destroy'),
  );

  SimilarityEngine._(this._handle) {
    // externalSize: ~4 MB scratch buffer (ed_a_ + ed_b_ + str_buf_)
    _finalizer.attach(this, _handle, detach: this, externalSize: 4194304);
  }

  /// 工厂构造：创建 C++ 相似度引擎实例（~4 MB 内存）
  factory SimilarityEngine() {
    final handle = NativeBindings.npSimCreate();
    if (handle == nullptr) {
      throw const NativeException(
          NpResultCode.errNullPtr, 'failed to create SimilarityEngine');
    }
    return SimilarityEngine._(handle);
  }

  /// 批量查重：输入弹幕列表和配置，返回相似结果。
  /// 复用引擎实例的 scratch buffer，避免每次 ~4 MB 分配。
  SimilarityResult checkSimilarity(
      List<DanmakuSimItem> items, SimilarityConfig config) {
    _checkReleased();

    if (items.isEmpty) return SimilarityResult.empty();

    final itemsJson = json.encode(items.map((i) => i.toJson()).toList());
    final configJson = json.encode(config.toJson());

    final itemsPtr = itemsJson.toNativeUtf8();
    final configPtr = configJson.toNativeUtf8();
    final outputPtr = calloc<NpString>();

    try {
      final result = NativeBindings.npSimCheckBatch(
          _handle, itemsPtr, configPtr, outputPtr);

      final code = npResultCodeFromInt(result.code);
      if (code != NpResultCode.ok) {
        debugPrint('[SimEngine] npSimCheckBatch error: code=$code');
        return SimilarityResult.empty();
      }

      final output = outputPtr.ref;
      if (output.data == nullptr) {
        return SimilarityResult.empty();
      }

      final resultStr = output.data.cast<Utf8>().toDartString();
      final decoded = json.decode(resultStr);
      if (decoded is Map<String, dynamic>) {
        return SimilarityResult.fromJson(decoded);
      }
      return SimilarityResult.empty();
    } catch (e, st) {
      debugPrint('[SimEngine] Exception: $e\n$st');
      return SimilarityResult.empty();
    } finally {
      NativeBindings.npStringFree(outputPtr);
      malloc.free(itemsPtr);
      malloc.free(configPtr);
      calloc.free(outputPtr);
    }
  }

  /// 单对相似度：输入两段文本，返回 0.0-1.0 分数。
  /// 使用独立临时引擎，不依赖此实例。
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

  /// 探测原生绑定是否可用——不吞异常，让调用方正确判断 DLL/符号是否存在。
  /// 成功返回 true；如果 DLL 加载或符号查找失败，抛出异常。
  static bool probeNativeBinding() {
    final aPtr = ''.toNativeUtf8();
    final bPtr = ''.toNativeUtf8();
    try {
      NativeBindings.npSimPairSimilarity(aPtr, bPtr, 0);
      return true;
    } finally {
      malloc.free(aPtr);
      malloc.free(bPtr);
    }
  }

  void dispose() {
    if (!_isReleased) {
      _finalizer.detach(this);
      NativeBindings.npSimDestroy(_handle);
      _isReleased = true;
    }
  }

  void _checkReleased() {
    if (_isReleased) throw StateError('SimilarityEngine used after dispose');
  }
}
