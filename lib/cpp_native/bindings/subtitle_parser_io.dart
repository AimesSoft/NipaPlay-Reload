import 'dart:developer' as developer;
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../../danmaku_next/danmaku_next_log.dart';
import '../native_arena.dart';
import '../types/native_types_io.dart';
import '../types/native_subtitle_types_io.dart';
import 'native_bindings.dart';

/// C++ 字幕解析器的 Dart FFI 封装
///
/// 通过 cpp_native (nipaplay_native DLL) 直接调用 C++ 字幕解析器，
/// 支持 ASS/SRT/SubViewer/MicroDVD 四种格式 + 自动编码检测/转换。
///
/// 返回格式: Map<String, dynamic>，可被 Dart 侧 SubtitleParser 直接转换为
/// SubtitleParseResult，避免循环依赖。
///
/// 内存安全: 所有 C 堆分配的字符串在 np_subtitle_free_result 之前完整复制到
/// Dart String，try/finally 保证 free 总被调用。
class NativeSubtitleParser {
  static const String _logTag = 'NativeSubtitleParser';

  /// format_code 到格式名的映射，与 C++ 侧 SubtitleFormat 枚举一致
  static const Map<int, String> _formatNames = {
    0: 'ass',
    1: 'srt',
    2: 'subViewer',
    3: 'microdvd',
    -1: 'unknown',
  };

  /// 输出应用内日志 — 三通道（Release 模式也可见）：
  ///   1. debugPrint → 控制台回显 + DebugLogService 自动拦截收集到应用内日志查看器
  ///   2. developer.log → DevTools 日志面板
  ///   3. DanmakuNextLog.d → 弹幕引擎日志面板（节流防刷屏）
  /// 与 NipaPlayNextEngine 日志风格一致
  /// 注意: 不显式调用 DebugLogService().addLog()，因为 DebugLogService.initialize()
  /// 已替换 debugPrint 为拦截器，会自动收集，显式调用会导致双重收集。
  static void _log(String status, String message) {
    final line = '[C++] [$status] $message';
    debugPrint('[$_logTag] $line');
    developer.log(line, name: _logTag);
    DanmakuNextLog.d(_logTag, line, throttle: Duration.zero);
  }

  /// 安全读取 NpString 中的 UTF-8 字符串
  /// 如果 data 为空指针或 length 为 0，返回空字符串
  static String _readNpString(NpString npStr) {
    if (npStr.data == nullptr) return '';
    if (npStr.length <= 0) return '';
    try {
      return npStr.data.cast<Utf8>().toDartString(length: npStr.length);
    } catch (e) {
      _log('WARN', '_readNpString: failed to read string ($e), returning empty');
      return '';
    }
  }

