import 'dart:collection';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import 'package:nipaplay/utils/video_player_state.dart';

import 'nipaplay_next_engine.dart';

/// [NEXT-DIAG] paint 日志节流
int _lastDiagPaintTimeMs = 0;

/// 高性能弹幕画师 — 采用 Canvas 引擎验证的 ui.Paragraph 直绘架构
///
/// 相比旧实现的根本性性能提升：
/// ┌──────────────────────┬──────────────────────────┬──────────────────────────┐
/// │ 环节                 │ 旧实现                   │ 新实现                   │
/// ├──────────────────────┼──────────────────────────┼──────────────────────────┤
/// │ 文本渲染对象         │ TextPainter + 9字段Key    │ ui.Paragraph + 紧凑String│
/// │ 描边(emoji)          │ 8× saveLayer(极慢)        │ 单次 thick-stroke Para   │
/// │ 描边(非emoji/uniform)│ 8× save/translate/restore│ 单次 thick-stroke Para   │
/// │ 阴影                 │ 独立 TextPainter+MaskFilter│ TextStyle.shadows 烘入   │
/// │ 坐标定位             │ save/translate/restore    │ drawParagraph(Offset)    │
/// │ 批量绘制             │ 无                       │ PictureRecorder(>阈值)   │
/// └──────────────────────┴──────────────────────────┴──────────────────────────┘
///
/// 每弹幕每帧 draw 调用数：旧 1~10次 → 新 1~2次
/// emoji 弹幕性能提升：约 50x（消除 8× saveLayer GPU 纹理分配）
/// uniform 描边弹幕性能提升：约 8x（8次文本绘制→1次）
class NipaPlayNextCanvasPainter extends CustomPainter {
  NipaPlayNextCanvasPainter({
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

  final NipaPlayNextEngine engine;
  final ValueListenable<double> playbackTimeMs;
  final double timeOffsetSeconds;
  final double fontSize;
  final String? fontFamily;
  final List<String>? fontFamilyFallback;
  final Locale? locale;
  final DanmakuOutlineStyle outlineStyle;
  final DanmakuShadowStyle shadowStyle;
  late final int _layoutVersion = engine.layoutVersion;

  /// fontFamilyFallback 紧凑键（构造时计算一次）
  late final String _ffbKey = fontFamilyFallback?.join('\u0000') ?? '';

  /// Paragraph 全局缓存（fill / stroke / fill+shadow 共用）
  static final LinkedHashMap<String, ui.Paragraph> _pCache =
      LinkedHashMap<String, ui.Paragraph>();
  static const int _pCacheLimit = 6000;

  /// 自发弹幕边框
  static final Paint _selfSendPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.white;

  /// PictureRecorder 批量录制阈值（与 Canvas 引擎一致）
  static const int _batchThreshold = 10;

  // ════════════════════════════════════════════════════════════════
  //  主绘制循环 — 零 saveLayer，零 save/translate/restore
  // ════════════════════════════════════════════════════════════════

  @override
  void paint(Canvas canvas, Size size) {
    final diagPaintSw = kDebugMode ? Stopwatch() : null;
    diagPaintSw?.start();

    final items =
        engine.layout(playbackTimeMs.value / 1000.0 + timeOffsetSeconds);
    if (items.isEmpty) {
      diagPaintSw?.stop();
      return;
    }

    // 弹幕数量超过阈值时使用 PictureRecorder 批量录制
    final bool useBatch = items.length > _batchThreshold;
    final ui.PictureRecorder? recorder =
        useBatch ? ui.PictureRecorder() : null;
    final Canvas dc = recorder != null ? Canvas(recorder) : canvas;

    // 预计算阴影参数（所有弹幕共享，只算一次）
    final shadowParams = _resolveShadowParams(fontSize);
    final hasOutline = outlineStyle != DanmakuOutlineStyle.none;

    for (final item in items) {
      final content = item.content;
      final adjFontSize = fontSize * content.fontSizeMultiplier;
      final itemStrokeColor = _getStrokeColor(textColor: content.color);
      final int colorVal = content.color.toARGB32();
      final int strokeColorVal = itemStrokeColor.toARGB32();

      // ── 描边宽度（由 outlineStyle 决定）──
      final double strokeWidth;
      switch (outlineStyle) {
        case DanmakuOutlineStyle.stroke:
          strokeWidth = _resolveStrokeWidth(adjFontSize);
        case DanmakuOutlineStyle.uniform:
          strokeWidth = _resolveUniformStrokeWidth(adjFontSize);
        case DanmakuOutlineStyle.none:
          strokeWidth = 0.0;
      }

      // ── 获取或构建 Paragraph ──
      // 有描边时：阴影烘入描边 Paragraph（阴影→描边→填充，2次 drawParagraph）
      // 无描边有阴影时：阴影烘入填充 Paragraph（1次 drawParagraph）
      // 无描边无阴影时：纯填充 Paragraph（1次 drawParagraph）
      final ui.Paragraph fillP;
      final ui.Paragraph? strokeP;

      if (hasOutline) {
        final sKey = _key(content, adjFontSize, strokeColorVal,
            's${strokeWidth.toStringAsFixed(1)}');
        strokeP = _getOrBuild(sKey, () => _buildStrokeParagraph(
              content, adjFontSize, itemStrokeColor, strokeWidth, shadowParams,
            ));

        final fKey = _key(content, adjFontSize, colorVal, 'f');
        fillP = _getOrBuild(fKey,
            () => _buildFillParagraph(content, adjFontSize, content.color));
      } else if (shadowParams != null) {
        final fsKey = _key(content, adjFontSize, colorVal, 'fs');
        fillP = _getOrBuild(fsKey, () => _buildFillWithShadowParagraph(
              content, adjFontSize, content.color, shadowParams,
            ));
        strokeP = null;
      } else {
        final fKey = _key(content, adjFontSize, colorVal, 'f');
        fillP = _getOrBuild(fKey,
            () => _buildFillParagraph(content, adjFontSize, content.color));
        strokeP = null;
      }

      final dx = item.x;
      final dy = item.y;
      final offset = Offset(dx, dy);

      // ── 绘制：描边(含阴影) → 自发标识 → 填充 ──
      if (strokeP != null) {
        dc.drawParagraph(strokeP, offset);
      }

      if (content.isMe) {
        dc.drawRect(
          Rect.fromLTWH(dx - 2, dy - 2, fillP.width + 4, fillP.height + 4),
          _selfSendPaint,
        );
      }

      dc.drawParagraph(fillP, offset);
    }

    // 批量录制：一次 drawPicture 提交所有绘制命令
    if (recorder != null) {
      final picture = recorder.endRecording();
      canvas.drawPicture(picture);
    }

    // [NEXT-DIAG] paint 完成后检查耗时
    diagPaintSw?.stop();
    if (diagPaintSw != null && diagPaintSw.elapsedMicroseconds > 2000) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastDiagPaintTimeMs >= 2000) {
        _lastDiagPaintTimeMs = now;
        debugPrint(
            '[NEXT-DIAG] SLOW PAINT: ${diagPaintSw.elapsedMicroseconds}μs items=${items.length}');
      }
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  Paragraph 构建 — 一次构建，逐帧复用
  // ════════════════════════════════════════════════════════════════

  /// 基础 ParagraphStyle
  ui.ParagraphStyle _baseStyle(double fontSize) {
    return ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontSize: fontSize,
      fontWeight: FontWeight.normal,
      textDirection: TextDirection.ltr,
      fontFamily: fontFamily,
      locale: locale,
    );
  }

  /// 填充 Paragraph（无阴影）
  ui.Paragraph _buildFillParagraph(
      DanmakuContentItem content, double fontSize, Color color) {
    final builder = ui.ParagraphBuilder(_baseStyle(fontSize))
      ..pushStyle(ui.TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
      ));
    _appendText(builder, content, false);
    final p = builder.build();
    p.layout(const ui.ParagraphConstraints(width: double.infinity));
    return p;
  }

