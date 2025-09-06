import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/danmaku_content_item.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

class Utils {
  static generateParagraph(DanmakuContentItem content, double danmakuWidth,
      double fontSize, int fontWeight) {
    final ui.ParagraphBuilder builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontSize: fontSize,
      fontWeight: FontWeight.values[fontWeight],
      textDirection: TextDirection.ltr,
    ))
      ..pushStyle(ui.TextStyle(
        color: content.color,
      ))
      ..addText(content.text);
    return builder.build()
      ..layout(ui.ParagraphConstraints(width: danmakuWidth));
  }

  static generateStrokeParagraph(DanmakuContentItem content,
      double danmakuWidth, double fontSize, int fontWeight) {
    // 计算弹幕颜色的亮度，与其他内核保持一致
    final color = content.color;
    final luminance =
        (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) / 255;
    // 如果亮度小于0.2，说明是深色，使用白色描边；否则使用黑色描边
    final strokeColor = luminance < 0.2 ? Colors.white : Colors.black;
    
    final Paint strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = globals.strokeWidth * 2.5  // 使用与其他内核一致的描边粗细
      ..color = strokeColor;  // 使用动态描边颜色

    final ui.ParagraphBuilder strokeBuilder =
        ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontSize: fontSize,
      fontWeight: FontWeight.values[fontWeight],
      textDirection: TextDirection.ltr,
    ))
          ..pushStyle(ui.TextStyle(
            foreground: strokePaint,
          ))
          ..addText(content.text);

    return strokeBuilder.build()
      ..layout(ui.ParagraphConstraints(width: danmakuWidth));
  }
}
