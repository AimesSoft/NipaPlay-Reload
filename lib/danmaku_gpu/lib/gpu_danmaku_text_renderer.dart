
import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_text_renderer.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'gpu_danmaku_item.dart';
import 'dynamic_font_atlas.dart';
import 'gpu_danmaku_config.dart';
import 'dart:math' as math;

/// GPU弹幕文本渲染器
///
/// 负责处理弹幕文本的描边和填充渲染
class GpuDanmakuTextRenderer extends DanmakuTextRenderer {
  final DynamicFontAtlas _fontAtlas;
  GPUDanmakuConfig config;

  GpuDanmakuTextRenderer({
    required DynamicFontAtlas fontAtlas,
    required this.config,
  }) : _fontAtlas = fontAtlas;

  @override
  Widget build(
    BuildContext context,
    DanmakuContentItem content,
    double fontSize,
    double opacity,
  ) {
    // 确保文本已经添加到图集
    _fontAtlas.addText(content.text);
    if (content.countText != null) {
      _fontAtlas.addText(content.countText!);
    }

    final gpuItem = GPUDanmakuItem(
      text: content.text,
      timeOffset: 0, // time is not used for rendering appearance
      type: content.type,
      color: content.color,
      createdAt: 0, // id is not used for rendering appearance
    );

    return CustomPaint(
      painter: _GpuDanmakuPainter(
        renderer: this,
        item: gpuItem,
        opacity: opacity,
        fontSizeMultiplier: content.fontSizeMultiplier,
        countText: content.countText,
      ),
      // 根据文本内容估算尺寸，以便CustomPaint有正确的绘制区域
      // 🔥 修改：增加额外高度以适应emoji和带descender的字符
      size: Size(
        calculateTextWidth(
          content.text + (content.countText ?? ''),
          scale: 0.5 * content.fontSizeMultiplier,
        ),
        config.fontSize * content.fontSizeMultiplier * 1.4, // 增加40%的高度缓冲
      ),
    );
  }

  /// 通用的渲染方法
  void render({
    required Canvas canvas,
    required String text,
    required Offset offset,
    required double opacity,
    double fontSizeMultiplier = 1.0,
    String? countText,
    Color color = Colors.white,
    DanmakuItemType type = DanmakuItemType.scroll,
  }) {
    final tempItem = GPUDanmakuItem(
      text: text,
      color: color,
      type: type,
      timeOffset: 0,
      createdAt: 0,
    );
    renderItem(
      canvas,
      tempItem,
      offset.dx,
      offset.dy,
      opacity,
      fontSizeMultiplier: fontSizeMultiplier,
      countText: countText,
    );
  }

  /// 根据文字颜色判断使用的描边颜色，与 NipaPlay 保持一致
  Color _getShadowColor(Color textColor) {
    // 计算亮度，与 NipaPlay 的算法保持一致
    final luminance = (0.299 * textColor.red + 0.587 * textColor.green + 0.114 * textColor.blue) / 255;
    // 如果亮度小于0.2，说明是深色，使用白色描边；否则使用黑色描边
    return luminance < 0.2 ? Colors.white : Colors.black;
  }

  /// 获取描边偏移量，移动端使用更细的描边
  double _getStrokeOffset() {
    // 移动端使用0.5像素偏移，桌面端使用1.0像素偏移
    return globals.isPhone ? 0.5 : 1.0;
  }

