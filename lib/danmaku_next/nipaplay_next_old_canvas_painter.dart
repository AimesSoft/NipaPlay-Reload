// ════════════════════════════════════════════════════════════════════
//  Next Old Canvas Painter — c4ceacbd 版 TextPainter 逐条绘制
//
//  与 DanmakuAtlasPainter 的区别：
//  - TextPainter.paint() 逐条绘制（O(glyphs)×N/帧 GPU 操作）
//  - 绝对定位 x = width - scrollSpeed * elapsed（无 displayX 增量定位）
//  - 8方向偏移重绘描边（_paintUniformOutline，非 Shadow 烘入）
//  - 无精灵图集 / toImageSync / vsync AnimationController
//  - repaint 由外部 ValueNotifier（playbackTimeMs 驱动）控制
// ════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/utils/video_player_state.dart';

import 'nipaplay_next_old_engine.dart';

/// Next Old 引擎画笔 — c4ceacbd 版逐条 TextPainter 绘制。
/// 无 vsync、无图集、无增量定位，playbackTimeMs 驱动重绘。
class NipaPlayNextOldCanvasPainter extends CustomPainter {
  NipaPlayNextOldCanvasPainter({
    required this.repaintNotifier,
    required this.engine,
    required this.items,
    required this.fontSize,
    required this.fontFamily,
    required this.fontFamilyFallback,
    required this.locale,
    required this.outlineStyle,
    required this.shadowStyle,
  }) : super(repaint: repaintNotifier);

  /// playbackTimeMs 变化时触发重绘
  final ValueNotifier<int> repaintNotifier;

  final NipaPlayNextOldEngine engine;
  final List<PositionedDanmakuItem> items;
  final double fontSize;
  final String? fontFamily;
  final List<String>? fontFamilyFallback;
  final Locale? locale;
  final DanmakuOutlineStyle outlineStyle;
  final DanmakuShadowStyle shadowStyle;

  late final int _layoutVersion = engine.layoutVersion;

  /// uniform 描边8方向偏移（与 c4ceacbd 旧版 _paintUniformOutline 一致）
  static const List<(double, double)> _uniformOutlineDirs = [
    (-1.0, 0.0),
    (1.0, 0.0),
    (0.0, -1.0),
    (0.0, 1.0),
    (-1.0, -1.0),
    (1.0, -1.0),
    (-1.0, 1.0),
    (1.0, 1.0),
  ];

