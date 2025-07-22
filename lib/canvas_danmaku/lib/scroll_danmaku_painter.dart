import 'package:flutter/material.dart';
import 'danmaku_item.dart';
import 'danmaku_option.dart';

class ScrollDanmakuPainter extends CustomPainter {
  final double value;
  final List<DanmakuItem> items;
  final int duration;
  final double fontSize;
  final bool showStroke;
  final double danmakuHeight;
  final bool running;
  final int tick;
  final bool showCollisionBoxes;
  final bool showTrackNumbers;
  final List<double> trackYPositions;
  final DanmakuOption option;

  ScrollDanmakuPainter(
    this.value,
    this.items,
    this.duration,
    this.fontSize,
    this.showStroke,
    this.danmakuHeight,
    this.running,
    this.tick,
    this.showCollisionBoxes,
    this.showTrackNumbers,
    this.trackYPositions, {
    required this.option,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制轨道编号
    if (showTrackNumbers) {
      final textPainter = TextPainter(
        textDirection: TextDirection.ltr,
      );
      final textStyle = TextStyle(
        color: Colors.white.withOpacity(0.5),
        fontSize: fontSize * 0.8,
      );

      for (int i = 0; i < trackYPositions.length; i++) {
        textPainter.text = TextSpan(
          text: 'Track $i',
          style: textStyle,
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(10, trackYPositions[i]));
      }
    }

    for (DanmakuItem item in items) {
      if (item.paragraph == null) continue;

      // 🔥 关键优化：弹幕运动时间计算
      // 确保弹幕速度恒定，无论动画控制器的duration如何
      double progress = (tick - item.creationTime) / (duration * 1000);
      if (progress < 0 || progress > 1) continue;

      // 🔥 关键优化：弹幕位置计算
      double screenWidth = size.width;
      double danmakuWidth = item.width;
      double totalDistance = screenWidth + danmakuWidth;
      
      // 计算弹幕当前位置 - 确保匀速运动
      double x = screenWidth - (progress * totalDistance);
      
      // 保存当前位置，以便其他功能使用（如碰撞检测）
      item.xPosition = x;

      // 绘制碰撞箱
      if (showCollisionBoxes) {
        final paint = Paint()
          ..color = Colors.red.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        
        canvas.drawRect(
          Rect.fromLTWH(x, item.yPosition, item.width, danmakuHeight),
          paint,
        );
      }

      // 绘制弹幕文本
      canvas.drawParagraph(
        item.paragraph!,
        Offset(x, item.yPosition),
      );
    }
  }

  @override
  bool shouldRepaint(ScrollDanmakuPainter oldDelegate) {
    // 🔥 关键修复：无论是否在运行状态，都应该重绘
    // 原因：即使在暂停状态，也需要保持弹幕在正确位置显示
    // 特别是在新添加弹幕或弹幕状态变化时，需要立即显示
    return oldDelegate.value != value || 
           oldDelegate.tick != tick ||
           items.length != oldDelegate.items.length;
  }
}