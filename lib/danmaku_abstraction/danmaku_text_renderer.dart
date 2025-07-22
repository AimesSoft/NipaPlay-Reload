import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';

/// 弹幕文本渲染器的抽象基类
abstract class DanmakuTextRenderer {
  const DanmakuTextRenderer();

  /// 构建并渲染弹幕文本
  ///
  /// [context] - 构建上下文
  /// [content] - 弹幕内容项
  /// [fontSize] - 基础字体大小
  /// [opacity] - 透明度
  Widget build(
    BuildContext context,
    DanmakuContentItem content,
    double fontSize,
    double opacity,
  );
}

/// 使用CPU进行文本渲染的实现类
class CpuDanmakuTextRenderer extends DanmakuTextRenderer {
  const CpuDanmakuTextRenderer();

  @override
  Widget build(
    BuildContext context,
    DanmakuContentItem content,
    double fontSize,
    double opacity,
  ) {
    // 计算弹幕颜色的亮度
    final color = content.color;
    final luminance =
        (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) / 255;
    // 如果亮度小于0.2，说明是深色，使用白色描边；否则使用黑色描边
    final strokeColor = luminance < 0.2 ? Colors.white : Colors.black;

    // 应用字体大小倍率
    final adjustedFontSize = fontSize * content.fontSizeMultiplier;

    // 检查是否有计数文本
    final hasCountText = content.countText != null;

    // 创建阴影列表
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

    return Opacity(
      opacity: opacity,
      child: hasCountText
          ? RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: content.text,
                    style: TextStyle(
                      fontSize: adjustedFontSize,
                      color: content.color,
                      fontWeight: FontWeight.normal,
                      shadows: shadowList,
                    ),
                  ),
                  TextSpan(
                    text: content.countText,
                    style: TextStyle(
                      fontSize: 25.0, // 固定大小字体
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      shadows: shadowList, // 继承相同的描边效果
                    ),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                // 描边
                Text(
                  content.text,
                  style: TextStyle(
                    fontSize: adjustedFontSize,
                    color: strokeColor,
                    fontWeight: FontWeight.normal,
                    shadows: shadowList,
                  ),
                ),
                // 实际文本
                Text(
                  content.text,
                  style: TextStyle(
                    fontSize: adjustedFontSize,
                    color: content.color,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
    );
  }
} 