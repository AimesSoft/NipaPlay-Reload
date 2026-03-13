import 'package:flutter/material.dart';

class DanmakuColorPresets {
  DanmakuColorPresets._();

  /// 发送弹幕对话框里的预设颜色
  static const List<Color> sendPresetColors = <Color>[
    Color(0xFFfe0502),
    Color(0xFFff7106),
    Color(0xFFffaa01),
    Color(0xFFffd301),
    Color(0xFFffff00),
    Color(0xFFa0ee02),
    Color(0xFF04cd00),
    Color(0xFF019899),
    Color(0xFF4266be),
    Color(0xFF89d5ff),
    Color(0xFFcc0173),
    Color(0xFF000000),
    Color(0xFF222222),
    Color(0xFF9b9b9b),
    Color(0xFFffffff),
  ];

  /// 随机染色可选的彩色集合（排除黑白灰）
  static const List<Color> randomColorfulDanmakuColors = <Color>[
    Color(0xFFfe0502),
    Color(0xFFff7106),
    Color(0xFFffaa01),
    Color(0xFFffd301),
    Color(0xFFffff00),
    Color(0xFFa0ee02),
    Color(0xFF04cd00),
    Color(0xFF019899),
    Color(0xFF4266be),
    Color(0xFF89d5ff),
    Color(0xFFcc0173),
  ];

  static String toRgbString(Color color) {
    final r = (color.r * 255.0).round().clamp(0, 255);
    final g = (color.g * 255.0).round().clamp(0, 255);
    final b = (color.b * 255.0).round().clamp(0, 255);
    return 'rgb($r,$g,$b)';
  }
}
