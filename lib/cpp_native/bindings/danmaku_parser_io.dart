import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../native_arena.dart';
import '../native_library.dart';
import '../types/native_types_io.dart';
import '../types/native_result_io.dart';
import 'native_bindings.dart';

/// C++ 弹幕解析器的 Dart FFI 封装
///
/// 通过 cpp_native (nipaplay_native DLL) 直接调用 C++ 弹幕解析器，
/// 替代 Dart 侧 XmlDocument.parse + 正则回退 + Isolate 标准化。
class DanmakuParser {
  static const String _logTag = 'DanmakuParser';

  /// 输出 C++ 路径日志，格式仿照 [NipaPlayNextEngine]
  static void _logCpp(String status, String message) {
    debugPrint('[$_logTag] [C++] [$status] $message');
  }

  /// 解析 Bilibili 弹幕 XML，返回 JSON 字符串
  /// 输出格式: {"count":N,"comments":[{"t":...,"c":...,"y":...,"r":...,"fontSize":...,"originalType":...},...]}
  /// 与 Dart 侧 convertBilibiliXmlDanmakuToJson 输出完全一致
  ///
  /// 成功返回 JSON 字符串，失败返回 null（调用方应 fallback 到 Dart 原实现）
  static String? parseXml(String xml) {
    final arena = NativeArena();
    try {
      final cInput = arena.allocUtf8(xml);
      final outString = arena.allocNpString();

      // ⚠️ 必须使用 UTF-8 字节长度而非 Dart String.length（UTF-16 码元数）。
      // 对于含中文的弹幕 XML，UTF-8 字节数远大于 UTF-16 码元数，
      // 例如 dartStringLength=3937371 vs utf8ByteLength=5856986 (diff=1919615)。
      // 如果传入 UTF-16 长度，C++ 的 string_view 会被截断，导致解析失败。
      final utf8ByteLength = utf8.encode(xml).length;

      final result = NativeBindings.npDanmakuParseXml(
        cInput,
        utf8ByteLength,
        outString,
      );
      final code = npResultCodeFromInt(result.code);
      if (code != NpResultCode.ok) {
        _logCpp('ERR', 'parseXml: C++ returned code=$code');
        return null;
      }
      final json = outString.ref.data.cast<Utf8>().toDartString(
            length: outString.ref.length,
          );
      // 提取 count 用于日志，避免完整 jsonDecode 开销
      final countMatch = RegExp(r'"count":(\d+)').firstMatch(json);
      _logCpp('OK', 'parseXml: ${countMatch?.group(1) ?? "?"} comments '
          'from $utf8ByteLength UTF-8 bytes');
      return json;
    } catch (_) {
      _logCpp('ERR', 'parseXml: C++ exception, falling back to Dart');
      return null;
    } finally {
      arena.freeAll();
    }
  }

  /// 解析弹幕 JSON 数组，返回标准化 JSON 字符串
  /// 输出格式: {"count":N,"comments":[{"time":...,"content":...,"type":...,"color":...,...},...]}
  /// 支持双源字段映射: t/time, c/content, y/type, r/color
  /// 保留所有非标准额外字段
  ///
  /// 成功返回 JSON 字符串，失败返回 null（调用方应 fallback 到 Dart 原实现）
  static String? parseJson(String jsonStr) {
    final arena = NativeArena();
    try {
      final cInput = arena.allocUtf8(jsonStr);
      final outString = arena.allocNpString();

      // ⚠️ 必须使用 UTF-8 字节长度而非 Dart String.length（UTF-16 码元数）。
      // 对于含中文的弹幕 JSON，UTF-8 字节数远大于 UTF-16 码元数，
      // 例如 dartStringLength=3005603 vs utf8ByteLength=3591806 (diff=586203)。
      // 如果传入 UTF-16 长度，C++ 的 string_view 会被截断，导致 rapidjson 解析失败。
      final utf8ByteLength = utf8.encode(jsonStr).length;

      final result = NativeBindings.npDanmakuParseJson(
        cInput,
        utf8ByteLength,
        outString,
      );
      final code = npResultCodeFromInt(result.code);
      if (code != NpResultCode.ok) {
        _logCpp('ERR', 'parseJson: C++ returned code=$code');
        return null;
      }
      final json = outString.ref.data.cast<Utf8>().toDartString(
            length: outString.ref.length,
          );
      // 提取 count 用于日志，避免完整 jsonDecode 开销
      final countMatch = RegExp(r'"count":(\d+)').firstMatch(json);
      _logCpp('OK', 'parseJson: ${countMatch?.group(1) ?? "?"} comments '
          'from $utf8ByteLength UTF-8 bytes');
      return json;
    } catch (_) {
      _logCpp('ERR', 'parseJson: C++ exception, falling back to Dart');
      return null;
    } finally {
      arena.freeAll();
    }
  }