  /// 渲染单个弹幕项目的文本
  ///
  /// 参数:
  /// - canvas: 画布
  /// - item: 弹幕项目
  /// - x: 文本起始X坐标
  /// - y: 文本起始Y坐标
  /// - opacity: 透明度
  /// - scale: 缩放比例（默认0.5，从2倍图集缩小回1倍）
  /// - fontSizeMultiplier: 字体大小倍率（用于合并弹幕）
  void renderItem(
    Canvas canvas,
    GPUDanmakuItem item,
    double x,
    double y,
    double opacity, {
    double scale = 0.5,
    double fontSizeMultiplier = 1.0,
    String? countText,
  }) {
    // 守卫：确保弹幕所需字符都已在图集中
    if (!_fontAtlas.isReady(item.text)) {
      _fontAtlas.addText(item.text);
      return;
    }

    if (countText != null && !_fontAtlas.isReady(countText)) {
      _fontAtlas.addText(countText);
      return;
    }

    final texture = _fontAtlas.atlasTexture;
    if (texture == null) {
      debugPrint('GPU弹幕渲染器: 字体图集纹理未准备好，跳过渲染');
      return;
    }
    
    // 验证纹理的有效性
    if (texture.width <= 0 || texture.height <= 0) {
      debugPrint('GPU弹幕渲染器: 字体图集纹理尺寸无效 (${texture.width}x${texture.height})，跳过渲染');
      return;
    }
    
    final bool needsOpacityLayer = opacity < 1.0;

    // 🔥 修改：仅在需要时创建透明层，增加额外高度以确保字符不被裁剪
    if (needsOpacityLayer) {
      final width = calculateTextWidth(
        item.text + (countText ?? ''),
        scale: scale * fontSizeMultiplier,
      );
      // 🔥 增加额外高度以适应emoji和带descender的字符
      final height = config.fontSize * fontSizeMultiplier * 1.4; // 增加40%的高度缓冲
      canvas.saveLayer(
        Rect.fromLTWH(x, y + 5, width, height), // 向上偏移10%高度
        Paint()..color = Colors.white.withOpacity(opacity),
      );
    }

    // 准备绘制参数
    final strokeTransforms = <RSTransform>[];
    final strokeRects = <Rect>[];
    final strokeColors = <Color>[];

    final fillTransforms = <RSTransform>[];
    final fillRects = <Rect>[];
    final fillColors = <Color>[];

    final double strokeOffset = _getStrokeOffset();
    // 🔥 修改：不再使用withOpacity修改颜色，保持原始颜色
    final shadowColor = _getShadowColor(item.color);
    final fillColor = item.color;

    double currentX = x;

    // 遍历每个字符
    for (var char in item.text.runes) {
      final charStr = String.fromCharCode(char);
      final charInfo = _fontAtlas.getCharRect(charStr);
      if (charInfo == null) {
        debugPrint('GPU弹幕渲染器: 字符 "$charStr" 不在图集中，跳过');
        continue;
      }
      
      // 验证字符矩形的有效性
      if (charInfo.isEmpty || !charInfo.isFinite) {
        debugPrint('GPU弹幕渲染器: 字符 "$charStr" 的矩形无效，跳过');
        continue;
      }

      final adjustedScale = scale * fontSizeMultiplier;
      final charWidthScaled = charInfo.width * adjustedScale;
      final charHeightScaled = charInfo.height * adjustedScale;
      
      // 验证缩放后的尺寸是否有效
      if (!charWidthScaled.isFinite || !charHeightScaled.isFinite || 
          charWidthScaled <= 0 || charHeightScaled <= 0) {
        debugPrint('GPU弹幕渲染器: 字符 "$charStr" 缩放后尺寸无效，跳过');
        continue;
      }
      
      final charCenterX = currentX + charWidthScaled / 2;
      // 🔥 修改：调整字符中心Y坐标，考虑字符图集中的实际高度
      final charCenterY = y + charHeightScaled / 2;
      
      // 验证中心点坐标是否有效
      if (!charCenterX.isFinite || !charCenterY.isFinite) {
        debugPrint('GPU弹幕渲染器: 字符 "$charStr" 中心点坐标无效，跳过');
        continue;
      }

      // 1. 准备描边层参数 (8个方向)
      final offsets = [
        Offset(-strokeOffset, -strokeOffset), Offset(strokeOffset, -strokeOffset),
        Offset(strokeOffset, strokeOffset),   Offset(-strokeOffset, strokeOffset),
        Offset(0, -strokeOffset),             Offset(0, strokeOffset),
        Offset(-strokeOffset, 0),             Offset(strokeOffset, 0),
      ];

      for (final offset in offsets) {
        strokeTransforms.add(RSTransform.fromComponents(
          rotation: 0, scale: adjustedScale,
          anchorX: charInfo.width / 2, anchorY: charInfo.height / 2,
          translateX: charCenterX + offset.dx, translateY: charCenterY + offset.dy,
        ));
        strokeRects.add(charInfo);
        strokeColors.add(shadowColor);
      }

      // 2. 准备填充层参数
      fillTransforms.add(RSTransform.fromComponents(
        rotation: 0, scale: adjustedScale,
        anchorX: charInfo.width / 2, anchorY: charInfo.height / 2,
        translateX: charCenterX, translateY: charCenterY,
      ));
      fillRects.add(charInfo);
      fillColors.add(fillColor);

      currentX += charWidthScaled;
    }

    // --- 绘制合并弹幕数量 ---
    if (countText != null) {
      final countFillTransforms = <RSTransform>[];
      final countFillRects = <Rect>[];
      final countFillColors = <Color>[];
      final countStrokeTransforms = <RSTransform>[];
      final countStrokeRects = <Rect>[];
      final countStrokeColors = <Color>[];
      final countShadowColor = _getShadowColor(Colors.white);

      for (var char in countText.runes) {
        final charStr = String.fromCharCode(char);
        final charInfo = _fontAtlas.getCharRect(charStr);
        if (charInfo == null) {
          debugPrint('GPU弹幕渲染器: 计数字符 "$charStr" 不在图集中，跳过');
          continue;
        }
        
        // 验证字符矩形的有效性
        if (charInfo.isEmpty || !charInfo.isFinite) {
          debugPrint('GPU弹幕渲染器: 计数字符 "$charStr" 的矩形无效，跳过');
          continue;
        }

        final adjustedScale = 0.5 * (25.0 / config.fontSize); // 固定大小
        final charWidthScaled = charInfo.width * adjustedScale;
        final charHeightScaled = charInfo.height * adjustedScale;
        
        // 验证缩放后的尺寸是否有效
        if (!charWidthScaled.isFinite || !charHeightScaled.isFinite || 
            charWidthScaled <= 0 || charHeightScaled <= 0) {
          debugPrint('GPU弹幕渲染器: 计数字符 "$charStr" 缩放后尺寸无效，跳过');
          continue;
        }
        
        final charCenterX = currentX + charWidthScaled / 2;
        final charCenterY = y + charHeightScaled / 2;
        
        // 验证中心点坐标是否有效
        if (!charCenterX.isFinite || !charCenterY.isFinite) {
          debugPrint('GPU弹幕渲染器: 计数字符 "$charStr" 中心点坐标无效，跳过');
          continue;
        }

        final offsets = [
          Offset(-strokeOffset, -strokeOffset), Offset(strokeOffset, -strokeOffset),
          Offset(strokeOffset, strokeOffset),   Offset(-strokeOffset, strokeOffset),
          Offset(0, -strokeOffset),             Offset(0, strokeOffset),
          Offset(-strokeOffset, 0),             Offset(strokeOffset, 0),
        ];

        for (final offset in offsets) {
          countStrokeTransforms.add(RSTransform.fromComponents(
            rotation: 0, scale: adjustedScale,
            anchorX: charInfo.width / 2, anchorY: charInfo.height / 2,
            translateX: charCenterX + offset.dx, translateY: charCenterY + offset.dy,
          ));
          countStrokeRects.add(charInfo);
          countStrokeColors.add(countShadowColor);
        }

        countFillTransforms.add(RSTransform.fromComponents(
          rotation: 0, scale: adjustedScale,
          anchorX: charInfo.width / 2, anchorY: charInfo.height / 2,
          translateX: charCenterX, translateY: charCenterY,
        ));
        countFillRects.add(charInfo);
        countFillColors.add(Colors.white);

        currentX += charWidthScaled;
      }

      strokeTransforms.addAll(countStrokeTransforms);
      strokeRects.addAll(countStrokeRects);
      strokeColors.addAll(countStrokeColors);
      fillTransforms.addAll(countFillTransforms);
      fillRects.addAll(countFillRects);
      fillColors.addAll(countFillColors);
    }


    // 执行绘制
    final paint = Paint()..filterQuality = FilterQuality.low; // 设置采样质量为low，实现抗锯齿

    // 验证参数完整性
    if (strokeTransforms.length != strokeRects.length || 
        strokeTransforms.length != strokeColors.length ||
        fillTransforms.length != fillRects.length ||
        fillTransforms.length != fillColors.length) {
      debugPrint('GPU弹幕渲染器: 参数长度不匹配，跳过渲染');
      if (needsOpacityLayer) {
        canvas.restore();
      }
      return;
    }

    // 第一遍：绘制描边
    if (strokeTransforms.isNotEmpty && _fontAtlas.atlasTexture != null) {
      try {
        canvas.drawAtlas(
          _fontAtlas.atlasTexture!,
          strokeTransforms,
          strokeRects,
          strokeColors,
          BlendMode.modulate,
          null,
          paint,
        );
      } catch (e) {
        debugPrint('GPU弹幕渲染器: 描边渲染失败 - $e');
        // 继续执行，不中断整个渲染流程
      }
    }

    // 第二遍：绘制填充
    if (fillTransforms.isNotEmpty && _fontAtlas.atlasTexture != null) {
      try {
        canvas.drawAtlas(
          _fontAtlas.atlasTexture!,
          fillTransforms,
          fillRects,
          fillColors,
          BlendMode.modulate,
          null,
          paint,
        );
      } catch (e) {
        debugPrint('GPU弹幕渲染器: 填充渲染失败 - $e');
        // 继续执行，不中断整个渲染流程
      }
    }
    
    // 🔥 修改：仅在创建了透明层时恢复画布状态
    if (needsOpacityLayer) {
      canvas.restore();
    }
  }

