// ════════════════════════════════════════════════════════════════════
//  P5: MSDF drawRect + Paint.shader 逐字形渲染器
//
//  替代旧版 drawVertices 批量提交（SkSL 不兼容导致构建崩溃）：
//  - 逐字形 canvas.drawRect(rect, Paint..shader)
//  - 每个 glyph 设置 per-draw uniform（uAtlasRect, uRectSize, uFillColor）
//  - 全局 uniform（uTexture, uSpread, uOutlinePx）每次 draw 前设置
//  - FilterQuality.none
//
//  Uniform 布局（对应 msdf_text.frag）：
//    Image sampler slot 0: uTexture (MSDF 字形图集)
//    Float slot 0:  uSpread
//    Float slot 1:  uOutlinePx
//    Float slot 2:  uAtlasRect.x (u0)
//    Float slot 3:  uAtlasRect.y (v0)
//    Float slot 4:  uAtlasRect.z (uW)
//    Float slot 5:  uAtlasRect.w (vH)
//    Float slot 6:  uRectSize.x (width)
//    Float slot 7:  uRectSize.y (height)
//    Float slot 8:  uFillColor.r
//    Float slot 9:  uFillColor.g
//    Float slot 10: uFillColor.b
//    Float slot 11: uFillColor.a (outlineSelector: 0.0=黑, 1.0=白)
// ════════════════════════════════════════════════════════════════════

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'danmaku_next_log.dart';

class MsdfTextRenderer {
  static const String _shaderAsset = 'assets/shaders/danmaku/msdf_text_next.frag';

  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  final Paint _paint = Paint()..filterQuality = ui.FilterQuality.none;

  bool get isReady => _shader != null;

  /// Uniform float slot indices
  static const int _kSpread = 0;
  static const int _kOutlinePx = 1;
  static const int _kAtlasU0 = 2;
  static const int _kAtlasV0 = 3;
  static const int _kAtlasUW = 4;
  static const int _kAtlasVH = 5;
  static const int _kRectW = 6;
  static const int _kRectH = 7;
  static const int _kFillR = 8;
  static const int _kFillG = 9;
  static const int _kFillB = 10;
  static const int _kOutlineSelector = 11;

  Future<void> initialize() async {
    if (_program != null) return;
    try {
      _program = await ui.FragmentProgram.fromAsset(_shaderAsset);
      _shader = _program!.fragmentShader();
      DanmakuNextLog.once('Renderer', 'MSDF P5 shader loaded (drawRect per-glyph)');
    } catch (e) {
      DanmakuNextLog.d('Renderer', 'MSDF P5 shader load failed: $e', throttle: Duration.zero);
    }
  }

  /// 绘制单个 MSDF 字形
  ///
  /// [canvas] — 画布
  /// [atlasTexture] — MSDF 字形图集纹理
  /// [spread] — MSDF spread 值
  /// [outlinePx] — 描边像素宽度
  /// [drawX], [drawY] — 屏幕坐标左上角
  /// [glyphW], [glyphH] — 逻辑宽高
  /// [atlasU], [atlasV] — 图集纹理坐标左上角（0-1 normalized）
  /// [atlasUW], [atlasVH] — 图集纹理坐标宽高（0-1 normalized）
  /// [fillColorARGB] — 填充颜色 ARGB32
  /// [isWhiteOutline] — 描边颜色：true=白, false=黑
  void drawGlyph({
    required ui.Canvas canvas,
    required ui.Image atlasTexture,
    required double spread,
    required double outlinePx,
    required double drawX,
    required double drawY,
    required double glyphW,
    required double glyphH,
    required double atlasU,
    required double atlasV,
    required double atlasUW,
    required double atlasVH,
    required int fillColorARGB,
    required bool isWhiteOutline,
  }) {
    final shader = _shader;
    if (shader == null) return;

    // ── 全局 uniform（每次 draw 前设置） ──
    shader.setImageSampler(0, atlasTexture);
    shader.setFloat(_kSpread, spread);
    shader.setFloat(_kOutlinePx, outlinePx);

    // ── Per-glyph uniform ──
    shader.setFloat(_kAtlasU0, atlasU);
    shader.setFloat(_kAtlasV0, atlasV);
    shader.setFloat(_kAtlasUW, atlasUW);
    shader.setFloat(_kAtlasVH, atlasVH);
    shader.setFloat(_kRectW, glyphW);
    shader.setFloat(_kRectH, glyphH);

    // fillColor: decode ARGB32 → float rgb + outlineSelector
    final double r = ((fillColorARGB >> 16) & 0xFF) / 255.0;
    final double g = ((fillColorARGB >> 8) & 0xFF) / 255.0;
    final double b = (fillColorARGB & 0xFF) / 255.0;
    final double outlineSelector = isWhiteOutline ? 1.0 : 0.0;
    shader.setFloat(_kFillR, r);
    shader.setFloat(_kFillG, g);
    shader.setFloat(_kFillB, b);
    shader.setFloat(_kOutlineSelector, outlineSelector);

    // ── drawRect + Paint.shader ──
    _paint.shader = shader;
    canvas.drawRect(
      ui.Rect.fromLTWH(drawX, drawY, glyphW, glyphH),
      _paint,
    );
  }

  /// 获取描边颜色选择器 — 纯黑文字用白描边，其他用黑描边
  static bool isWhiteOutline(Color textColor) {
    const double epsilon = 1e-6;
    return textColor.r <= epsilon && textColor.g <= epsilon && textColor.b <= epsilon;
  }
}