  /// 探测原生绑定是否可用——不吞异常，让调用方正确判断 DLL/符号是否存在。
  /// 成功返回 true；如果 DLL 加载或符号查找失败，抛出异常。
  static bool probeNativeBinding() {
    final arena = NativeArena();
    try {
      final testPtr = arena.allocUtf8('');
      final outPtr = arena.allocNpString();
      // 触发 NativeBindings 的 lookupFunction + 一次 FFI 调用
      NativeBindings.npDanmakuParseXml(testPtr, 0, outPtr);
      return true;
    } finally {
      arena.freeAll();
    }
  }

  /// 解析弹幕列表并标准化 — 优先 C++，失败则 fallback 到 Dart compute()
  ///
  /// C++ 路径: jsonEncode(danmakuList) → C++ parseJson → jsonDecode → List<Map>
  /// Dart 路径: compute(parseDanmakuListInBackground, danmakuList)
  ///
  /// 注意: C++ 路径有 JSON 往返序列化开销（3次），但对于万级弹幕列表，
  /// C++ 的零 GC 压力 + 批量处理仍优于 Dart 逐条 Map 转换。
  /// 对于小列表（<100条），Dart compute() 可能更快，但差异可忽略。
  ///
  /// [danmakuList] 原始弹幕列表（List<Map<String, dynamic>> 或 List<dynamic>）
  /// [dartFallback] Dart 侧的 compute 回调函数（parseDanmakuListInBackground）
  /// 返回标准化后的弹幕列表
  static Future<List<Map<String, dynamic>>> parseDanmakuListOptimized(
    List<dynamic>? danmakuList,
    Future<List<Map<String, dynamic>>> Function(List<dynamic>?) dartFallback,
  ) async {
    if (danmakuList == null || danmakuList.isEmpty) {
      return [];
    }

    // 尝试 C++ 路径
    try {
      final jsonStr = jsonEncode(danmakuList);
      final result = parseJson(jsonStr);
      if (result != null) {
        final parsed = jsonDecode(result) as Map<String, dynamic>;
        final comments = parsed['comments'] as List<dynamic>;
        // 防御性检查: 如果 C++ 返回 0 条弹幕但输入有明显数据，
        // 可能是 FFI content_len 传错、JSON 被截断等异常情况，
        // 应 fallback 到 Dart 而非返回空列表导致弹幕消失。
        if (comments.isEmpty && danmakuList.isNotEmpty) {
          _logCpp('ERR', 'parseDanmakuListOptimized: C++ returned 0 comments '
              'for ${danmakuList.length} input items; falling back to Dart');
          return dartFallback(danmakuList);
        }
        _logCpp('OK', 'parseDanmakuListOptimized: ${comments.length} items via C++ path');
        return comments.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      // C++ 解析失败，fallback
      _logCpp('ERR', 'parseDanmakuListOptimized: C++ exception ($e), falling back to Dart');
    }

    // Fallback: Dart compute()
    return dartFallback(danmakuList);
  }
}
