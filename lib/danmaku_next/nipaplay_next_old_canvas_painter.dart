// ════════════════════════════════════════════════════════════════════
//  Next Old Canvas Painter — d6592232 版 TextPainter 逐条绘制
//
//  与 DanmakuAtlasPainter (Next++) 的区别：
//  - TextPainter.paint() 逐条绘制（O(glyphs)×N/帧 GPU 操作）
//  - 绝对定位 x = width - scrollSpeed * elapsed（无 displayX 增量定位）
//  - 8方向偏移重绘描边（_paintUniformOutline，非 Shadow 烘入）
//  - 无精灵图集 / toImageSync / vsync AnimationController
//  - repaint 由 playbackTimeMs ValueListenable 直接驱动
// ════════════════════════════════════════════════════════════════════

import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import 'package:nipaplay/utils/danmaku/style.dart';

import 'nipaplay_next_old_engine.dart';

/// Next Old 引擎画笔 — d6592232 版逐条 TextPainter 绘制。
/// 无 vsync、无图集、无增量定位，playbackTimeMs 驱动重绘。
class NipaPlayNextOldCanvasPainter extends CustomPainter {
  NipaPlayNextOldCanvasPainter({
    required this.engine,
    required this.playbackTimeMs,
    required this.timeOffsetSeconds,
    required this.fontSize,
    required this.fontFamily,
    required this.fontFamilyFallback,
    required this.locale,
    required this.outlineStyle,
    required this.shadowStyle,
  }) : super(repaint: playbackTimeMs);

  final NipaPlayNextOldEngine engine;
  final ValueListenable<double> playbackTimeMs;
  final double timeOffsetSeconds;
  final double fontSize;
  final String? fontFamily;
  final List<String>? fontFamilyFallback;
  final Locale? locale;
  final DanmakuOutlineStyle outlineStyle;
  final DanmakuShadowStyle shadowStyle;
  late final int _layoutVersion = engine.layoutVersion;
  late final String? _fontFamilyFallbackKey =
      fontFamilyFallback?.join('\u0000');

  static const int _cacheLimit = 2000;
  static const int _emojiCacheLimit = 4000;
  static final LinkedHashMap<_TextCacheKey, TextPainter> _fillCache =
      LinkedHashMap<_TextCacheKey, TextPainter>();
  static final LinkedHashMap<_TextCacheKey, TextPainter> _strokeCache =
      LinkedHashMap<_TextCacheKey, TextPainter>();
  static final LinkedHashMap<_TextCacheKey, TextPainter> _shadowCache =
      LinkedHashMap<_TextCacheKey, TextPainter>();
  static final LinkedHashMap<String, bool> _emojiCache =
      LinkedHashMap<String, bool>();
  static final Paint _selfSendPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    final items =
        engine.layout(playbackTimeMs.value / 1000.0 + timeOffsetSeconds);
    if (items.isEmpty) return;

