import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'danmaku_content_item.dart';
import 'dart:io'; // 用于检测平台

// 返回根据平台的描边偏移值
double getStrokeOffset() {
    return 1.0; 
}

class Utils {
  // 根据文字颜色判断使用的描边颜色，与nipaPlay内核保持一致
  static Color getShadowColor(Color textColor, Color? strokeColor) {
    if (strokeColor != null) {
      return strokeColor;
    }
    
    // 特殊处理：纯黑色文本总是使用白色描边
    if (textColor.value == Colors.black.value || 
        textColor.value == const Color(0xFF000000).value) {
      return Colors.white;
    }
    
    // 计算亮度，与nipaPlay内核保持一致
    final luminance = (0.299 * textColor.red + 0.587 * textColor.green + 0.114 * textColor.blue) / 255;
    
    return luminance < 0.2 ? Colors.white : Colors.black;
  }

  static generateParagraph(
    DanmakuContentItem content, 
    double danmakuWidth, 
    double fontSize, {
    bool showStroke = true,
    double strokeWidth = 1.0,
    Color? strokeColor,
  }) {
    final ui.ParagraphBuilder builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontSize: fontSize,
      textDirection: TextDirection.ltr,
    ));

    if (showStroke) {
      // 获取描边颜色
      final shadowColor = getShadowColor(content.color, strokeColor);
      final strokeOffset = strokeWidth * getStrokeOffset(); // 动态获取偏移量，与nipaPlay内核保持一致

      builder.pushStyle(ui.TextStyle(
        color: content.color,
        shadows: [
          ui.Shadow(offset: Offset(-strokeOffset, -strokeOffset), color: shadowColor), // 左上
          ui.Shadow(offset: Offset(strokeOffset, -strokeOffset), color: shadowColor),  // 右上
          ui.Shadow(offset: Offset(-strokeOffset, strokeOffset), color: shadowColor),  // 左下
          ui.Shadow(offset: Offset(strokeOffset, strokeOffset), color: shadowColor),   // 右下
          ui.Shadow(offset: Offset(0, -strokeOffset), color: shadowColor),  // 上
          ui.Shadow(offset: Offset(0, strokeOffset), color: shadowColor),   // 下
          ui.Shadow(offset: Offset(-strokeOffset, 0), color: shadowColor),  // 左
          ui.Shadow(offset: Offset(strokeOffset, 0), color: shadowColor),   // 右
        ],
      ));
    } else {
      builder.pushStyle(ui.TextStyle(
        color: content.color,
      ));
    }

    builder.addText(content.text);

    return builder.build()
      ..layout(ui.ParagraphConstraints(width: danmakuWidth));
  }
}