  /// 批量渲染弹幕项目
  ///
  /// 参数:
  /// - canvas: 画布
  /// - items: 弹幕项目列表
  /// - positions: 对应的位置列表
  /// - opacity: 透明度
  /// - scale: 缩放比例
  void renderBatch(
    Canvas canvas,
    List<GPUDanmakuItem> items,
    List<Offset> positions,
    double opacity, {
    double scale = 0.5,
  }) {
    if (items.length != positions.length) {
      throw ArgumentError('Items and positions must have the same length');
    }

    // 🔥 新增：如果透明度小于1.0，为整个批量渲染创建透明层
    if (opacity < 1.0) {
      // 计算整个批量渲染的边界
      double minX = double.infinity;
      double minY = double.infinity;
      double maxX = -double.infinity;
      double maxY = -double.infinity;
      
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final position = positions[i];
        final textWidth = calculateTextWidth(item.text, scale: scale);
        // 🔥 修改：增加额外高度以适应emoji和带descender的字符
        final textHeight = config.fontSize * 1.4; // 增加40%的高度缓冲
        
        minX = math.min(minX, position.dx);
        minY = math.min(minY, position.dy - textHeight * 0.1); // 向上偏移10%高度
        maxX = math.max(maxX, position.dx + textWidth);
        maxY = math.max(maxY, position.dy + textHeight);
      }
      
      // 创建透明层
      canvas.saveLayer(
        Rect.fromLTWH(minX, minY, maxX - minX, maxY - minY),
        Paint()..color = Colors.white.withOpacity(opacity),
      );
    }

