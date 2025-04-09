import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'danmaku_content_item.dart';
import 'dart:io'; // 用于检测平台

// 返回根据平台的描边偏移值
double getStrokeOffset() {
  if (Platform.isIOS || Platform.isAndroid) {
    return 1.0; // iOS 和 Android 使用较小的偏移
  } else {
    return 1.5; // 其他平台使用较大的偏移
  }
}

class Utils {
  // 根据文字颜色判断使用的描边颜色
  static Color getShadowColor(Color textColor) {
    // 计算颜色的亮度
    final luminance = textColor.computeLuminance();
    
    // 如果亮度低于0.2，认为是接近黑色，使用白色描边
    if (luminance < 0.1) {
      return Colors.white;
    }
    
    // 否则使用黑色描边
    return Colors.black;
  }

  static generateParagraph(DanmakuContentItem content, double danmakuWidth, double fontSize) {
    // 获取描边颜色
    final shadowColor = getShadowColor(content.color);
    final strokeOffset = getStrokeOffset(); // 动态获取偏移量

    final ui.ParagraphBuilder builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontSize: fontSize,
      textDirection: TextDirection.ltr,
    ))
      ..pushStyle(ui.TextStyle(
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
      ))
      ..addText(content.text);

    return builder.build()
      ..layout(ui.ParagraphConstraints(width: danmakuWidth));
  }
}