    for (final item in items) {
      final content = item.content;
      final adjustedFontSize = fontSize * content.fontSizeMultiplier;
      final fillPainter = _getFillPainter(
        content: content,
        fontSize: adjustedFontSize,
        color: content.color,
      );

      final baseOffset = Offset(item.x, item.y);
      if (shadowStyle != DanmakuShadowStyle.none) {
        final shadowConfig = _resolveShadowStyle(adjustedFontSize);
        if (shadowConfig != null) {
          final shadowPainter = _getShadowPainter(
            content: content,
            fontSize: adjustedFontSize,
            color: Color.fromRGBO(0, 0, 0, shadowConfig.opacity),
            blurSigma: shadowConfig.blurSigma,
          );
          shadowPainter.paint(canvas, baseOffset + shadowConfig.offset);
        }
      }

      switch (outlineStyle) {
        case DanmakuOutlineStyle.none:
          break;
        case DanmakuOutlineStyle.stroke:
          final containsEmoji = _containsEmojiCached(content.text);
          final strokeColor = _getStrokeColor(
            textColor: content.color,
          );
          final strokeWidth = _resolveStrokeWidth(adjustedFontSize);
          if (containsEmoji) {
            _paintEmojiOutline(
              canvas: canvas,
              fillPainter: fillPainter,
              baseOffset: baseOffset,
              radius: strokeWidth,
              outlineColor: strokeColor,
            );
          } else {
            final strokePainter = _getStrokePainter(
              content: content,
              fontSize: adjustedFontSize,
              color: strokeColor,
              strokeWidth: strokeWidth,
            );
            strokePainter.paint(canvas, baseOffset);
          }
          break;
        case DanmakuOutlineStyle.uniform:
          final containsEmoji = _containsEmojiCached(content.text);
          final strokeColor = _getStrokeColor(
            textColor: content.color,
          );
          final uniformOutlineRadius =
              _resolveUniformOutlineRadius(adjustedFontSize);
          if (containsEmoji) {
            _paintEmojiOutline(
              canvas: canvas,
              fillPainter: fillPainter,
              baseOffset: baseOffset,
              radius: uniformOutlineRadius,
              outlineColor: strokeColor,
            );
          } else {
            final outlinePainter = _getFillPainter(
              content: content,
              fontSize: adjustedFontSize,
              color: strokeColor,
            );
            _paintUniformOutline(
              canvas: canvas,
              painter: outlinePainter,
              baseOffset: baseOffset,
              radius: uniformOutlineRadius,
            );
          }
          break;
      }

      if (content.isMe) {
        final rect = Rect.fromLTWH(
          baseOffset.dx - 2,
          baseOffset.dy - 2,
          fillPainter.width + 4,
          fillPainter.height + 4,
        );
        canvas.drawRect(rect, _selfSendPaint);
      }
      fillPainter.paint(canvas, baseOffset);
    }
  }

  TextPainter _getFillPainter({
    required DanmakuContentItem content,
    required double fontSize,
    required Color color,
  }) {
    return _getPainter(
      content: content,
      fontSize: fontSize,
      color: color,
      variant: _PainterVariant.fill,
    );
  }

  TextPainter _getStrokePainter({
    required DanmakuContentItem content,
    required double fontSize,
    required Color color,
    required double strokeWidth,
  }) {
    return _getPainter(
      content: content,
      fontSize: fontSize,
      color: color,
      variant: _PainterVariant.stroke,
      effectValue: strokeWidth,
    );
  }

  TextPainter _getShadowPainter({
    required DanmakuContentItem content,
    required double fontSize,
    required Color color,
    required double blurSigma,
  }) {
    return _getPainter(
      content: content,
      fontSize: fontSize,
      color: color,
      variant: _PainterVariant.shadow,
      effectValue: blurSigma,
    );
  }

  TextPainter _getPainter({
    required DanmakuContentItem content,
    required double fontSize,
    required Color color,
    required _PainterVariant variant,
    double effectValue = 0.0,
  }) {
    final key = _TextCacheKey(
      text: content.text,
      countText: content.countText,
      fontSize: fontSize,
      color: color.toARGB32(),
      variant: variant,
      effectValue: effectValue,
      fontFamily: fontFamily,
      fontFamilyFallbackKey: _fontFamilyFallbackKey,
      locale: locale,
    );

    final cache = switch (variant) {
      _PainterVariant.fill => _fillCache,
      _PainterVariant.stroke => _strokeCache,
      _PainterVariant.shadow => _shadowCache,
    };
    final cached = cache[key];
    if (cached != null) {
      cache.remove(key);
      cache[key] = cached;
      return cached;
    }

    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;

    if (variant == _PainterVariant.stroke) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = effectValue
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
    } else {
      paint.style = PaintingStyle.fill;
      if (variant == _PainterVariant.shadow && effectValue > 0) {
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, effectValue);
      }
    }

    final bool isFill = variant == _PainterVariant.fill;

    final baseStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.normal,
      color: isFill ? color : null,
      foreground: isFill ? null : paint,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );

    final span = _buildSpan(content, baseStyle, !isFill);

    final painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      locale: locale,
    )..layout(minWidth: 0, maxWidth: double.infinity);

    _insertWithBound(cache, key, painter, _cacheLimit);
    return painter;
  }

  static void _insertWithBound<K, V>(
    LinkedHashMap<K, V> cache,
    K key,
    V value,
    int limit,
  ) {
    if (cache.length >= limit && cache.isNotEmpty) {
      cache.remove(cache.keys.first);
    }
    cache[key] = value;
  }

  _ShadowConfig? _resolveShadowStyle(double targetFontSize) {
    final double unit = _resolveUniformOutlineRadius(targetFontSize);
    switch (shadowStyle) {
      case DanmakuShadowStyle.none:
        return null;
      case DanmakuShadowStyle.soft:
        return _ShadowConfig(
          offset: Offset(unit * 0.8, unit * 0.8),
          blurSigma: unit * 0.9,
          opacity: 0.34,
        );
      case DanmakuShadowStyle.medium:
        return _ShadowConfig(
          offset: Offset(unit, unit),
          blurSigma: unit * 1.2,
          opacity: 0.44,
        );
      case DanmakuShadowStyle.strong:
        return _ShadowConfig(
          offset: Offset(unit * 1.2, unit * 1.2),
          blurSigma: unit * 1.5,
          opacity: 0.55,
        );
    }
  }

  double _resolveStrokeWidth(double targetFontSize) {
    final width = targetFontSize * 0.06;
    return width.clamp(1.0, 2.6);
  }

  double _resolveUniformOutlineRadius(double targetFontSize) {
    final radius = targetFontSize * 0.045;
    return math.max(0.8, radius.clamp(0.8, 2.0));
  }

  TextSpan _buildSpan(
    DanmakuContentItem content,
    TextStyle baseStyle,
    bool isStroke,
  ) {
    final countText = content.countText;
    if (countText == null || countText.isEmpty) {
      return TextSpan(
        text: content.text,
        style: baseStyle,
      );
    }

    final countStyle = baseStyle.copyWith(
      fontSize: 25.0,
      fontWeight: FontWeight.bold,
      color: isStroke ? null : Colors.white,
    );

    return TextSpan(
      children: [
        TextSpan(text: content.text, style: baseStyle),
        TextSpan(text: countText, style: countStyle),
      ],
    );
  }

  Color _getStrokeColor({
    required Color textColor,
  }) {
    if (_isPureBlack(textColor)) return Colors.white;
    return Colors.black;
  }

  bool _isPureBlack(Color color) {
    const double epsilon = 1e-6;
    return color.r <= epsilon && color.g <= epsilon && color.b <= epsilon;
  }

  bool _containsEmojiCached(String text) {
    final cached = _emojiCache[text];
    if (cached != null) {
      _emojiCache.remove(text);
      _emojiCache[text] = cached;
      return cached;
    }
    final result = _containsEmoji(text);
    _insertWithBound(_emojiCache, text, result, _emojiCacheLimit);
    return result;
  }

  bool _containsEmoji(String text) {
    for (final rune in text.runes) {
      if (_isEmojiRune(rune)) return true;
    }
    return false;
  }

  bool _isEmojiRune(int rune) {
    return (rune >= 0x1F000 && rune <= 0x1FAFF) ||
        (rune >= 0x2600 && rune <= 0x27BF) ||
        (rune >= 0xFE00 && rune <= 0xFE0F) ||
        rune == 0x200D ||
        rune == 0x20E3;
  }

  void _paintEmojiOutline({
    required Canvas canvas,
    required TextPainter fillPainter,
    required Offset baseOffset,
    required double radius,
    required Color outlineColor,
  }) {
    final expanded = (radius + 2.0).clamp(2.0, 6.0);
    final baseBounds = Rect.fromLTWH(
      baseOffset.dx - expanded,
      baseOffset.dy - expanded,
      fillPainter.width + expanded * 2,
      fillPainter.height + expanded * 2,
    );
    final filterPaint = Paint()
      ..colorFilter = ColorFilter.mode(outlineColor, BlendMode.srcIn);

    _paintEmojiOutlineDirection(
      canvas: canvas,
      fillPainter: fillPainter,
      baseOffset: baseOffset,
      baseBounds: baseBounds,
      filterPaint: filterPaint,
      dx: -radius,
      dy: 0,
    );
    _paintEmojiOutlineDirection(
      canvas: canvas,
      fillPainter: fillPainter,
      baseOffset: baseOffset,
      baseBounds: baseBounds,
      filterPaint: filterPaint,
      dx: radius,
      dy: 0,
    );
    _paintEmojiOutlineDirection(
      canvas: canvas,
      fillPainter: fillPainter,
      baseOffset: baseOffset,
      baseBounds: baseBounds,
      filterPaint: filterPaint,
      dx: 0,
      dy: -radius,
    );
    _paintEmojiOutlineDirection(
      canvas: canvas,
      fillPainter: fillPainter,
      baseOffset: baseOffset,
      baseBounds: baseBounds,
      filterPaint: filterPaint,
      dx: 0,
      dy: radius,
    );
    _paintEmojiOutlineDirection(
      canvas: canvas,
      fillPainter: fillPainter,
      baseOffset: baseOffset,
      baseBounds: baseBounds,
      filterPaint: filterPaint,
      dx: -radius,
      dy: -radius,
    );
    _paintEmojiOutlineDirection(
      canvas: canvas,
      fillPainter: fillPainter,
      baseOffset: baseOffset,
      baseBounds: baseBounds,
      filterPaint: filterPaint,
      dx: radius,
      dy: -radius,
    );
    _paintEmojiOutlineDirection(
      canvas: canvas,
      fillPainter: fillPainter,
      baseOffset: baseOffset,
      baseBounds: baseBounds,
      filterPaint: filterPaint,
      dx: -radius,
      dy: radius,
    );
    _paintEmojiOutlineDirection(
      canvas: canvas,
      fillPainter: fillPainter,
      baseOffset: baseOffset,
      baseBounds: baseBounds,
      filterPaint: filterPaint,
      dx: radius,
      dy: radius,
    );
  }

  void _paintUniformOutline({
    required Canvas canvas,
    required TextPainter painter,
    required Offset baseOffset,
    required double radius,
  }) {
    painter.paint(canvas, Offset(baseOffset.dx - radius, baseOffset.dy));
    painter.paint(canvas, Offset(baseOffset.dx + radius, baseOffset.dy));
    painter.paint(canvas, Offset(baseOffset.dx, baseOffset.dy - radius));
    painter.paint(canvas, Offset(baseOffset.dx, baseOffset.dy + radius));
    painter.paint(
      canvas,
      Offset(baseOffset.dx - radius, baseOffset.dy - radius),
    );
    painter.paint(
      canvas,
      Offset(baseOffset.dx + radius, baseOffset.dy - radius),
    );
    painter.paint(
      canvas,
      Offset(baseOffset.dx - radius, baseOffset.dy + radius),
    );
    painter.paint(
      canvas,
      Offset(baseOffset.dx + radius, baseOffset.dy + radius),
    );
  }

  void _paintEmojiOutlineDirection({
    required Canvas canvas,
    required TextPainter fillPainter,
    required Offset baseOffset,
    required Rect baseBounds,
    required Paint filterPaint,
    required double dx,
    required double dy,
  }) {
    final shift = Offset(dx, dy);
    canvas.saveLayer(baseBounds.shift(shift), filterPaint);
    fillPainter.paint(canvas, baseOffset + shift);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant NipaPlayNextOldCanvasPainter oldDelegate) {
    return oldDelegate._layoutVersion != _layoutVersion ||
        oldDelegate.engine != engine ||
        oldDelegate.timeOffsetSeconds != timeOffsetSeconds ||
        oldDelegate.fontSize != fontSize ||
        oldDelegate.fontFamily != fontFamily ||
        oldDelegate.outlineStyle != outlineStyle ||
        oldDelegate.shadowStyle != shadowStyle ||
        oldDelegate.locale != locale ||
        !_listEquals(oldDelegate.fontFamilyFallback, fontFamilyFallback);
  }
}

