import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'danmaku_item.dart';
import 'utils.dart';
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

      double progress = (tick - item.creationTime) / (duration * 1000);
      if (progress < 0 || progress > 1) continue;

      // 修正弹幕运动逻辑
      double x = size.width - (size.width + item.width) * progress;

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

      // 更新弹幕实际位置（用于碰撞检测）
      item.xPosition = x;
    }
  }

  @override
  bool shouldRepaint(ScrollDanmakuPainter oldDelegate) {
    return oldDelegate.value != value;
  }
}