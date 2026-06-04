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

/// 高性能弹幕画师 — vsync 驱动 + ui.Paragraph 直绘 + 增量定位
///
/// ┌──────────────────────┬──────────────────────────┬──────────────────────────┐
/// │ 环节                 │ 旧实现                   │ 新实现                   │
/// ├──────────────────────┼──────────────────────────┼──────────────────────────┤
/// │ 重绘驱动             │ playbackTimeMs ValueNotifier│ AnimationController vsync│
/// │ 帧间隔(dt)           │ playbackTime delta(含漂移) │ Stopwatch 墙钟时间       │
/// │ 文本渲染对象         │ TextPainter + 9字段Key    │ ui.Paragraph + 紧凑String│
/// │ 描边(emoji)          │ 8× saveLayer(极慢)        │ 单次 thick-stroke Para   │
/// │ 描边(uniform)        │ 8× paint(offset)          │ 8方向Shadow烘入单Para    │
/// │ 阴影                 │ 独立 TextPainter+MaskFilter│ TextStyle.shadows 烘入   │
/// │ 坐标定位             │ save/translate/restore    │ drawParagraph(Offset)    │
/// │ 倍速滚动             │ 绝对位置(帧间隔敏感)      │ 增量定位(墙钟dt×rate)    │
/// │ 批量绘制             │ 无                       │ 始终PictureRecorder      │
/// └──────────────────────┴──────────────────────────┴──────────────────────────┘
///
/// GPU 进一步优化路径（工程量较大，可作为下一阶段）：
/// - MSDF + drawRawAtlas：将所有弹幕字符渲染为纹理四边形，
///   单次 drawRawAtlas 调用绘制全部可见弹幕（draw call O(1) vs O(n)）
/// - 项目已有 msdf_font_atlas.dart / msdf_text_renderer.dart / msdf_text.frag
///   可复用，但需改造为 drawRawAtlas 批量模式
class NipaPlayNextCanvasPainter extends CustomPainter {
  NipaPlayNextCanvasPainter({
    required this.vsyncNotifier,
    required this.engine,
    required this.playbackTimeMs,
    required this.playbackRate,
    required this.timeOffsetSeconds,
    required this.fontSize,
    required this.fontFamily,
    required this.fontFamilyFallback,
    required this.locale,
    required this.outlineStyle,
    required this.shadowStyle,
  }) : super(repaint: vsyncNotifier);

  /// vsync 动画控制器 — 以屏幕刷新率驱动 paint()
  final Animation<double> vsyncNotifier;

  final NipaPlayNextEngine engine;
  final ValueListenable<double> playbackTimeMs;
  final double playbackRate;
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

  /// Paragraph 全局缓存（fill / stroke / uniform-outline 共用）
  static final LinkedHashMap<String, ui.Paragraph> _pCache =
      LinkedHashMap<String, ui.Paragraph>();
  static const int _pCacheLimit = 6000;

  /// 自发弹幕边框
  static final Paint _selfSendPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.white;

  /// 墙钟 Stopwatch — 测量真实帧间隔，消除平滑时钟漂移
  static final Stopwatch _wallClock = Stopwatch()..start();
  static int _lastWallUs = 0;

  /// uniform 描边8方向偏移（与旧版 _paintUniformOutline 一致）
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

  // ════════════════════════════════════════════════════════════════
  //  主绘制循环 — vsync 驱动 + 墙钟增量定位 + 始终 PictureRecorder
  // ════════════════════════════════════════════════════════════════

