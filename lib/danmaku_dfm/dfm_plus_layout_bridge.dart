import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/src/rust/api/dfm_plus.dart' as rust_dfm;
import 'package:nipaplay/src/rust/rust_init.dart';

class DfmPlusLayoutBridge {
  rust_dfm.DfmPlusPreparedLayout? _prepared;
  int _sourceListIdentity = 0;
  int _sourceListVersion = -1;
  double _lastFontSize = -1;
  double _lastDisplayArea = -1;
  bool _lastMergeDanmaku = false;
  double _lastTrackGapRatio = -1;
  double _lastOutlineWidth = -1;
  String _lastCustomFontFamily = '';
  String _lastCustomFontFilePath = '';
  List<String> _lastBlockWords = const [];

  Uint8List? _cachedFontBytes;
  String? _cachedFontFilePath;

  Future<void> configure({
    required List<Map<String, dynamic>> danmakuList,
    required int danmakuListVersion,
    required Size size,
    required double fontSize,
    required double displayArea,
    required double scrollDurationSeconds,
    required bool allowStacking,
    required bool mergeDanmaku,
    int? maxQuantity,
    int? maxLinesPerType,
    double trackGapRatio = 0.20,
    double outlineWidth = 0.0,
    String customFontFamily = '',
    String customFontFilePath = '',
    List<String> blockWords = const [],
  }) async {
    final listIdentity = identityHashCode(danmakuList);
    final changed = listIdentity != _sourceListIdentity ||
        danmakuListVersion != _sourceListVersion ||
        _prepared == null ||
        (_lastFontSize - fontSize).abs() > 0.001 ||
        (_lastDisplayArea - displayArea).abs() > 0.0001 ||
        _lastMergeDanmaku != mergeDanmaku ||
        (_lastTrackGapRatio - trackGapRatio).abs() > 0.001 ||
        (_lastOutlineWidth - outlineWidth).abs() > 0.001 ||
        _lastCustomFontFamily != customFontFamily ||
        _lastCustomFontFilePath != customFontFilePath ||
        !listEquals(_lastBlockWords, blockWords) ||
        !_sameLayoutConfig(
          _prepared!,
          size: size,
          scrollDurationSeconds: scrollDurationSeconds,
        );

    if (!changed) {
      return;
    }

    final oldHandle = _prepared?.handle;
    if (oldHandle != null && oldHandle != BigInt.zero) {
      rust_dfm.dfmPlusDropLayout(handle: oldHandle);
    }

    final fontBytes = await _loadFontBytes(customFontFilePath);

    final rawItems = <rust_dfm.DfmPlusRawDanmakuItem>[];
    for (final raw in danmakuList) {
      final text = (raw['content'] ?? raw['c'])?.toString() ?? '';
      if (text.isEmpty) {
        continue;
      }
      final time = _resolveTime(raw);
      final typeCode = _parseType(raw['type']);
      final colorArgb = _parseColor(raw['color']);
      final isMe = raw['isMe'] == true;

      rawItems.add(
        rust_dfm.DfmPlusRawDanmakuItem(
          timeSeconds: time,
          text: text,
          typeCode: typeCode,
          colorArgb: colorArgb,
          isMe: isMe,
        ),
      );
    }

    await ensureRustInitialized();
    _prepared = await rust_dfm.dfmPlusPrepareLayoutFull(
      rawItems: rawItems,
      width: size.width,
      height: size.height,
      fontSize: fontSize,
      displayArea: displayArea,
      scrollDurationSeconds: scrollDurationSeconds,
      allowStacking: allowStacking,
      mergeDanmaku: mergeDanmaku,
      maxQuantity: maxQuantity,
      maxLinesPerType: maxLinesPerType,
      trackGapRatio: trackGapRatio,
      outlineWidth: outlineWidth,
      customFontBytes: fontBytes,
      blockWords: blockWords,
    );
    _sourceListIdentity = listIdentity;
    _sourceListVersion = danmakuListVersion;
    _lastFontSize = fontSize;
    _lastDisplayArea = displayArea;
    _lastMergeDanmaku = mergeDanmaku;
    _lastTrackGapRatio = trackGapRatio;
    _lastOutlineWidth = outlineWidth;
    _lastCustomFontFamily = customFontFamily;
    _lastCustomFontFilePath = customFontFilePath;
    _lastBlockWords = List.unmodifiable(blockWords);
  }