  /// 自发弹幕边框
  static final Paint _selfSendPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty) return;

    for (final item in items) {
      final content = item.content;
      final drawX = item.x;
      final drawY = item.y;

      // ── 视口剔除：跳过完全不可见的弹幕 ──
      final itemWidth = item.width;
      if (itemWidth > 0.0) {
        if (drawX + itemWidth < 0.0 || drawX > size.width) {
          continue;
        }
      }

      final adjFontSize = fontSize * content.fontSizeMultiplier;
      final strokeColor = _getStrokeColor(textColor: content.color);

      // ── 构建 TextPainter ──
      final textStyle = TextStyle(
        fontSize: adjFontSize,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        color: content.color,
        locale: locale,
      );

      final strokeTextStyle = TextStyle(
        fontSize: adjFontSize,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        color: strokeColor,
        locale: locale,
      );

      // ── 描边绘制 ──
      if (outlineStyle == DanmakuOutlineStyle.uniform) {
        // c4ceacbd 版 uniform 描边：8方向偏移重绘
        final radius = _resolveUniformOutlineRadius(adjFontSize);
        _paintUniformOutline(
          canvas, content.text, drawX, drawY,
          strokeTextStyle, radius,
        );
      } else if (outlineStyle == DanmakuOutlineStyle.stroke) {
        // thin stroke 描边：-1px stroke + fill
        final strokeWidth = _resolveStrokeWidth(adjFontSize);
        _paintStrokeOutline(
          canvas, content.text, drawX, drawY,
          strokeTextStyle, textStyle, strokeWidth,
        );
      }

      // ── 阴影绘制（描边之后、填充之前） ──
      if (shadowStyle != DanmakuShadowStyle.none) {
        final shadowParams = _resolveShadowParams(adjFontSize);
        if (shadowParams != null) {
          _paintShadow(
            canvas, content.text, drawX, drawY,
            textStyle, shadowParams,
          );
        }
      }

      // ── 填充绘制 ──
      final fillTp = TextPainter(
        text: TextSpan(text: content.text, style: textStyle),
        maxLines: 1,
        textDirection: TextDirection.ltr,
        locale: locale,
      )..layout(minWidth: 0, maxWidth: double.infinity);
      fillTp.paint(canvas, Offset(drawX, drawY));

      // 自发弹幕边框
      if (content.isMe) {
        canvas.drawRect(
          Rect.fromLTWH(drawX - 2, drawY - 2, fillTp.width + 4, fillTp.height + 4),
          _selfSendPaint,
        );
      }
    }
  }

  /// c4ceacbd 版 uniform 描边：8方向偏移重绘
  /// 在8个方向各偏移 radius 像素画一次描边色文本，最后画填充色文本。
  void _paintUniformOutline(
    Canvas canvas,
    String text,
    double x,
    double y,
    TextStyle strokeStyle,
    double radius,
  ) {
    for (final (dx, dy) in _uniformOutlineDirs) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: strokeStyle),
        maxLines: 1,
        textDirection: TextDirection.ltr,
        locale: locale,
      )..layout(minWidth: 0, maxWidth: double.infinity);
      tp.paint(canvas, Offset(x + dx * radius, y + dy * radius));
    }
  }

  /// thin stroke 描边：先画 stroke 文本（比 fill 稍大），再画 fill 文本
  void _paintStrokeOutline(
    Canvas canvas,
    String text,
    double x,
    double y,
    TextStyle strokeStyle,
    TextStyle fillStyle,
    double strokeWidth,
  ) {
    // 使用 Paint stroke 模拟描边：在上下左右各偏移 strokeWidth/2 画4次
    final offsets = [
      Offset(-strokeWidth, 0),
      Offset(strokeWidth, 0),
      Offset(0, -strokeWidth),
      Offset(0, strokeWidth),
    ];
    for (final offset in offsets) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: strokeStyle),
        maxLines: 1,
        textDirection: TextDirection.ltr,
        locale: locale,
      )..layout(minWidth: 0, maxWidth: double.infinity);
      tp.paint(canvas, Offset(x + offset.dx, y + offset.dy));
    }
  }

  /// 阴影绘制：在偏移位置画一层半透明文本
  void _paintShadow(
    Canvas canvas,
    String text,
    double x,
    double y,
    TextStyle baseStyle,
    _OldShadowParams params,
  ) {
    final shadowStyle = baseStyle.copyWith(
      color: baseStyle.color?.withValues(alpha: params.opacity),
    );
    final tp = TextPainter(
      text: TextSpan(text: text, style: shadowStyle),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      locale: locale,
    )..layout(minWidth: 0, maxWidth: double.infinity);
    tp.paint(canvas, Offset(x + params.dx, y + params.dy));
  }

  // ════════════════════════════════════════════════════════════════
  //  样式计算
  // ════════════════════════════════════════════════════════════════

  _OldShadowParams? _resolveShadowParams(double targetFontSize) {
    final double unit = _resolveUniformOutlineRadius(targetFontSize);
    switch (shadowStyle) {
      case DanmakuShadowStyle.none:
        return null;
      case DanmakuShadowStyle.soft:
        return _OldShadowParams(
            dx: unit * 0.8, dy: unit * 0.8, opacity: 0.34);
      case DanmakuShadowStyle.medium:
        return _OldShadowParams(dx: unit, dy: unit, opacity: 0.44);
      case DanmakuShadowStyle.strong:
        return _OldShadowParams(
            dx: unit * 1.2, dy: unit * 1.2, opacity: 0.55);
    }
  }

  double _resolveStrokeWidth(double targetFontSize) {
    return (targetFontSize * 0.06).clamp(1.0, 2.6);
  }

  double _resolveUniformOutlineRadius(double targetFontSize) {
    return math.max(0.8, (targetFontSize * 0.045).clamp(0.8, 2.0));
  }

  Color _getStrokeColor({required Color textColor}) {
    if (_isPureBlack(textColor)) return Colors.white;
    return Colors.black;
  }

  bool _isPureBlack(Color color) {
    const double epsilon = 1e-6;
    return color.r <= epsilon && color.g <= epsilon && color.b <= epsilon;
  }

  @override
  bool shouldRepaint(covariant NipaPlayNextOldCanvasPainter oldDelegate) {
    return oldDelegate._layoutVersion != _layoutVersion ||
        oldDelegate.fontSize != fontSize ||
        oldDelegate.outlineStyle != outlineStyle ||
        oldDelegate.shadowStyle != shadowStyle ||
        oldDelegate.fontFamily != fontFamily ||
        oldDelegate.locale != locale ||
        !_listEquals(oldDelegate.fontFamilyFallback, fontFamilyFallback);
  }
}

class _OldShadowParams {
  const _OldShadowParams({
    required this.dx,
    required this.dy,
    required this.opacity,
  });
  final double dx;
  final double dy;
  final double opacity;
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
