import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

class NipaPlayNextCanvasPainter extends CustomPainter {
  NipaPlayNextCanvasPainter({
    required this.items,
    required this.fontSize,
  });

  final List<PositionedDanmakuItem> items;
  final double fontSize;

  static const int _cacheLimit = 2000;
  static final Map<_TextCacheKey, TextPainter> _fillCache = {};
  static final Map<_TextCacheKey, TextPainter> _strokeCache = {};

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty) return;

    for (final item in items) {
      final content = item.content;
      final adjustedFontSize = fontSize * content.fontSizeMultiplier;
      final strokeColor = _getStrokeColor(content.color);

      final fillPainter = _getPainter(
        content: content,
        fontSize: adjustedFontSize,
        color: content.color,
        isStroke: false,
      );
      final strokePainter = _getPainter(
        content: content,
        fontSize: adjustedFontSize,
        color: strokeColor,
        isStroke: true,
      );

      final baseOffset = Offset(item.x, item.y);
      strokePainter.paint(canvas, baseOffset);
      fillPainter.paint(canvas, baseOffset);
    }
  }

  TextPainter _getPainter({
    required DanmakuContentItem content,
    required double fontSize,
    required Color color,
    required bool isStroke,
  }) {
    final key = _TextCacheKey(
      text: content.text,
      countText: content.countText,
      fontSize: fontSize,
      color: color.value,
      isStroke: isStroke,
    );

    final cache = isStroke ? _strokeCache : _fillCache;
    final cached = cache[key];
    if (cached != null) return cached;

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = globals.strokeWidth * 2
      ..color = color;

    final baseStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.normal,
      color: isStroke ? null : color,
      foreground: isStroke ? strokePaint : null,
    );

    final span = _buildSpan(content, baseStyle, isStroke);

    final painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      locale: const Locale('zh-Hans', 'zh'),
    )..layout(minWidth: 0, maxWidth: double.infinity);

    if (cache.length > _cacheLimit) {
      cache.clear();
    }
    cache[key] = painter;
    return painter;
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

  Color _getStrokeColor(Color textColor) {
    final luminance =
        (0.299 * textColor.red + 0.587 * textColor.green + 0.114 * textColor.blue) / 255;
    return luminance < 0.2 ? Colors.white : Colors.black;
  }

  @override
  bool shouldRepaint(covariant NipaPlayNextCanvasPainter oldDelegate) {
    return oldDelegate.items != items || oldDelegate.fontSize != fontSize;
  }
}

class _TextCacheKey {
  const _TextCacheKey({
    required this.text,
    required this.countText,
    required this.fontSize,
    required this.color,
    required this.isStroke,
  });

  final String text;
  final String? countText;
  final double fontSize;
  final int color;
  final bool isStroke;

  @override
  bool operator ==(Object other) {
    return other is _TextCacheKey &&
        other.text == text &&
        other.countText == countText &&
        other.fontSize == fontSize &&
        other.color == color &&
        other.isStroke == isStroke;
  }

  @override
  int get hashCode =>
      Object.hash(text, countText, fontSize, color, isStroke);
}