  /// 描边 Paragraph（含可选阴影烘入）
  ///
  /// 阴影通过 TextStyle.shadows 烘入，Skia 在单次 drawParagraph 中
  /// 先绘制 shadow → 再绘制 glyph，无需额外 draw 调用。
  ui.Paragraph _buildStrokeParagraph(
    DanmakuContentItem content,
    double fontSize,
    Color strokeColor,
    double strokeWidth,
    _ShadowParams? shadow,
  ) {
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = strokeColor;

    final shadows = shadow != null
        ? <Shadow>[
            Shadow(
              color: Color.fromRGBO(0, 0, 0, shadow.opacity),
              blurRadius: shadow.blurSigma,
              offset: Offset(shadow.dx, shadow.dy),
            )
          ]
        : null;

    final builder = ui.ParagraphBuilder(_baseStyle(fontSize))
      ..pushStyle(ui.TextStyle(
        foreground: strokePaint,
        shadows: shadows,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
      ));
    _appendText(builder, content, true);
    final p = builder.build();
    p.layout(const ui.ParagraphConstraints(width: double.infinity));
    return p;
  }

  /// 填充+阴影 Paragraph（无描边时使用，阴影烘入填充）
  ui.Paragraph _buildFillWithShadowParagraph(
    DanmakuContentItem content,
    double fontSize,
    Color color,
    _ShadowParams shadow,
  ) {
    final builder = ui.ParagraphBuilder(_baseStyle(fontSize))
      ..pushStyle(ui.TextStyle(
        color: color,
        shadows: <Shadow>[
          Shadow(
            color: Color.fromRGBO(0, 0, 0, shadow.opacity),
            blurRadius: shadow.blurSigma,
            offset: Offset(shadow.dx, shadow.dy),
          )
        ],
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
      ));
    _appendText(builder, content, false);
    final p = builder.build();
    p.layout(const ui.ParagraphConstraints(width: double.infinity));
    return p;
  }

