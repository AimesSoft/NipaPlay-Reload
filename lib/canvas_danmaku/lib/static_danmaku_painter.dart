import 'package:flutter/material.dart';
import 'danmaku_item.dart';
import 'danmaku_option.dart';

class StaticDanmakuPainter extends CustomPainter {
  final double value;
  final List<DanmakuItem> topItems;
  final List<DanmakuItem> bottomItems;
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

  StaticDanmakuPainter(
    this.value,
    this.topItems,
    this.bottomItems,
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

    // 绘制顶部弹幕
    for (DanmakuItem item in topItems) {
      if (item.paragraph == null) continue;

      // 检查是否在显示时间内
      int elapsedTime = tick - item.creationTime;
      if (elapsedTime < 0 || elapsedTime > 5000) continue;

      // 绘制碰撞箱
      if (showCollisionBoxes) {
        final paint = Paint()
          ..color = Colors.red.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        
        canvas.drawRect(
          Rect.fromLTWH(item.xPosition, item.yPosition, item.width, danmakuHeight),
          paint,
        );
      }

      // 绘制弹幕文本
      canvas.drawParagraph(
        item.paragraph!,
        Offset(item.xPosition, item.yPosition),
      );
    }

    // 绘制底部弹幕
    for (DanmakuItem item in bottomItems) {
      if (item.paragraph == null) continue;

      // 检查是否在显示时间内
      int elapsedTime = tick - item.creationTime;
      if (elapsedTime < 0 || elapsedTime > 5000) continue;

      // 绘制碰撞箱
      if (showCollisionBoxes) {
        final paint = Paint()
          ..color = Colors.red.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        
        canvas.drawRect(
          Rect.fromLTWH(item.xPosition, item.yPosition, item.width, danmakuHeight),
          paint,
        );
      }

      // 绘制弹幕文本
      canvas.drawParagraph(
        item.paragraph!,
        Offset(item.xPosition, item.yPosition),
      );
    }
  }

  @override
  bool shouldRepaint(StaticDanmakuPainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.tick != tick;
  }
}