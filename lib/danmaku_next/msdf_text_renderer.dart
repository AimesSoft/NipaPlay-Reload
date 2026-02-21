import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

import 'danmaku_next_log.dart';
import 'msdf_font_atlas.dart';

class MsdfTextRenderer {
  static const String _shaderAsset = 'assets/shaders/danmaku/msdf_text.frag';

  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  final Paint _paint = Paint()..filterQuality = FilterQuality.low;

  bool get isReady => _shader != null;

  Future<void> initialize() async {
    if (_program != null) return;
    try {
      _program = await ui.FragmentProgram.fromAsset(_shaderAsset);
      _shader = _program!.fragmentShader();
      DanmakuNextLog.once('Renderer', 'MSDF shader loaded');
    } catch (e) {
      DanmakuNextLog.d('Renderer', 'MSDF shader load failed: $e', throttle: Duration.zero);
    }
  }

  void renderDanmaku(
    Canvas canvas,
    MsdfFontAtlas atlas,
    PositionedDanmakuItem item,
    double opacity,
  ) {
    if (_shader == null || atlas.atlasTexture == null) return;

    final texture = atlas.atlasTexture!;
    _shader!.setImageSampler(0, texture);

    final fillColor = item.content.color;
    final outlineColor = _getOutlineColor(fillColor);

    final double spread = atlas.spread.toDouble() * atlas.atlasScale;
    final double outlinePx = globals.strokeWidth * 2.0;

    double cursorX = item.x;
    final double cursorY = item.y;

    for (final rune in item.content.text.runes) {
      final charStr = String.fromCharCode(rune);
      final glyph = atlas.getGlyph(charStr);
      if (glyph == null) {
        atlas.addText(charStr);
        continue;
      }

      final rect = glyph.atlasRect;
      final double glyphW = rect.width * atlas.atlasScale;
      final double glyphH = rect.height * atlas.atlasScale;

      final double drawX = cursorX - glyph.offsetX;
      final double drawY = cursorY - glyph.offsetY;

      final drawRect = Rect.fromLTWH(drawX, drawY, glyphW, glyphH);

      final atlasRect = Rect.fromLTWH(
        rect.left / texture.width,
        rect.top / texture.height,
        rect.width / texture.width,
        rect.height / texture.height,
      );

      _setUniforms(
        drawRect,
        atlasRect,
        fillColor,
        outlineColor,
        opacity,
        spread,
        outlinePx,
      );

      _paint.shader = _shader;
      canvas.drawRect(drawRect, _paint);

      cursorX += glyph.advance;
    }
  }

  void _setUniforms(
    Rect drawRect,
    Rect atlasRect,
    Color fill,
    Color outline,
    double opacity,
    double spread,
    double outlinePx,
  ) {
    _shader!
      ..setFloat(0, drawRect.left)
      ..setFloat(1, drawRect.top)
      ..setFloat(2, drawRect.width)
      ..setFloat(3, drawRect.height)
      ..setFloat(4, atlasRect.left)
      ..setFloat(5, atlasRect.top)
      ..setFloat(6, atlasRect.width)
      ..setFloat(7, atlasRect.height)
      ..setFloat(8, fill.red / 255.0)
      ..setFloat(9, fill.green / 255.0)
      ..setFloat(10, fill.blue / 255.0)
      ..setFloat(11, fill.alpha / 255.0)
      ..setFloat(12, outline.red / 255.0)
      ..setFloat(13, outline.green / 255.0)
      ..setFloat(14, outline.blue / 255.0)
      ..setFloat(15, outline.alpha / 255.0)
      ..setFloat(16, opacity)
      ..setFloat(17, spread)
      ..setFloat(18, outlinePx);
  }

  Color _getOutlineColor(Color textColor) {
    final luminance =
        (0.299 * textColor.red + 0.587 * textColor.green + 0.114 * textColor.blue) / 255;
    return luminance < 0.2 ? Colors.white : Colors.black;
  }
}
