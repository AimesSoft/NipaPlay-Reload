import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'danmaku_item.dart';
import 'utils.dart';
import 'danmaku_option.dart'; // 🔥 添加导入

class ScrollDanmakuPainter extends CustomPainter {
  final double progress;
  final List<DanmakuItem> scrollDanmakuItems;
  final int danmakuDurationInSeconds;
  final double fontSize;
  final bool showStroke;  // 可以移除这个字段
  final double danmakuHeight;
  final bool running;
  final int tick;
  final bool isPaused; // 🔥 新增：暂停状态
  final int batchThreshold;
  final DanmakuOption option; // 🔥 新增：弹幕选项

  final double totalDuration;

  ScrollDanmakuPainter(
    this.progress,
    this.scrollDanmakuItems,
    this.danmakuDurationInSeconds,
    this.fontSize,
    this.showStroke, // 也可以移除这个参数
    this.danmakuHeight,
    this.running,
    this.tick,
    this.isPaused, // 🔥 新增：暂停状态参数
    this.option, // 🔥 新增：弹幕选项参数
    {
    this.batchThreshold = 10, // 默认值为10，可以自行调整
  }) : totalDuration = danmakuDurationInSeconds * 1000;

  @override
  void paint(Canvas canvas, Size size) {
    final startPosition = size.width;
    
    // 🔥 关键修改：如果隐藏滚动弹幕，则不绘制，但仍然更新弹幕位置以保持状态一致
    if (option.hideScroll) {
      // 仍然更新弹幕位置，保持状态一致，这样重新显示时弹幕能从正确位置继续
      for (var item in scrollDanmakuItems) {
        if (!isPaused) {
          final elapsedTime = tick - item.creationTime;
          final endPosition = -item.width;
          final distance = startPosition - endPosition;
          
          item.xPosition = startPosition - (elapsedTime / totalDuration) * distance;
        }
      }
      return; // 不绘制，直接返回
    }

    if (scrollDanmakuItems.length > batchThreshold) {
      // 弹幕数量超过阈值时使用批量绘制
      final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
      final Canvas pictureCanvas = Canvas(pictureRecorder);

      for (var item in scrollDanmakuItems) {
        // 🔥 关键修改：只有在未暂停时才更新位置
        if (!isPaused) {
          final elapsedTime = tick - item.creationTime;
          final endPosition = -item.width;
          final distance = startPosition - endPosition;

          item.xPosition =
              startPosition - (elapsedTime / totalDuration) * distance;
        }

        if (item.xPosition < -item.width || item.xPosition > size.width) {
          continue;
        }

        // 生成带阴影的段落（包含描边）
        item.paragraph ??= Utils.generateParagraph(item.content, size.width, fontSize);

        // 绘制段落
        pictureCanvas.drawParagraph(
            item.paragraph!, Offset(item.xPosition, item.yPosition));
            
        // 🔥 新增：绘制碰撞箱（如果启用）
        if (option.showCollisionBoxes) {
          final collisionBox = Utils.calculateCollisionBox(item, fontSize);
          Utils.drawCollisionBox(pictureCanvas, collisionBox, item.content.color);
          // 可选：绘制碰撞箱信息
          // Utils.drawCollisionBoxInfo(pictureCanvas, collisionBox, item);
        }
        
        // 🔥 新增：绘制轨道编号（如果启用）
        if (option.showTrackNumbers) {
          // 基于Y位置计算轨道编号
          final trackHeight = danmakuHeight + 10.0; // 轨道高度 = 弹幕高度 + 垂直间距
          final trackIndex = ((item.yPosition - 10.0) / trackHeight).floor(); // 减去垂直间距
          Utils.drawTrackNumber(pictureCanvas, item, trackIndex);
        }
      }

      final ui.Picture picture = pictureRecorder.endRecording();
      canvas.drawPicture(picture);
    } else {
      // 弹幕数量较少时直接绘制 (节约创建 canvas 的开销)
      for (var item in scrollDanmakuItems) {
        // 🔥 关键修改：只有在未暂停时才更新位置
        if (!isPaused) {
          final elapsedTime = tick - item.creationTime;
          final endPosition = -item.width;
          final distance = startPosition - endPosition;

          item.xPosition =
              startPosition - (elapsedTime / totalDuration) * distance;
        }

        if (item.xPosition < -item.width || item.xPosition > size.width) {
          continue;
        }

        // 生成带阴影的段落（包含描边）
        item.paragraph ??= Utils.generateParagraph(item.content, size.width, fontSize);

        // 绘制段落
        canvas.drawParagraph(
            item.paragraph!, Offset(item.xPosition, item.yPosition));
            
        // 🔥 新增：绘制碰撞箱（如果启用）
        if (option.showCollisionBoxes) {
          final collisionBox = Utils.calculateCollisionBox(item, fontSize);
          Utils.drawCollisionBox(canvas, collisionBox, item.content.color);
          // 可选：绘制碰撞箱信息
          // Utils.drawCollisionBoxInfo(canvas, collisionBox, item);
        }
        
        // 🔥 新增：绘制轨道编号（如果启用）
        if (option.showTrackNumbers) {
          // 基于Y位置计算轨道编号
          final trackHeight = danmakuHeight + 10.0; // 轨道高度 = 弹幕高度 + 垂直间距
          final trackIndex = ((item.yPosition - 10.0) / trackHeight).floor(); // 减去垂直间距
          Utils.drawTrackNumber(canvas, item, trackIndex);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    // 🔥 关键修改：只有在运行状态且未暂停时才重绘
    final shouldRepaint = running && !isPaused;
    return shouldRepaint;
  }
}