import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'danmaku_content_item.dart';
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