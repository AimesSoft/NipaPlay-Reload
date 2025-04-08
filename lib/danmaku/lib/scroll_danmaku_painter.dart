import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'danmaku_item.dart';
import 'utils.dart';

class ScrollDanmakuPainter extends CustomPainter {
  final double progress;
  final List<DanmakuItem> scrollDanmakuItems;
  final int danmakuDurationInSeconds;
  final double fontSize;
  final bool showStroke;  // 可以移除这个字段
  final double danmakuHeight;
  final bool running;
  final int tick;
  final int batchThreshold;

  final double totalDuration;

  ScrollDanmakuPainter(
    this.progress,
    this.scrollDanmakuItems,
    this.danmakuDurationInSeconds,
    this.fontSize,
    this.showStroke, // 也可以移除这个参数
    this.danmakuHeight,
    this.running,
    this.tick, {
    this.batchThreshold = 10, // 默认值为10，可以自行调整
  }) : totalDuration = danmakuDurationInSeconds * 1000;

  @override
  void paint(Canvas canvas, Size size) {
    final startPosition = size.width;

    if (scrollDanmakuItems.length > batchThreshold) {
      // 弹幕数量超过阈值时使用批量绘制
      final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
      final Canvas pictureCanvas = Canvas(pictureRecorder);

      for (var item in scrollDanmakuItems) {
        final elapsedTime = tick - item.creationTime;
        final endPosition = -item.width;
        final distance = startPosition - endPosition;

        item.xPosition =
            startPosition - (elapsedTime / totalDuration) * distance;

        if (item.xPosition < -item.width || item.xPosition > size.width) {
          continue;
        }

        // 生成带阴影的段落（包含描边）
        item.paragraph ??= Utils.generateParagraph(item.content, size.width, fontSize);

        // 绘制段落
        pictureCanvas.drawParagraph(
            item.paragraph!, Offset(item.xPosition, item.yPosition));
      }

      final ui.Picture picture = pictureRecorder.endRecording();
      canvas.drawPicture(picture);
    } else {
      // 弹幕数量较少时直接绘制 (节约创建 canvas 的开销)
      for (var item in scrollDanmakuItems) {
        final elapsedTime = tick - item.creationTime;
        final endPosition = -item.width;
        final distance = startPosition - endPosition;

        item.xPosition =
            startPosition - (elapsedTime / totalDuration) * distance;

        if (item.xPosition < -item.width || item.xPosition > size.width) {
          continue;
        }

        // 生成带阴影的段落（包含描边）
        item.paragraph ??= Utils.generateParagraph(item.content, size.width, fontSize);

        // 绘制段落
        canvas.drawParagraph(
            item.paragraph!, Offset(item.xPosition, item.yPosition));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return running;
  }
}