  /// 向 ParagraphBuilder 追加文本（含 countText 分段处理）
  ///
  /// 合并弹幕的 countText（如 "x15"）使用独立样式段，
  /// 通过 pushStyle 切换字号/粗细，parent 的 foreground/color 自动继承。
  void _appendText(
      ui.ParagraphBuilder builder, DanmakuContentItem content, bool isStroke) {
    final countText = content.countText;
    if (countText != null && countText.isNotEmpty) {
      builder.addText(content.text);
      // countText 用更小字号 + 粗体
      // isStroke 时 color=null → 继承 parent 的 foreground(Paint)
      // 非 isStroke 时 color=Colors.white → 覆盖 parent 的 color
      builder.pushStyle(ui.TextStyle(
        fontSize: 25.0,
        fontWeight: FontWeight.bold,
        color: isStroke ? null : Colors.white,
      ));
      builder.addText(countText);
    } else {
      builder.addText(content.text);
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  缓存 — 紧凑 String 键 + LRU 淘汰
  // ════════════════════════════════════════════════════════════════

  /// 紧凑缓存键：variant|fontSize|color|fontFamily|ffbKey|text|countText
  String _key(DanmakuContentItem content, double fontSize, int colorValue,
      String variant) {
    return '$variant|${fontSize.toStringAsFixed(1)}|$colorValue|'
        '${fontFamily ?? ''}|$_ffbKey|'
        '${content.text}'
        '${content.countText != null ? '|${content.countText}' : ''}';
  }

  ui.Paragraph _getOrBuild(String key, ui.Paragraph Function() builder) {
    final cached = _pCache[key];
    if (cached != null) {
      // LRU 提升
      _pCache.remove(key);
      _pCache[key] = cached;
      return cached;
    }
    final p = builder();
    if (_pCache.length >= _pCacheLimit && _pCache.isNotEmpty) {
      _pCache.remove(_pCache.keys.first);
    }
    _pCache[key] = p;
    return p;
  }

  // ════════════════════════════════════════════════════════════════
  //  样式计算
  // ════════════════════════════════════════════════════════════════

  _ShadowParams? _resolveShadowParams(double targetFontSize) {
    final double unit = _resolveUniformOutlineRadius(targetFontSize);
    switch (shadowStyle) {
      case DanmakuShadowStyle.none:
        return null;
      case DanmakuShadowStyle.soft:
        return _ShadowParams(
            dx: unit * 0.8, dy: unit * 0.8, blurSigma: unit * 0.9, opacity: 0.34);
      case DanmakuShadowStyle.medium:
        return _ShadowParams(
            dx: unit, dy: unit, blurSigma: unit * 1.2, opacity: 0.44);
      case DanmakuShadowStyle.strong:
        return _ShadowParams(
            dx: unit * 1.2, dy: unit * 1.2, blurSigma: unit * 1.5, opacity: 0.55);
    }
  }

  double _resolveStrokeWidth(double targetFontSize) {
    return (targetFontSize * 0.06).clamp(1.0, 2.6);
  }

  double _resolveUniformOutlineRadius(double targetFontSize) {
    return math.max(0.8, (targetFontSize * 0.045).clamp(0.8, 2.0));
  }

  /// uniform 描边→等价 strokeWidth：8方向半径 R ≈ 单笔画宽度 2.5R
  double _resolveUniformStrokeWidth(double targetFontSize) {
    return (_resolveUniformOutlineRadius(targetFontSize) * 2.5).clamp(1.5, 5.0);
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
  bool shouldRepaint(covariant NipaPlayNextCanvasPainter oldDelegate) {
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

// ════════════════════════════════════════════════════════════════
//  辅助
// ════════════════════════════════════════════════════════════════

class _ShadowParams {
  const _ShadowParams({
    required this.dx,
    required this.dy,
    required this.blurSigma,
    required this.opacity,
  });
  final double dx;
  final double dy;
  final double blurSigma;
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
