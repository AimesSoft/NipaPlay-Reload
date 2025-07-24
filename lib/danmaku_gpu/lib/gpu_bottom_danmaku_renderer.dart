import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import 'gpu_danmaku_base_renderer.dart';
import 'gpu_danmaku_item.dart';


/// GPU底部弹幕渲染器
///
/// 专门处理底部弹幕的渲染，直接使用传入的位置信息。
class GPUBottomDanmakuRenderer extends GPUDanmakuBaseRenderer {
  GPUBottomDanmakuRenderer({
    required super.config,
    required super.opacity,
    super.onNeedRepaint,
    super.isPaused,
    super.showCollisionBoxes,
    super.showTrackNumbers,
    super.isVisible,
  });

  @override
  void paintDanmaku(Canvas canvas, Size size) {
    if (danmakuItems.isEmpty) return;

    final visibleItems = danmakuItems.where((item) {
      final elapsed = (currentTime * 1000 - item.timeOffset).round();
      return elapsed >= 0 && elapsed <= config.duration;
    }).toList();

    for (final item in visibleItems) {
      if (item.type != DanmakuItemType.bottom) continue;

      if (item.currentX != null && item.currentY != null) {
        final textWidth =
            item.getTextWidth(config.fontSize * item.fontSizeMultiplier);
        if (item.currentY! > -config.trackHeight &&
            item.currentY! < size.height) {
          textRenderer.renderItem(
            canvas,
            item,
            item.currentX!,
            item.currentY!,
            opacity,
          );
        }
      }
    }
  }
} 