    for (int i = 0; i < items.length; i++) {
      renderItem(
        canvas,
        items[i],
        positions[i].dx,
        positions[i].dy,
        1.0, // 🔥 修改：传递1.0，因为透明度已经在批量层处理
        scale: scale,
      );
    }
    
    // 🔥 新增：恢复画布状态
    if (opacity < 1.0) {
      canvas.restore();
    }
  }

  /// 计算弹幕文本的实际渲染宽度
  ///
  /// 使用字体图集中的字符信息计算，比TextPainter更准确
  double calculateTextWidth(String text, {double scale = 0.5}) {
    if (_fontAtlas.atlasTexture == null) return 0.0;
    
    double width = 0.0;
    for (var char in text.runes) {
      final charStr = String.fromCharCode(char);
      final charInfo = _fontAtlas.getCharRect(charStr);
      if (charInfo != null) {
        width += charInfo.width * scale;
      }
    }
    return width;
  }

  /// 检查文本是否可以渲染（所有字符都在图集中）
  bool canRender(String text) {
    return _fontAtlas.isReady(text);
  }

  /// 添加文本到字体图集
  void addTextToAtlas(String text) {
    _fontAtlas.addText(text);
  }
}

class _GpuDanmakuPainter extends CustomPainter {
  final GpuDanmakuTextRenderer renderer;
  final GPUDanmakuItem item;
  final double opacity;
  final double fontSizeMultiplier;
  final String? countText;

  _GpuDanmakuPainter({
    required this.renderer,
    required this.item,
    required this.opacity,
    required this.fontSizeMultiplier,
    this.countText,
  });

  @override
  void paint(Canvas canvas, Size size) {
    renderer.renderItem(
      canvas,
      item,
      0, // x
      0, // y
      opacity,
      fontSizeMultiplier: fontSizeMultiplier,
      countText: countText,
    );
  }

  @override
  bool shouldRepaint(covariant _GpuDanmakuPainter oldDelegate) {
    return oldDelegate.item != item ||
        oldDelegate.opacity != opacity ||
        oldDelegate.fontSizeMultiplier != fontSizeMultiplier ||
        oldDelegate.countText != countText;
  }
} 