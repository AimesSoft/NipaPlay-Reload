import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'danmaku_content_item.dart';
import 'danmaku_item.dart';
import '../../utils/globals.dart' as globals;

class Utils {
  // 根据文字颜色判断使用的描边颜色，与 NipaPlay 保持一致
  static Color getShadowColor(Color textColor) {
    // 计算亮度，与 NipaPlay 的算法保持一致
    final luminance = (0.299 * textColor.red + 0.587 * textColor.green + 0.114 * textColor.blue) / 255;
    // 如果亮度小于0.2，说明是深色，使用白色描边；否则使用黑色描边
    return luminance < 0.2 ? Colors.white : Colors.black;
  }

  // 获取描边偏移量，与 NipaPlay 保持一致
  static double getStrokeOffset() {
    // 统一使用1.0像素偏移，与 NipaPlay 保持一致
    return 1.0;
  }

  /// 计算弹幕的准确碰撞箱边界
  static Rect calculateCollisionBox(DanmakuItem item, double fontSize) {
    // 如果paragraph存在，使用实际的text metrics
    if (item.paragraph != null) {
      // 使用paragraph的尺寸而不是getBoxesForRange
      // 因为getBoxesForRange可能不能正确处理完整的文本范围
      final paragraphWidth = item.paragraph!.width;
      final paragraphHeight = item.paragraph!.height;
      
      // 但如果paragraph的width不准确，还是尝试使用getBoxesForRange
      if (paragraphWidth > 0 && paragraphHeight > 0) {
        return Rect.fromLTWH(
          item.xPosition,
          item.yPosition,
          paragraphWidth,
          paragraphHeight,
        );
      }
      
      // 如果paragraph尺寸不可用，尝试使用getBoxesForRange
      try {
        final textBox = item.paragraph!.getBoxesForRange(0, item.content.text.length);
        if (textBox.isNotEmpty) {
          // 使用实际的文本边界框
          final box = textBox.first;
          return Rect.fromLTWH(
            item.xPosition + box.left,
            item.yPosition + box.top,
            box.right - box.left,
            box.bottom - box.top,
          );
        }
      } catch (e) {
        // 如果getBoxesForRange失败，继续使用估算方法
      }
    }
    
    // 如果没有paragraph或者paragraph方法失败，使用更准确的估算
    // 使用TextPainter来测量文本的实际宽度
    final textPainter = TextPainter(
      text: TextSpan(
        text: item.content.text,
        style: TextStyle(
          fontSize: fontSize,
          color: item.content.color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    
    return Rect.fromLTWH(
      item.xPosition,
      item.yPosition,
      textPainter.width,
      textPainter.height,
    );
  }

  /// 绘制碰撞箱（半透明纯色）
  static void drawCollisionBox(Canvas canvas, Rect collisionBox, Color danmakuColor) {
    // 使用弹幕颜色的半透明版本作为碰撞箱颜色
    final boxColor = danmakuColor.withOpacity(0.3);
    
    // 绘制碰撞箱填充
    final paint = Paint()
      ..color = boxColor
      ..style = PaintingStyle.fill;
    
    canvas.drawRect(collisionBox, paint);
    
    // 绘制碰撞箱边框
    final borderPaint = Paint()
      ..color = danmakuColor.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    
    canvas.drawRect(collisionBox, borderPaint);
  }

  /// 绘制碰撞箱信息文本（可选）
  static void drawCollisionBoxInfo(Canvas canvas, Rect collisionBox, DanmakuItem item) {
    // 创建信息文本，显示弹幕的基本信息
    final infoText = 'W:${item.width.toStringAsFixed(1)}, '
        'X:${item.xPosition.toStringAsFixed(1)}, '
        'Y:${item.yPosition.toStringAsFixed(1)}';
    
    final textPainter = TextPainter(
      text: TextSpan(
        text: infoText,
        style: TextStyle(
          color: Colors.white,
          fontSize: 8,
          backgroundColor: Colors.black54,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    
    // 在碰撞箱上方绘制信息
    final infoOffset = Offset(
      collisionBox.left,
      collisionBox.top - textPainter.height - 2,
    );
    
    // 确保信息文本不会超出屏幕
    final adjustedOffset = Offset(
      infoOffset.dx.clamp(0, double.infinity),
      infoOffset.dy.clamp(0, double.infinity),
    );
    
    textPainter.paint(canvas, adjustedOffset);
  }

  /// 绘制轨道编号
  static void drawTrackNumber(Canvas canvas, DanmakuItem item, int trackIndex) {
    final trackText = 'T$trackIndex';
    
    final textPainter = TextPainter(
      text: TextSpan(
        text: trackText,
        style: TextStyle(
          color: Colors.yellow,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black54,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    
    // 在弹幕左侧绘制轨道编号
    final trackOffset = Offset(
      item.xPosition - textPainter.width - 8, // 在弹幕左侧留一点间距
      item.yPosition,
    );
    
    // 确保轨道编号不会超出屏幕左边界
    final adjustedOffset = Offset(
      trackOffset.dx.clamp(0, double.infinity),
      trackOffset.dy.clamp(0, double.infinity),
    );
    
    textPainter.paint(canvas, adjustedOffset);
  }

  static generateParagraph(DanmakuContentItem content, double danmakuWidth, double fontSize) {
    // 获取描边颜色
    final shadowColor = getShadowColor(content.color);
    final strokeOffset = getStrokeOffset();

    final ui.ParagraphBuilder builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontSize: fontSize,
      textDirection: TextDirection.ltr,
    ))
      ..pushStyle(ui.TextStyle(
        color: content.color,
        shadows: [
          // 八个方向的描边，与 NipaPlay 保持一致
          ui.Shadow(offset: Offset(-strokeOffset, -strokeOffset), blurRadius: 0, color: shadowColor), // 左上
          ui.Shadow(offset: Offset(strokeOffset, -strokeOffset), blurRadius: 0, color: shadowColor),  // 右上
          ui.Shadow(offset: Offset(strokeOffset, strokeOffset), blurRadius: 0, color: shadowColor),   // 右下
          ui.Shadow(offset: Offset(-strokeOffset, strokeOffset), blurRadius: 0, color: shadowColor),  // 左下
          ui.Shadow(offset: Offset(0, -strokeOffset), blurRadius: 0, color: shadowColor),  // 上
          ui.Shadow(offset: Offset(0, strokeOffset), blurRadius: 0, color: shadowColor),   // 下
          ui.Shadow(offset: Offset(-strokeOffset, 0), blurRadius: 0, color: shadowColor),  // 左
          ui.Shadow(offset: Offset(strokeOffset, 0), blurRadius: 0, color: shadowColor),   // 右
        ],
      ))
      ..addText(content.text);

    return builder.build()
      ..layout(ui.ParagraphConstraints(width: danmakuWidth));
  }
}