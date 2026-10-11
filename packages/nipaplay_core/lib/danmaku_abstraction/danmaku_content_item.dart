import 'dart:ui' show Color;

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
  
  /// 字体大小倍率（用于合并弹幕）
  final double fontSizeMultiplier;
  
  /// 合并弹幕的计数文本（如 x15），为 null 表示不是合并弹幕
  final String? countText;
  
  /// 滚动弹幕的初始X坐标
  final double? scrollOriginalX;

  /// 是否是用户自己发送的弹幕
  final bool isMe;

  DanmakuContentItem(
    this.text, {
    this.color = const Color(0xFFFFFFFF),
    this.type = DanmakuItemType.scroll,
    this.timeOffset = 0,
    this.trackIndex, // 🔥 新增：轨道编号
    this.fontSizeMultiplier = 1.0,
    this.countText,
    this.scrollOriginalX,
    this.isMe = false,
  });
}
