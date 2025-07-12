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
  
  /// 🔥 新增：时间偏移（毫秒），用于时间轴跳转后的运动中途弹幕
  final int timeOffset;
  
  /// 🔥 新增：轨道编号，用于状态恢复时强制使用相同轨道
  final int? trackIndex;
  
  DanmakuContentItem(
    this.text, {
    this.color = Colors.white,
    this.type = DanmakuItemType.scroll,
    this.timeOffset = 0,
    this.trackIndex, // 🔥 新增：轨道编号
  });
}
