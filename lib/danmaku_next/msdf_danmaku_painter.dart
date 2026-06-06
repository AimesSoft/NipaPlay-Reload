// ════════════════════════════════════════════════════════════════════
//  P5: MSDF drawRect + Paint.shader 逐字形弹幕画笔
//
//  集成到 Next++ 引擎链路，复用核心架构：
//  - vsync 驱动 (Animation<double> repaint)
//  - 墙钟 dt + EMA 平滑 + 漂移校正
//  - 视口剔除
//  - Emoji bypass（非 BMP 字符回退到 drawParagraph）
//  - playbackRate 变化检测 + displayX 强制同步
//
//  渲染管线（替代 DanmakuAtlasPainter 的 sprite atlas + drawImageRect）：
//  layout → 遍历弹幕 → 遍历字形 → drawGlyph(drawRect + Paint.shader)
//  = N 次 GPU draw call（SkSL 兼容，vs 旧版 drawVertices 不兼容 SkSL）
// ════════════════════════════════════════════════════════════════════

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';

import 'msdf_font_atlas.dart';
import 'msdf_text_renderer.dart';
import 'nipaplay_next_engine.dart';

// ════════════════════════════════════════════════════════════════
//  诊断日志节流
// ════════════════════════════════════════════════════════════════

int _lastDiagPaintTimeMs = 0;
double _lastDiagPlaybackRate = 1.0;

int _lastDiagBottleneckTimeMs = 0;
int _diagLayoutItems = 0;
int _diagCulledItems = 0;
int _diagPendingGlyphs = 0;

int _diagDriftCorrectionCount = 0;
int _diagHardSnapCount = 0;
double _diagMaxDrift = 0.0;

// ════════════════════════════════════════════════════════════════
//  主画笔
// ════════════════════════════════════════════════════════════════

/// P5 MSDF drawRect + Paint.shader 逐字形弹幕画笔
///
/// 渲染管线：
///   layout → 遍历弹幕 → 遍历字形 → drawGlyph(drawRect + Paint.shader)
///   = N 次 GPU draw call（SkSL 兼容，vs 旧版 drawVertices 不兼容 SkSL）
class MsdfDanmakuPainter extends CustomPainter {
  MsdfDanmakuPainter({
    required this.vsyncNotifier,
    required this.engine,
    required this.playbackTimeMs,
    required this.playbackRate,
    required this.isPlaying,
    required this.timeOffsetSeconds,
    required this.fontSize,
    required this.outlineWidth,
    required this.opacity,
    required this.msdfAtlas,
    required this.msdfRenderer,
  }) : super(repaint: vsyncNotifier);

  final Animation<double> vsyncNotifier;
  final NipaPlayNextEngine engine;
  final ValueListenable<double> playbackTimeMs;
  final double playbackRate;
  final bool isPlaying;
  final double timeOffsetSeconds;
  final double fontSize;
  final double outlineWidth;
  final double opacity;
  final MsdfFontAtlas msdfAtlas;
  final MsdfTextRenderer msdfRenderer;

  late final int _layoutVersion = engine.layoutVersion;

  // ════════════════════════════════════════════════════════════════
  //  墙钟 dt + EMA（与 DanmakuAtlasPainter 完全一致）
  // ════════════════════════════════════════════════════════════════

  static final Stopwatch _wallClock = Stopwatch()..start();
  static int _lastWallUs = 0;
  static double _smoothedDtSeconds = 0.0;
  static const double _dtEmaAlpha = 0.3;

  // ── Emoji bypass 绘制列表 ──
  static final List<_EmojiDrawInfo> _emojiDrawList = [];
  static int _emojiBypassCount = 0;

  // ── 自发弹幕边框 Paint ──
  static final Paint _selfSendPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.white;

  // ════════════════════════════════════════════════════════════════
  //  主绘制循环
  // ════════════════════════════════════════════════════════════════