  /// 解析字节数据 — 核心入口
  ///
  /// [bytes] 原始字幕文件字节（可能为任意编码）
  /// [hintPath] 可选文件路径，用于编码/格式检测提示（如含 "big5" 优先 Big5）
  ///
  /// 返回 Map<String, dynamic>:
  ///   'entries': List<Map<String, dynamic>> — 字幕条目列表
  ///     每条: {'startTimeMs', 'endTimeMs', 'content', 'style', 'name', 'layer', 'effect'}
  ///   'format': String — 格式名 ('ass'|'srt'|'subViewer'|'microdvd'|'unknown')
  ///   'encoding': String — 检测到的编码名
  ///
  /// 失败返回 null（调用方应 fallback 到 Dart 原实现）
  static Map<String, dynamic>? parseBytes(
    Uint8List bytes, {
    String? hintPath,
  }) {
    final arena = NativeArena();
    Pointer<NpSubtitleParseResult> resultPtr = nullptr;

    try {
      // ── 1. 分配原始字节缓冲区 ──
      // 字幕文件可能为任意编码（GBK/Big5/Shift-JIS），
      // 不能用 toNativeUtf8()（会加 null 终止符且假设 UTF-8）
      final len = bytes.length;
      if (len <= 0) {
        _log('WARN', 'parseBytes: empty input');
        return null;
      }
      // Int32 最大 ~2GB，字幕文件不会超过此限制
      if (len > 0x7FFFFFFF) {
        _log('ERR', 'parseBytes: input too large ($len bytes), exceeds Int32 max');
        return null;
      }

      final dataPtr = arena.allocUint8List(bytes);

      // ── 2. 准备 hint_path 参数 ──
      final hintPtr = hintPath != null
          ? arena.allocUtf8(hintPath)
          : nullptr.cast<Utf8>();

      // ── 3. 调用 C++ 解析 ──
      resultPtr = NativeBindings.npSubtitleParseBytes(
        dataPtr.cast<Uint8>(),
        len,
        hintPtr,
      );

      if (resultPtr == nullptr) {
        _log('ERR', 'parseBytes: C++ returned null pointer');
        return null;
      }

      final result = resultPtr.ref;

      // ── 4. 检查结果码 ──
      final code = npResultCodeFromInt(result.code);
      if (code != NpResultCode.ok) {
        String errMsg = '';
        if (result.errorMessage != nullptr) {
          try {
            errMsg = result.errorMessage.cast<Utf8>().toDartString();
          } catch (_) {}
        }
        _log('ERR', 'parseBytes: C++ returned code=$code'
            '${errMsg.isNotEmpty ? ", msg=$errMsg" : ""}');
        return null;
      }

      // ── 5. 提取所有字符串（必须在 free_result 之前完成） ──
      final entryCount = result.entryCount;
      final formatCode = result.formatCode;
      final formatName = _formatNames[formatCode] ?? 'unknown';
      final detectedEncoding = _readNpString(result.detectedEncoding);

      _log('INFO', 'parseBytes: C++ parsed $entryCount entries, '
          'format=$formatName, encoding=$detectedEncoding '
          'from $len bytes'
          '${hintPath != null ? ", hint=$hintPath" : ""}');

      if (entryCount <= 0) {
        _log('WARN', 'parseBytes: C++ returned 0 entries');
        return null;
      }

      // 遍历 entries 数组，复制所有字符串到 Dart
      final entriesPtr = result.entries;
      if (entriesPtr == nullptr) {
        _log('ERR', 'parseBytes: entries pointer is null but entryCount=$entryCount');
        return null;
      }

      final dartEntries = <Map<String, dynamic>>[];
      for (var i = 0; i < entryCount; i++) {
        try {
          final entry = (entriesPtr + i).ref;
          dartEntries.add({
            'startTimeMs': entry.startTimeMs,
            'endTimeMs': entry.endTimeMs,
            'content': _readNpString(entry.content),
            'style': _readNpString(entry.style),
            'name': _readNpString(entry.name),
            // C struct 无 layer/effect 字段，使用默认值
            // （与 C++ 侧 SubtitleEntry 默认值一致）
            'layer': '0',
            'effect': '',
          });
        } catch (e) {
          _log('WARN', 'parseBytes: failed to read entry[$i] ($e), skipping');
        }
      }

      // ── 6. 防御性检查 ──
      // 如果 C++ 返回 0 条有效条目但声明有数据，可能编码转换失败
      if (dartEntries.isEmpty && entryCount > 0) {
        _log('ERR', 'parseBytes: all entries failed to read, '
            'likely encoding conversion failure');
        return null;
      }

      return {
        'entries': dartEntries,
        'format': formatName,
        'encoding': detectedEncoding,
      };
    } catch (e) {
      _log('ERR', 'parseBytes: C++ exception ($e), falling back to Dart');
      return null;
    } finally {
      // ── 7. 释放 C 堆分配的解析结果 ──
      // 必须在所有字符串复制完成后调用，否则变悬垂指针
      if (resultPtr != nullptr) {
        try {
          NativeBindings.npSubtitleFreeResult(resultPtr);
        } catch (e) {
          _log('WARN', 'parseBytes: failed to free result ($e), potential leak');
        }
      }
      arena.freeAll();
    }
  }

  /// 探测原生绑定是否可用 — 不吞异常，让调用方正确判断 DLL/符号是否存在。
  /// 成功返回 true；如果 DLL 加载或符号查找失败，抛出异常。
  static bool probeNativeBinding() {
    final arena = NativeArena();
    try {
      // 用一个极小输入测试，C++ 会返回格式识别失败而非崩溃
      final testBytes = Uint8List.fromList([0x54, 0x45, 0x53, 0x54]); // "TEST"
      final dataPtr = arena.allocUint8List(testBytes);
      final resultPtr = NativeBindings.npSubtitleParseBytes(
        dataPtr.cast<Uint8>(),
        testBytes.length,
        nullptr.cast<Utf8>(),
      );
      // 无论结果码如何，只要 FFI 调用成功就说明绑定可用
      if (resultPtr != nullptr) {
        NativeBindings.npSubtitleFreeResult(resultPtr);
      }
      _log('INFO', 'probeNativeBinding: native binding available');
      return true;
    } finally {
      arena.freeAll();
    }
  }
}

