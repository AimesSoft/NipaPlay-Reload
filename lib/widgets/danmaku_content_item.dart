import 'package:flutter/material.dart';

enum DanmakuItemType {
  scroll,
  top,
  bottom,
}

class DanmakuContentItem {
  /// 弹幕文本
  final String text;

  /// 弹幕颜色
  final Color color;

  /// 弹幕类型
  final DanmakuItemType type;
  
  /// 字体大小倍率
  final double fontSizeMultiplier;
  
  /// 合并弹幕的计数文本（如 x15），为 null 表示不是合并弹幕
  final String? countText;
  
  DanmakuContentItem(
    this.text, {
    this.color = Colors.white,
    this.type = DanmakuItemType.scroll,
    this.fontSizeMultiplier = 1.0,
    this.countText,
  });
}
