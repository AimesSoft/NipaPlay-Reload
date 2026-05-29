import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

// ===== FFI 类型定义 =====

typedef _SimilarityCheckBatchC = Pointer<Utf8> Function(
  Pointer<Utf8> itemsJson,
  Pointer<Utf8> configJson,
);
typedef _SimilarityCheckBatchDart = Pointer<Utf8> Function(
  Pointer<Utf8> itemsJson,
  Pointer<Utf8> configJson,
);

typedef _SimilarityPairC = Double Function(
  Pointer<Utf8> textA,
  Pointer<Utf8> textB,
  Int32 usePinyin,
);
typedef _SimilarityPairDart = double Function(
  Pointer<Utf8> textA,
  Pointer<Utf8> textB,
  int usePinyin,
);

typedef _SimilarityFreeCstringC = Void Function(Pointer<Utf8> ptr);
typedef _SimilarityFreeCstringDart = void Function(Pointer<Utf8> ptr);

/// 通过 Dart FFI 同步调用 Rust 相似度引擎。
///
/// 绕过 flutter_rust_bridge 的异步管线，使 JS 插件桥接可以同步返回结果。
class SimilarityFfiService {
  static SimilarityFfiService? _instance;
  static SimilarityFfiService get instance =>
      _instance ??= SimilarityFfiService._();

  SimilarityFfiService._() {
    _init();
  }

  late final DynamicLibrary _dylib;
  late final _SimilarityCheckBatchDart _checkBatch;
  late final _SimilarityPairDart _pair;
  late final _SimilarityFreeCstringDart _freeCstring;

  void _init() {
    _dylib = _openDynamicLibrary();
    _checkBatch = _dylib.lookupFunction<
        _SimilarityCheckBatchC,
        _SimilarityCheckBatchDart>('similarity_check_batch');
    _pair = _dylib.lookupFunction<
        _SimilarityPairC,
        _SimilarityPairDart>('similarity_pair');
    _freeCstring = _dylib.lookupFunction<
        _SimilarityFreeCstringC,
        _SimilarityFreeCstringDart>('similarity_free_cstring');
  }

  /// 批量查重：输入弹幕列表和配置，返回相似结果 JSON 字符串。
  String checkSimilarity(List<Map<String, dynamic>> items, Map<String, dynamic> config) {
    final itemsJson = json.encode(items);
    final configJson = json.encode(config);

    final itemsPtr = itemsJson.toNativeUtf8();
    final configPtr = configJson.toNativeUtf8();

    try {
      final resultPtr = _checkBatch(itemsPtr, configPtr);
      if (resultPtr == nullptr) return '{}';
      try {
        return resultPtr.toDartString();
      } finally {
        _freeCstring(resultPtr);
      }
    } finally {
      malloc.free(itemsPtr);
      malloc.free(configPtr);
    }
  }

  /// 单对相似度：输入两段文本，返回 0.0-1.0 分数。
  double pairSimilarity(String textA, String textB, {bool usePinyin = true}) {
    final aPtr = textA.toNativeUtf8();
    final bPtr = textB.toNativeUtf8();

    try {
      return _pair(aPtr, bPtr, usePinyin ? 1 : 0);
    } finally {
      malloc.free(aPtr);
      malloc.free(bPtr);
    }
  }

  static DynamicLibrary _openDynamicLibrary() {
    if (kIsWeb) {
      throw UnsupportedError('相似度 FFI 不支持 Web 平台');
    }

    const stem = 'rust_lib_nipaplay';

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => DynamicLibrary.open('lib$stem.so'),
      TargetPlatform.linux => DynamicLibrary.open('lib$stem.so'),
      TargetPlatform.windows => DynamicLibrary.open('$stem.dll'),
      TargetPlatform.macOS => DynamicLibrary.open('$stem.dylib'),
      TargetPlatform.iOS => DynamicLibrary.process(),
      _ => throw UnsupportedError('不支持的平台'),
    };
  }
}
