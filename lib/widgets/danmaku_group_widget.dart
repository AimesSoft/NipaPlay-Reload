import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';

class DanmakuGroupWidget extends StatelessWidget {
  final List<Map<String, dynamic>> danmakus;
  final String type;
  final double videoDuration;
  final double currentTime;
  final double fontSize;
  final bool isVisible;
  final double opacity;

  const DanmakuGroupWidget({
    super.key,
    required this.danmakus,
    required this.type,
    required this.videoDuration,
    required this.currentTime,
    required this.fontSize,
    required this.isVisible,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible || danmakus.isEmpty) return const SizedBox.shrink();
    final screenWidth = MediaQuery.of(context).size.width;
    List<Widget> children = [];
    for (var danmaku in danmakus) {
      final content = danmaku['content'] as String;
      final time = danmaku['time'] as double;
      final colorStr = danmaku['color'] as String;
      final isMerged = danmaku['merged'] == true;
      final mergeCount = isMerged ? (danmaku['mergeCount'] as int? ?? 1) : 1;
      final y = danmaku['y'] as double? ?? 0.0;
      final colorValues = colorStr.replaceAll('rgb(', '').replaceAll(')', '').split(',').map((s) => int.parse(s)).toList();
      final color = Color.fromARGB(255, colorValues[0], colorValues[1], colorValues[2]);
      DanmakuItemType danmakuType;
      switch (type) {
        case 'scroll':
          danmakuType = DanmakuItemType.scroll;
          break;
        case 'top':
          danmakuType = DanmakuItemType.top;
          break;
        case 'bottom':
          danmakuType = DanmakuItemType.bottom;
          break;
        default:
          danmakuType = DanmakuItemType.scroll;
      }
      final danmakuItem = DanmakuContentItem(
        content,
        type: danmakuType,
        color: color,
        fontSizeMultiplier: isMerged ? (1.0 + mergeCount / 10.0).clamp(1.0, 2.0) : 1.0,
        countText: isMerged ? 'x$mergeCount' : null,
        isMe: danmaku['isMe'] as bool? ?? false,
      );
      // 计算X/Y位置和透明度
      double x = 0;
      double localOpacity = opacity;
      final timeDiff = currentTime - time;
      final adjustedFontSize = fontSize * danmakuItem.fontSizeMultiplier;
      final textPainter = TextPainter(
        text: TextSpan(
          text: danmakuItem.text,
          style: TextStyle(fontSize: adjustedFontSize, color: danmakuItem.color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final danmakuWidth = textPainter.width;
      switch (danmakuType) {
        case DanmakuItemType.scroll:
          const duration = 10.0; // 保持10秒的移动时间
          const earlyStartTime = 1.0; // 提前1秒开始
          
          if (timeDiff < -earlyStartTime) {
            x = screenWidth;
            localOpacity = 0;
          } else if (timeDiff > duration) {
            x = -danmakuWidth;
            localOpacity = 0;
          } else {
            // 🔥 修复：弹幕从更远的屏幕外开始，确保时间轴时间点时刚好在屏幕边缘
            final extraDistance = (screenWidth + danmakuWidth) / 10; // 额外距离
            final startX = screenWidth + extraDistance; // 起始位置
            final totalDistance = extraDistance + screenWidth + danmakuWidth; // 总移动距离
            final adjustedTime = timeDiff + earlyStartTime; // 调整到[0, 11]范围
            final totalDuration = duration + earlyStartTime; // 总时长11秒
            
            x = startX - (adjustedTime / totalDuration) * totalDistance;
            if (x > screenWidth || x + danmakuWidth < 0) {
              localOpacity = 0;
            }
          }
          break;
        case DanmakuItemType.top:
        case DanmakuItemType.bottom:
          x = (screenWidth - danmakuWidth) / 2;
          if (timeDiff < 0 || timeDiff > 5) {
            localOpacity = 0;
          }
          break;
      }
      if (localOpacity > 0) {
        // 计算描边色
        final luminance = (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) / 255;
        final strokeColor = luminance < 0.114 ? Colors.white : Colors.black;
        final shadowList = [
          Shadow(offset: const Offset(-1, -1), blurRadius: 0, color: strokeColor),
          Shadow(offset: const Offset(1, -1), blurRadius: 0, color: strokeColor),
          Shadow(offset: const Offset(1, 1), blurRadius: 0, color: strokeColor),
          Shadow(offset: const Offset(-1, 1), blurRadius: 0, color: strokeColor),
          Shadow(offset: const Offset(0, -1), blurRadius: 0, color: strokeColor),
          Shadow(offset: const Offset(0, 1), blurRadius: 0, color: strokeColor),
          Shadow(offset: const Offset(-1, 0), blurRadius: 0, color: strokeColor),
          Shadow(offset: const Offset(1, 0), blurRadius: 0, color: strokeColor),
        ];
        final hasCountText = danmakuItem.countText != null;
        children.add(Positioned(
          left: x,
          top: y,
          child: Opacity(
            opacity: localOpacity,
            child: hasCountText
                ? RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: danmakuItem.text,
                          style: TextStyle(
                            fontSize: adjustedFontSize,
                            color: danmakuItem.color,
                            fontWeight: FontWeight.normal,
                            shadows: shadowList,
                          ),
                        ),
                        TextSpan(
                          text: danmakuItem.countText,
                          style: TextStyle(
                            fontSize: 16.0,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            shadows: shadowList,
                          ),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      // 描边
                      Text(
                        danmakuItem.text,
                        style: TextStyle(
                          fontSize: adjustedFontSize,
                          color: strokeColor,
                          fontWeight: FontWeight.normal,
                          shadows: shadowList,
                        ),
                      ),
                      // 实际文本
                      Text(
                        danmakuItem.text,
                        style: TextStyle(
                          fontSize: adjustedFontSize,
                          color: danmakuItem.color,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
          ),
        ));
      }
    }
    return Stack(children: children);
  }
} 