class _ShadowConfig {
  const _ShadowConfig({
    required this.offset,
    required this.blurSigma,
    required this.opacity,
  });

  final Offset offset;
  final double blurSigma;
  final double opacity;
}

enum _PainterVariant {
  fill,
  stroke,
  shadow,
}

bool _listEquals(List<String>? a, List<String>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _TextCacheKey {
  const _TextCacheKey({
    required this.text,
    required this.countText,
    required this.fontSize,
    required this.color,
    required this.variant,
    required this.effectValue,
    required this.fontFamily,
    required this.fontFamilyFallbackKey,
    required this.locale,
  });

  final String text;
  final String? countText;
  final double fontSize;
  final int color;
  final _PainterVariant variant;
  final double effectValue;
  final String? fontFamily;
  final String? fontFamilyFallbackKey;
  final Locale? locale;

  @override
  bool operator ==(Object other) {
    return other is _TextCacheKey &&
        other.text == text &&
        other.countText == countText &&
        other.fontSize == fontSize &&
        other.color == color &&
        other.variant == variant &&
        other.effectValue == effectValue &&
        other.fontFamily == fontFamily &&
        other.fontFamilyFallbackKey == fontFamilyFallbackKey &&
        other.locale == locale;
  }

  @override
  int get hashCode => Object.hash(
        text,
        countText,
        fontSize,
        color,
        variant,
        effectValue,
        fontFamily,
        fontFamilyFallbackKey,
        locale,
      );
}
