import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

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
/// 如果 Rust DLL 未加载或符号不存在，所有方法安全降级返回默认值。
class SimilarityFfiService {
  static SimilarityFfiService? _instance;
  static SimilarityFfiService get instance =>
      _instance ??= SimilarityFfiService._();

  SimilarityFfiService._() {
    _init();
  }

  DynamicLibrary? _dylib;
  _SimilarityCheckBatchDart? _checkBatch;
  _SimilarityPairDart? _pair;
  _SimilarityFreeCstringDart? _freeCstring;
  bool _available = false;

  /// 引擎是否可用（DLL 加载且符号查找成功）
  bool get available => _available;

  void _init() {
    if (kIsWeb) return; // Web 不支持 FFI

    try {
      _dylib = _openDynamicLibrary();
      _checkBatch = _dylib!.lookupFunction<
          _SimilarityCheckBatchC,
          _SimilarityCheckBatchDart>('similarity_check_batch');
      _pair = _dylib!.lookupFunction<
          _SimilarityPairC,
          _SimilarityPairDart>('similarity_pair');
      _freeCstring = _dylib!.lookupFunction<
          _SimilarityFreeCstringC,
          _SimilarityFreeCstringDart>('similarity_free_cstring');
      _available = true;
      debugPrint('[SimilarityFFI] 初始化成功');
    } catch (e) {
      _available = false;
      debugPrint('[SimilarityFFI] 初始化失败（相似度查重不可用）: $e');
    }
  }

  /// 批量查重：输入弹幕列表和配置，返回相似结果 JSON 字符串。
  /// 如果引擎不可用，返回 '{}'。
  String checkSimilarity(List<Map<String, dynamic>> items, Map<String, dynamic> config) {
    if (!_available || _checkBatch == null || _freeCstring == null) return '{}';

    final itemsJson = json.encode(items);
    final configJson = json.encode(config);

    final itemsPtr = itemsJson.toNativeUtf8();
    final configPtr = configJson.toNativeUtf8();

    try {
      final resultPtr = _checkBatch!(itemsPtr, configPtr);
      if (resultPtr == nullptr) return '{}';
      try {
        return resultPtr.toDartString();
      } finally {
        _freeCstring!(resultPtr);
      }
    } catch (e) {
      debugPrint('[SimilarityFFI] checkSimilarity 异常: $e');
      return '{}';
    } finally {
      malloc.free(itemsPtr);
      malloc.free(configPtr);
    }
  }

  /// 单对相似度：输入两段文本，返回 0.0-1.0 分数。
  /// 如果引擎不可用，返回 0.0。
  double pairSimilarity(String textA, String textB, {bool usePinyin = true}) {
    if (!_available || _pair == null) return 0.0;

    final aPtr = textA.toNativeUtf8();
    final bPtr = textB.toNativeUtf8();

    try {
      return _pair!(aPtr, bPtr, usePinyin ? 1 : 0);
    } catch (e) {
      debugPrint('[SimilarityFFI] pairSimilarity 异常: $e');
      return 0.0;
    } finally {
      malloc.free(aPtr);
      malloc.free(bPtr);
    }
  }

  static DynamicLibrary _openDynamicLibrary() {
    const stem = 'rust_lib_nipaplay';

    if (Platform.isIOS) {
      return DynamicLibrary.process();
    }

    if (Platform.isAndroid) {
      return DynamicLibrary.open('lib$stem.so');
    }

    // macOS / Linux / Windows: 从 exe 所在目录查找 DLL
    if (Platform.isMacOS) {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      return DynamicLibrary.open(p.join(exeDir, '$stem.dylib'));
    }

    if (Platform.isLinux) {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      return DynamicLibrary.open(p.join(exeDir, 'lib$stem.so'));
    }

    if (Platform.isWindows) {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      // Flutter 桌面: DLL 在 exe 同目录
      return DynamicLibrary.open(p.join(exeDir, '$stem.dll'));
    }

    throw UnsupportedError('不支持的平台');
  }
}
