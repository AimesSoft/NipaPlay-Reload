import 'package:flutter/material.dart';
import 'danmaku_item.dart';
import 'utils.dart';
import 'danmaku_option.dart'; // 🔥 添加导入

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
  final bool isPaused;
  final DanmakuOption option; // 🔥 新增：弹幕选项

  StaticDanmakuPainter(
      this.progress,
      this.topDanmakuItems,
      this.buttomDanmakuItems,
      this.danmakuDurationInSeconds,
      this.fontSize,
      this.showStroke,
      this.danmakuHeight,
      this.running,
      this.tick,
      this.isPaused,
      this.option); // 🔥 新增：弹幕选项参数

  @override
  void paint(Canvas canvas, Size size) {
    // 🔥 关键修改：根据隐藏选项决定是否绘制弹幕
    
    // 绘制顶部弹幕
    if (!option.hideTop) {
      for (var item in topDanmakuItems) {
        // 🔥 检查弹幕是否在5秒显示时间内
        final elapsedTime = tick - item.creationTime;
        if (elapsedTime > 5 * 1000) continue; // 5秒后不显示
        
        item.xPosition = (size.width - item.width) / 2;
        // 如果 Paragraph 没有缓存，则创建并缓存它
        item.paragraph ??= Utils.generateParagraph(item.content, size.width, fontSize);

        // 绘制文字（包括阴影）
        canvas.drawParagraph(item.paragraph!, Offset(item.xPosition, item.yPosition));
        
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

    // 绘制底部弹幕 (翻转绘制)
    if (!option.hideBottom) {
      for (var item in buttomDanmakuItems) {
        // 🔥 检查弹幕是否在5秒显示时间内
        final elapsedTime = tick - item.creationTime;
        if (elapsedTime > 5 * 1000) continue; // 5秒后不显示
        
        item.xPosition = (size.width - item.width) / 2;
        // 如果 Paragraph 没有缓存，则创建并缓存它
        item.paragraph ??= Utils.generateParagraph(item.content, size.width, fontSize);

        // 计算底部弹幕的实际Y位置
        final actualYPosition = size.height - item.yPosition - danmakuHeight;
        
        // 绘制文字（包括阴影）
        canvas.drawParagraph(
            item.paragraph!, Offset(item.xPosition, actualYPosition));
            
        // 🔥 新增：绘制碰撞箱（如果启用）
        if (option.showCollisionBoxes) {
          // 为底部弹幕创建一个临时的DanmakuItem来计算碰撞箱
          final tempItem = DanmakuItem(
            content: item.content,
            creationTime: item.creationTime,
            width: item.width,
            xPosition: item.xPosition,
            yPosition: actualYPosition, // 使用实际的Y位置
            paragraph: item.paragraph,
            strokeParagraph: item.strokeParagraph,
          );
          
          final collisionBox = Utils.calculateCollisionBox(tempItem, fontSize);
          Utils.drawCollisionBox(canvas, collisionBox, item.content.color);
          // 可选：绘制碰撞箱信息
          // Utils.drawCollisionBoxInfo(canvas, collisionBox, tempItem);
        }
        
        // 🔥 新增：绘制轨道编号（如果启用）
        if (option.showTrackNumbers) {
          // 基于Y位置计算轨道编号（底部弹幕）
          final trackHeight = danmakuHeight + 10.0; // 轨道高度 = 弹幕高度 + 垂直间距
          final trackIndex = ((item.yPosition - 10.0) / trackHeight).floor(); // 减去垂直间距
          // 为底部弹幕创建一个临时的DanmakuItem来绘制轨道编号
          final tempItem = DanmakuItem(
            content: item.content,
            creationTime: item.creationTime,
            width: item.width,
            xPosition: item.xPosition,
            yPosition: actualYPosition, // 使用实际的Y位置
            paragraph: item.paragraph,
            strokeParagraph: item.strokeParagraph,
          );
          Utils.drawTrackNumber(canvas, tempItem, trackIndex);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant StaticDanmakuPainter oldDelegate) {
    final shouldRepaint = running && !isPaused;
    return shouldRepaint;
  }
}