  @override
  void paint(Canvas canvas, Size size) {
    final diagPaintSw = kDebugMode ? Stopwatch() : null;
    diagPaintSw?.start();

    // ── 墙钟 dt：真实帧间隔，不受平滑时钟漂移/seek保护影响 ──
    final currentWallUs = _wallClock.elapsedMicroseconds;
    final double dtSeconds;
    if (_lastWallUs == 0 || currentWallUs < _lastWallUs) {
      dtSeconds = 0.0; // 首帧或 Stopwatch 重置
    } else {
      final deltaUs = currentWallUs - _lastWallUs;
      // 过大间隔（>100ms，暂停恢复/后台切换）→ 不推进，避免跳帧
      dtSeconds = (deltaUs < 100000) ? deltaUs / 1000000.0 : 0.0;
    }
    _lastWallUs = currentWallUs;

    final items =
        engine.layout(playbackTimeMs.value / 1000.0 + timeOffsetSeconds);
    if (items.isEmpty) {
      diagPaintSw?.stop();
      return;
    }

    // ── 始终使用 PictureRecorder ──
    // Impeller/Skia 均受益于单 Picture 提交：
    // 减少 render pass 切换，允许 GPU 命令缓冲整体优化
    // recorder 创建开销 < 0.1μs，对任何弹幕数量都值得
    final recorder = ui.PictureRecorder();
    final dc = Canvas(recorder);

    // 预计算阴影参数（所有弹幕共享，只算一次）
    final shadowParams = _resolveShadowParams(fontSize);

    for (final item in items) {
      final content = item.content;
      final adjFontSize = fontSize * content.fontSizeMultiplier;
      final itemStrokeColor = _getStrokeColor(textColor: content.color);
      final int colorVal = content.color.toARGB32();
      final int strokeColorVal = itemStrokeColor.toARGB32();

      // ── 增量定位：滚动弹幕用 displayX + 墙钟dt × playbackRate 推进 ──
      final double drawX;
      if (item.scrollSpeed > 0.0) {
        if (item.displayX.isNaN || (item.displayX - item.x).abs() > 50.0) {
          // 首次出现 / seek 大跳变：从引擎绝对位置初始化
          item.displayX = item.x;
        } else {
          // 正常播放：墙钟增量 × playbackRate = 真实视觉推进量
          item.displayX -= item.scrollSpeed * dtSeconds * playbackRate;
        }
        drawX = item.displayX;
      } else {
        drawX = item.x;
      }
      final drawY = item.y;

      // ── 获取或构建 Paragraph ──
      final ui.Paragraph fillP;
      final ui.Paragraph? strokeP;

      if (outlineStyle == DanmakuOutlineStyle.uniform) {
        // uniform 描边：8方向零模糊 Shadow 烘入 fill Paragraph
        // 几何膨胀效果与旧版8方向偏移像素级一致，但只需1次 drawParagraph
        final radius = _resolveUniformOutlineRadius(adjFontSize);
        final uKey = _key(content, adjFontSize, strokeColorVal,
            'u${radius.toStringAsFixed(1)}');
        fillP = _getOrBuild(uKey, () => _buildUniformOutlineParagraph(
              content, adjFontSize, content.color, itemStrokeColor,
              radius, shadowParams,
            ));
        strokeP = null;
      } else if (outlineStyle == DanmakuOutlineStyle.stroke) {
        // thin stroke 描边：独立 stroke Paragraph（与旧版等价）
        final strokeWidth = _resolveStrokeWidth(adjFontSize);
        final sKey = _key(content, adjFontSize, strokeColorVal,
            's${strokeWidth.toStringAsFixed(1)}');
        strokeP = _getOrBuild(sKey, () => _buildStrokeParagraph(
              content, adjFontSize, itemStrokeColor, strokeWidth, shadowParams,
            ));

        final fKey = _key(content, adjFontSize, colorVal, 'f');
        fillP = _getOrBuild(fKey,
            () => _buildFillParagraph(content, adjFontSize, content.color));
      } else if (shadowParams != null) {
        // 无描边有阴影：阴影烘入填充
        final fsKey = _key(content, adjFontSize, colorVal, 'fs');
        fillP = _getOrBuild(fsKey, () => _buildFillWithShadowParagraph(
              content, adjFontSize, content.color, shadowParams,
            ));
        strokeP = null;
      } else {
        // 纯填充
        final fKey = _key(content, adjFontSize, colorVal, 'f');
        fillP = _getOrBuild(fKey,
            () => _buildFillParagraph(content, adjFontSize, content.color));
        strokeP = null;
      }

      final offset = Offset(drawX, drawY);

      // ── 绘制：描边(含阴影) → 自发标识 → 填充 ──
      if (strokeP != null) {
        dc.drawParagraph(strokeP, offset);
      }

      if (content.isMe) {
        dc.drawRect(
          Rect.fromLTWH(drawX - 2, drawY - 2, fillP.width + 4, fillP.height + 4),
          _selfSendPaint,
        );
      }

      dc.drawParagraph(fillP, offset);
    }

    // 单次 drawPicture 提交全部绘制命令 — GPU 命令缓冲整体优化
    final picture = recorder.endRecording();
    canvas.drawPicture(picture);

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

  /// 描边 Paragraph（含可选阴影烘入）— 用于 DanmakuOutlineStyle.stroke
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

  /// uniform 描边 Paragraph — 8方向零模糊 Shadow 几何膨胀
  ///
  /// 在 TextStyle.shadows 中放入 8 个 Shadow(offset=方向×R, blurRadius=0)，
  /// 视觉效果等价于旧版 _paintUniformOutline 的8次偏移绘制（几何膨胀），
  /// 但全部烘入单个 Paragraph，只需1次 drawParagraph。
  ui.Paragraph _buildUniformOutlineParagraph(
    DanmakuContentItem content,
    double fontSize,
    Color fillColor,
    Color outlineColor,
    double radius,
    _ShadowParams? shadow,
  ) {
    final shadows = <Shadow>[];

    // drop shadow 放在最底层（Skia 按列表顺序先渲染）
    if (shadow != null) {
      shadows.add(Shadow(
        color: Color.fromRGBO(0, 0, 0, shadow.opacity),
        blurRadius: shadow.blurSigma,
        offset: Offset(shadow.dx, shadow.dy),
      ));
    }

    // 8方向零模糊 outline — 几何膨胀（与旧版 _paintUniformOutline 像素级一致）
    for (final (dx, dy) in _uniformOutlineDirs) {
      shadows.add(Shadow(
        color: outlineColor,
        offset: Offset(dx * radius, dy * radius),
        blurRadius: 0.0,
      ));
    }

    final builder = ui.ParagraphBuilder(_baseStyle(fontSize))
      ..pushStyle(ui.TextStyle(
        color: fillColor,
        shadows: shadows,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
      ));
    _appendText(builder, content, false);
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
  void _appendText(
      ui.ParagraphBuilder builder, DanmakuContentItem content, bool isStroke) {
    final countText = content.countText;
    if (countText != null && countText.isNotEmpty) {
      builder.addText(content.text);
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
        oldDelegate.playbackRate != playbackRate ||
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