  @override
  void paint(Canvas canvas, Size size) {
    final diagPaintSw = kDebugMode ? Stopwatch() : null;
    diagPaintSw?.start();

    // ── MSDF 渲染器就绪检查 ──
    if (!msdfRenderer.isReady || msdfAtlas.atlasTexture == null) {
      return;
    }

    // ── 墙钟 dt ──
    final currentWallUs = _wallClock.elapsedMicroseconds;
    final double rawDtSeconds;
    if (_lastWallUs == 0 || currentWallUs < _lastWallUs) {
      rawDtSeconds = 0.0;
    } else {
      final deltaUs = currentWallUs - _lastWallUs;
      rawDtSeconds = (deltaUs < 100000) ? deltaUs / 1000000.0 : 0.0;
    }
    _lastWallUs = currentWallUs;

    // ── EMA 平滑 dt ──
    final double dtSeconds;
    if (!isPlaying) {
      dtSeconds = 0.0;
    } else if (rawDtSeconds == 0.0) {
      dtSeconds = 0.0;
    } else if (_smoothedDtSeconds == 0.0) {
      dtSeconds = rawDtSeconds;
      _smoothedDtSeconds = rawDtSeconds;
    } else {
      _smoothedDtSeconds =
          _dtEmaAlpha * rawDtSeconds + (1.0 - _dtEmaAlpha) * _smoothedDtSeconds;
      dtSeconds = _smoothedDtSeconds;
    }

    final items =
        engine.layout(playbackTimeMs.value / 1000.0 + timeOffsetSeconds);
    if (items.isEmpty) return;

    // ── playbackRate 变化检测 ──
    if (playbackRate != _lastDiagPlaybackRate) {
      if (!kReleaseMode) {
        debugPrint('[MSDF-DIAG] RATE CHANGE: $_lastDiagPlaybackRate → $playbackRate');
      }
      _lastDiagPlaybackRate = playbackRate;
      for (final item in items) {
        if (item.scrollSpeed > 0.0) {
          item.displayX = item.x;
        }
      }
    }

    // ── 重置帧缓冲区 ──
    _emojiDrawList.clear();
    _emojiBypassCount = 0;

    // ── 诊断计数器重置 ──
    _diagLayoutItems = items.length;
    _diagCulledItems = 0;
    _diagPendingGlyphs = 0;
    _diagDriftCorrectionCount = 0;
    _diagHardSnapCount = 0;
    _diagMaxDrift = 0.0;

    // ── MSDF 全局参数 ──
    final texture = msdfAtlas.atlasTexture!;
    final double spread = msdfAtlas.spread.toDouble() * msdfAtlas.atlasScale;
    final double outlinePx = outlineWidth * 2.0;

    // ══════════════════════════════════════════════════════════════
    //  遍历弹幕 — 增量定位 + 视口剔除 + 字形收集
    // ══════════════════════════════════════════════════════════════

    for (final item in items) {
      final content = item.content;

      // ── 增量定位（与 DanmakuAtlasPainter 完全一致） ──
      final double drawX;
      if (item.scrollSpeed > 0.0) {
        if (item.displayX.isNaN) {
          item.displayX = item.x;
        } else {
          item.displayX -= item.scrollSpeed * dtSeconds * playbackRate;
          final drift = item.displayX - item.x;
          final absDrift = drift.abs();
          if (absDrift > _diagMaxDrift) _diagMaxDrift = absDrift;
          if (absDrift > 200.0) {
            item.displayX = item.x;
            _diagHardSnapCount++;
          } else if (absDrift > 50.0) {
            item.displayX = item.displayX + (item.x - item.displayX) * 0.15;
            _diagDriftCorrectionCount++;
          }
        }
        drawX = item.displayX;
      } else {
        drawX = item.x;
      }
      final drawY = item.y;

      // ── 视口剔除 ──
      final itemWidth = item.width;
      if (itemWidth > 0.0) {
        if (drawX + itemWidth < -12.0 || drawX > size.width) {
          _diagCulledItems++;
          continue;
        }
      }

      // ── Emoji 弹幕绕过 MSDF → 直接 drawParagraph ──
      // MSDF 不支持 CBDT/COLRv1 彩色 Emoji
      {
        final text = content.text;
        final hasNonBmp = text.runes.any((r) => r > 0xFFFF);
        if (hasNonBmp) {
          _emojiBypassCount++;
          _emojiDrawList.add(_EmojiDrawInfo(
            content: content,
            drawX: drawX,
            drawY: drawY,
            fontSize: fontSize * content.fontSizeMultiplier,
          ));
          continue;
        }
      }

      // ── 描边颜色选择 ──
      final bool isWhiteOutline = MsdfTextRenderer.isWhiteOutline(content.color);
      final int fillColorARGB = content.color.toARGB32();

      // ── 遍历字形 → addGlyph ──
      double cursorX = drawX;
      final text = content.text;

      for (final rune in text.runes) {
        final charStr = String.fromCharCode(rune);
        final glyph = msdfAtlas.getGlyph(charStr);

        if (glyph == null) {
          // 字形未就绪 — 触发异步生成，本帧跳过
          msdfAtlas.addText(charStr);
          _diagPendingGlyphs++;
          cursorX += fontSize * content.fontSizeMultiplier * 0.5; // 估算 advance
          continue;
        }

        final rect = glyph.atlasRect;
        final double glyphW = rect.width * msdfAtlas.atlasScale;
        final double glyphH = rect.height * msdfAtlas.atlasScale;

        final double gx = cursorX - glyph.offsetX;
        final double gy = drawY - glyph.offsetY;

        // 视口剔除：跳过完全不可见的字形 quad
        if (gx + glyphW < 0.0 || gx > size.width || gy + glyphH < 0.0 || gy > size.height) {
          cursorX += glyph.advance;
          continue;
        }

        // 计算图集纹理坐标（0-1 normalized）
        final double u0 = rect.left / texture.width;
        final double v0 = rect.top / texture.height;
        final double uW = rect.width / texture.width;
        final double vH = rect.height / texture.height;

        msdfRenderer.drawGlyph(
          canvas: canvas,
          atlasTexture: texture,
          spread: spread,
          outlinePx: outlinePx,
          drawX: gx,
          drawY: gy,
          glyphW: glyphW,
          glyphH: glyphH,
          atlasU: u0,
          atlasV: v0,
          atlasUW: uW,
          atlasVH: vH,
          fillColorARGB: fillColorARGB,
          isWhiteOutline: isWhiteOutline,
        );

        cursorX += glyph.advance;
      }

      // ── 自发弹幕边框 ──
      if (content.isMe) {
        canvas.drawRect(
          ui.Rect.fromLTWH(drawX - 2, drawY - 2, itemWidth + 4,
              fontSize * content.fontSizeMultiplier + 4),
          _selfSendPaint,
        );
      }
    }

    // ══════════════════════════════════════════════════════════════
    //  Emoji bypass 渲染（MSDF drawGlyph 已在内层循环中逐字形提交）
    // ══════════════════════════════════════════════════════════════

    // ── Emoji bypass — drawParagraph ──
    if (_emojiDrawList.isNotEmpty) {
      for (final emoji in _emojiDrawList) {
        _drawEmojiFallback(canvas, emoji);
      }
    }

    // ── 诊断输出 ──
    diagPaintSw?.stop();
    if (diagPaintSw != null && diagPaintSw.elapsedMicroseconds > 2000) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastDiagPaintTimeMs >= 2000) {
        _lastDiagPaintTimeMs = now;
        debugPrint(
            '[MSDF-DIAG] SLOW PAINT: ${diagPaintSw.elapsedMicroseconds}μs '
            'items=${items.length} culled=$_diagCulledItems '
            'pendingGlyphs=$_diagPendingGlyphs '
            'emoji=$_emojiBypassCount');
      }
    }

    if (!kReleaseMode) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastDiagBottleneckTimeMs >= 2000) {
        _lastDiagBottleneckTimeMs = now;
        debugPrint('[MSDF-DIAG] LAYOUT=$_diagLayoutItems '
            'CULL=$_diagCulledItems PENDING=$_diagPendingGlyphs '
            'EMOJI=$_emojiBypassCount');

        debugPrint('[MSDF-DRIFT] CORRECTIONS=$_diagDriftCorrectionCount '
            'HARD_SNAPS=$_diagHardSnapCount '
            'MAX_DRIFT=${_diagMaxDrift.toStringAsFixed(1)}px '
            'RATE=$playbackRate dt=${dtSeconds.toStringAsFixed(4)}s');
      }
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  Emoji bypass — drawParagraph 回退渲染
  // ════════════════════════════════════════════════════════════════

  void _drawEmojiFallback(Canvas canvas, _EmojiDrawInfo emoji) {
    final content = emoji.content;
    final double adjFontSize = emoji.fontSize;

    // 构建填充 Paragraph
    final fillBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontSize: adjFontSize,
      fontWeight: FontWeight.normal,
      textDirection: TextDirection.ltr,
    ))
      ..pushStyle(ui.TextStyle(color: content.color));

    final countText = content.countText;
    if (countText != null && countText.isNotEmpty) {
      fillBuilder.addText(content.text);
      fillBuilder.pushStyle(ui.TextStyle(
        fontSize: 25.0,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ));
      fillBuilder.addText(countText);
    } else {
      fillBuilder.addText(content.text);
    }

    final fillP = fillBuilder.build();
    fillP.layout(const ui.ParagraphConstraints(width: double.infinity));

    // 构建描边 Paragraph
    final strokeColor = MsdfTextRenderer.isWhiteOutline(content.color)
        ? Colors.white
        : Colors.black;
    final strokeBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontSize: adjFontSize,
      fontWeight: FontWeight.normal,
      textDirection: TextDirection.ltr,
    ))
      ..pushStyle(ui.TextStyle(
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (adjFontSize * 0.06).clamp(1.0, 2.6)
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..color = strokeColor,
      ));

    if (countText != null && countText.isNotEmpty) {
      strokeBuilder.addText(content.text);
      strokeBuilder.pushStyle(ui.TextStyle(
        fontSize: 25.0,
        fontWeight: FontWeight.bold,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..color = strokeColor,
      ));
      strokeBuilder.addText(countText);
    } else {
      strokeBuilder.addText(content.text);
    }

    final strokeP = strokeBuilder.build();
    strokeP.layout(const ui.ParagraphConstraints(width: double.infinity));

    canvas.drawParagraph(strokeP, ui.Offset(emoji.drawX, emoji.drawY));
    canvas.drawParagraph(fillP, ui.Offset(emoji.drawX, emoji.drawY));
  }

  @override
  bool shouldRepaint(covariant MsdfDanmakuPainter oldDelegate) {
    return oldDelegate._layoutVersion != _layoutVersion ||
        oldDelegate.engine != engine ||
        oldDelegate.playbackRate != playbackRate ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.timeOffsetSeconds != timeOffsetSeconds ||
        oldDelegate.fontSize != fontSize ||
        oldDelegate.outlineWidth != outlineWidth ||
        oldDelegate.opacity != opacity;
  }
}

// ════════════════════════════════════════════════════════════════
//  辅助类
// ════════════════════════════════════════════════════════════════

class _EmojiDrawInfo {
  final DanmakuContentItem content;
  final double drawX;
  final double drawY;
  final double fontSize;

  _EmojiDrawInfo({
    required this.content,
    required this.drawX,
    required this.drawY,
    required this.fontSize,
  });
}