  Future<List<PositionedDanmakuItem>> layout(double currentTimeSeconds) async {
    final prepared = _prepared;
    if (prepared == null) {
      return const [];
    }

    final frame = await rust_dfm.dfmPlusLayoutFrame(
      request: rust_dfm.DfmPlusFrameRequest(
        layoutHandle: prepared.handle,
        currentTimeSeconds: currentTimeSeconds,
      ),
    );

    return frame.items
        .map(
          (fi) {
            final pi = prepared.items[fi.itemIndex];
            return PositionedDanmakuItem(
            content: DanmakuContentItem(
              pi.text,
              type: _toItemType(pi.typeCode),
              color: Color(pi.colorArgb),
              isMe: pi.isMe,
              fontSizeMultiplier: pi.fontSizeMultiplier,
              countText: pi.countText,
            ),
            x: fi.x,
            y: fi.y,
            offstageX: fi.offstageX,
            time: pi.timeSeconds,
          );
          },
        )
        .toList(growable: false);
  }

  void dispose() {
    final handle = _prepared?.handle;
    if (handle != null && handle != BigInt.zero) {
      rust_dfm.dfmPlusDropLayout(handle: handle);
    }
    _prepared = null;
  }

  bool _sameLayoutConfig(
    rust_dfm.DfmPlusPreparedLayout prepared, {
    required Size size,
    required double scrollDurationSeconds,
  }) {
    return (prepared.width - size.width).abs() < 0.5 &&
        (prepared.height - size.height).abs() < 0.5 &&
        (prepared.scrollDurationSeconds - scrollDurationSeconds).abs() < 0.001;
  }

  /// Load custom font file bytes. Cached to avoid re-reading on every configure() call.
  Future<Uint8List?> _loadFontBytes(String fontFilePath) async {
    if (fontFilePath.isEmpty) {
      return null;
    }
    if (_cachedFontFilePath == fontFilePath && _cachedFontBytes != null) {
      return _cachedFontBytes;
    }
    try {
      final file = io.File(fontFilePath);
      if (await file.exists()) {
        _cachedFontBytes = await file.readAsBytes();
        _cachedFontFilePath = fontFilePath;
        return _cachedFontBytes;
      }
    } catch (_) {
      // Fall through to no custom font
    }
    _cachedFontBytes = null;
    _cachedFontFilePath = fontFilePath;
    return null;
  }

  double _resolveTime(Map<String, dynamic> raw) {
    final value = raw['time'] ?? raw['t'];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  int _parseType(dynamic raw) {
    if (raw is num) {
      final code = raw.toInt();
      return code;
    }
    final value = raw?.toString().toLowerCase() ?? 'scroll';
    switch (value) {
      case 'top':
        return 5;
      case 'bottom':
        return 4;
      default:
        return 1;
    }
  }

  int _parseColor(dynamic raw) {
    if (raw is int) {
      final value = raw & 0x00FFFFFF;
      return (0xFF000000 | value).toSigned(32);
    }

    final value = raw?.toString() ?? '';
    if (value.startsWith('rgb')) {
      final parts = value
          .replaceAll('rgb(', '')
          .replaceAll(')', '')
          .split(',')
          .map((s) => int.tryParse(s.trim()) ?? 255)
          .toList();
      if (parts.length >= 3) {
        return Color.fromARGB(255, parts[0], parts[1], parts[2]).toARGB32();
      }
    }

    if (value.startsWith('#')) {
      final hex = value.substring(1);
      final parsed = int.tryParse(hex, radix: 16);
      if (parsed != null) {
        return (0xFF000000 | parsed).toSigned(32);
      }
    }

    if (value.startsWith('0x')) {
      final parsed = int.tryParse(value.substring(2), radix: 16);
      if (parsed != null) {
        return (0xFF000000 | parsed).toSigned(32);
      }
    }

    return Colors.white.toARGB32();
  }

  DanmakuItemType _toItemType(int typeCode) {
    switch (typeCode) {
      case 5:
        return DanmakuItemType.top;
      case 4:
        return DanmakuItemType.bottom;
      default:
        return DanmakuItemType.scroll;
    }
  }
}
