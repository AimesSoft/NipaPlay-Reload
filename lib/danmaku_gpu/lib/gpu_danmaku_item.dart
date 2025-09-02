import 'package:flutter/material.dart';
import '../../danmaku_abstraction/danmaku_content_item.dart';

/// GPU弹幕项目
/// 
/// 通用的弹幕项目类，支持不同类型的弹幕（顶部、滚动、底部）
class GPUDanmakuItem {
  final String text;
  final Color color;
  final DanmakuItemType type;
  final int timeOffset;
  final int createdAt;
  
  /// 轨道ID，-1表示尚未分配轨道
  int trackId = -1;
  
  /// 弹幕的实际显示位置（用于滚动弹幕）
  double? currentX;
  double? currentY;
  
  /// 滚动弹幕的初始X坐标
  double? scrollOriginalX;
  
  /// 弹幕的目标位置（用于动画）
  double? targetX;
  double? targetY;
  
  /// 弹幕的文本宽度（缓存，避免重复计算）
  double? _textWidth;
  
  /// 合并弹幕相关属性
  bool isMerged = false;
  int mergeCount = 1;
  bool isFirstInGroup = true;
  String? groupContent;
  
  /// 字体大小倍率
  double fontSizeMultiplier = 1.0;
  
  /// 计数文本
  String? countText;
  
  GPUDanmakuItem({
    required this.text,
    required this.color,
    required this.type,
    required this.timeOffset,
    required this.createdAt,
    this.currentX,
    this.currentY,
    this.targetX,
    this.targetY,
    this.isMerged = false,
    this.mergeCount = 1,
    this.isFirstInGroup = true,
    this.groupContent,
    this.fontSizeMultiplier = 1.0,
    this.countText,
    this.scrollOriginalX,
  });

  /// 获取文本宽度（缓存计算结果）
  double getTextWidth(double fontSize) {
    if (_textWidth == null) {
      _textWidth = _calculateTextWidth(text, fontSize);
    }
    return _textWidth!;
  }

  /// 计算文本宽度
  static double _calculateTextWidth(String text, double fontSize) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        locale:Locale("zh","CN"),
style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.normal,
          fontFeatures: const [FontFeature.proportionalFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    return textPainter.width;
  }

  /// 从DanmakuContentItem创建GPUDanmakuItem
  static GPUDanmakuItem fromDanmakuContentItem(
    DanmakuContentItem item,
    int createdAt,
  ) {
    return GPUDanmakuItem(
      text: item.text,
      color: item.color,
      type: item.type,
      timeOffset: item.timeOffset,
      createdAt: createdAt,
      fontSizeMultiplier: item.fontSizeMultiplier,
      countText: item.countText,
      scrollOriginalX: item.scrollOriginalX,
    );
  }

  /// 检查弹幕是否已过期
  bool isExpired(int currentTime, int durationMs) {
    return (currentTime - createdAt + timeOffset) > durationMs;
  }

  /// 检查弹幕是否应该显示
  bool shouldShow(int currentTime) {
    final elapsed = currentTime - createdAt + timeOffset;
    return elapsed >= 0;
  }

  /// 获取弹幕经过的时间（毫秒）
  int getElapsedTime(int currentTime) {
    return currentTime - createdAt + timeOffset;
  }

  /// 获取弹幕显示的进度（0.0-1.0）
  double getProgress(int currentTime, int durationMs) {
    final elapsed = getElapsedTime(currentTime);
    if (elapsed < 0) return 0.0;
    return (elapsed / durationMs).clamp(0.0, 1.0);
  }

  /// 重置轨道分配
  void resetTrack() {
    trackId = -1;
  }

  /// 重置文本宽度缓存
  void resetTextWidthCache() {
    _textWidth = null;
  }

  @override
  String toString() {
    return 'GPUDanmakuItem(text: "$text", type: $type, trackId: $trackId)';
  }
} 