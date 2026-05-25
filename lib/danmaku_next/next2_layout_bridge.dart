import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/src/rust/api/next2.dart' as rust_next2;
import 'package:nipaplay/src/rust/rust_init.dart';

class Next2LayoutBridge {
  rust_next2.RustNext2PreparedLayout? _prepared;
  int _sourceListIdentity = 0;
  int _sourceListVersion = -1;
  double _lastFontSize = -1;
  double _lastDisplayArea = -1;
  bool _lastAllowStacking = false;
  bool _lastMergeDanmaku = false;
  String _lastCustomFontFamily = '';
  String _lastCustomFontFilePath = '';

  Future<void> configure({
    required List<Map<String, dynamic>> danmakuList,
    required int danmakuListVersion,
    required Size size,
    required double fontSize,
    required double displayArea,
    required double scrollDurationSeconds,
    required bool allowStacking,
    required bool mergeDanmaku,
    required String customFontFamily,
    required String customFontFilePath,
  }) async {
    final listIdentity = identityHashCode(danmakuList);
    final changed = listIdentity != _sourceListIdentity ||
        danmakuListVersion != _sourceListVersion ||
        _prepared == null ||
        (_lastFontSize - fontSize).abs() > 0.001 ||
        (_lastDisplayArea - displayArea).abs() > 0.0001 ||
        _lastAllowStacking != allowStacking ||
        _lastMergeDanmaku != mergeDanmaku ||
        _lastCustomFontFamily != customFontFamily ||
        _lastCustomFontFilePath != customFontFilePath ||
        !_sameLayoutConfig(
          _prepared!,
          size: size,
          scrollDurationSeconds: scrollDurationSeconds,
        );

    if (!changed) {
      return;
    }

    final items = <rust_next2.RustNext2DanmakuItem>[];
    for (final raw in danmakuList) {
      final text = (raw['content'] ?? raw['c'])?.toString() ?? '';
      if (text.isEmpty) {
        continue;
      }
      final time = _resolveTime(raw);
      final typeCode = _parseType(raw['type']);
      final colorArgb = _parseColor(raw['color']);
      final isMe = raw['isMe'] == true;

      items.add(
        rust_next2.RustNext2DanmakuItem(
          timeSeconds: time,
          text: text,
          typeCode: typeCode,
          colorArgb: colorArgb,
          isMe: isMe,
        ),
      );
    }

    await ensureRustInitialized();
    _prepared = await rust_next2.next2PrepareLayout(
      request: rust_next2.RustNext2PrepareRequest(
        items: items,
        width: size.width,
        height: size.height,
        fontSize: fontSize,
        displayArea: displayArea,
        scrollDurationSeconds: scrollDurationSeconds,
        allowStacking: allowStacking,
        mergeDanmaku: mergeDanmaku,
        customFontFamily: customFontFamily,
        customFontFilePath: customFontFilePath,
      ),
    );
    _sourceListIdentity = listIdentity;
    _sourceListVersion = danmakuListVersion;
    _lastFontSize = fontSize;
    _lastDisplayArea = displayArea;
    _lastAllowStacking = allowStacking;
    _lastMergeDanmaku = mergeDanmaku;
    _lastCustomFontFamily = customFontFamily;
    _lastCustomFontFilePath = customFontFilePath;
  }

  Future<List<PositionedDanmakuItem>> layout(double currentTimeSeconds) async {
    final prepared = _prepared;
    if (prepared == null) {
      return const [];
    }

    final frame = await rust_next2.next2LayoutFrame(
      request: rust_next2.RustNext2FrameRequest(
        layout: prepared,
        currentTimeSeconds: currentTimeSeconds,
      ),
    );

    return frame.items
        .map(
          (item) => PositionedDanmakuItem(
            content: DanmakuContentItem(
              item.text,
              type: _toItemType(item.typeCode),
              color: Color(item.colorArgb),
              isMe: item.isMe,
              fontSizeMultiplier: item.fontSizeMultiplier,
              countText: item.countText,
            ),
            x: item.x,
            y: item.y,
            offstageX: item.offstageX,
            time: item.timeSeconds,
          ),
        )
        .toList(growable: false);
  }

  bool _sameLayoutConfig(
    rust_next2.RustNext2PreparedLayout prepared, {
    required Size size,
    required double scrollDurationSeconds,
  }) {
    return (prepared.width - size.width).abs() < 0.5 &&
        (prepared.height - size.height).abs() < 0.5 &&
        (prepared.scrollDurationSeconds - scrollDurationSeconds).abs() < 0.001;
  }

  double _resolveTime(Map<String, dynamic> raw) {
    final value = raw['time'] ?? raw['t'];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  int _parseType(dynamic raw) {
    if (raw is num) {
      final code = raw.toInt();
      if (code == 5) return 1;
      if (code == 4) return 2;
      return 0;
    }
    final value = raw?.toString().toLowerCase() ?? 'scroll';
    switch (value) {
      case 'top':
        return 1;
      case 'bottom':
        return 2;
      default:
        return 0;
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
      case 1:
        return DanmakuItemType.top;
      case 2:
        return DanmakuItemType.bottom;
      default:
        return DanmakuItemType.scroll;
    }
  }
}
