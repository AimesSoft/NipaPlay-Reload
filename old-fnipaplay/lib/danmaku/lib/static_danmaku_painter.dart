import 'package:flutter/material.dart';
import 'danmaku_item.dart';
import 'utils.dart';

class StaticDanmakuPainter extends CustomPainter {
  final double progress;
  final List<DanmakuItem> topDanmakuItems;
  final List<DanmakuItem> buttomDanmakuItems;
  final int danmakuDurationInSeconds;
  final double fontSize;
  final bool showStroke;
  final double danmakuHeight;
  final bool running;
  final int tick;

  StaticDanmakuPainter(
      this.progress,
      this.topDanmakuItems,
      this.buttomDanmakuItems,
      this.danmakuDurationInSeconds,
      this.fontSize,
      this.showStroke,
      this.danmakuHeight,
      this.running,
      this.tick);

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制顶部弹幕
    for (var item in topDanmakuItems) {
      item.xPosition = (size.width - item.width) / 2;
      // 如果 Paragraph 没有缓存，则创建并缓存它
      item.paragraph ??= Utils.generateParagraph(item.content, size.width, fontSize);

      // 绘制文字（包括阴影）
      canvas.drawParagraph(item.paragraph!, Offset(item.xPosition, item.yPosition));
    }

    // 绘制底部弹幕 (翻转绘制)
    for (var item in buttomDanmakuItems) {
      item.xPosition = (size.width - item.width) / 2;
      // 如果 Paragraph 没有缓存，则创建并缓存它
      item.paragraph ??= Utils.generateParagraph(item.content, size.width, fontSize);

      // 绘制文字（包括阴影）
      canvas.drawParagraph(
          item.paragraph!, Offset(item.xPosition, size.height - item.yPosition - danmakuHeight));
    }
  }

  @override
  bool shouldRepaint(covariant StaticDanmakuPainter oldDelegate) {
    return running;
  }
}