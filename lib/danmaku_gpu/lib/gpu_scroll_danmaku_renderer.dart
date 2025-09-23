import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import 'gpu_danmaku_base_renderer.dart';
import 'gpu_danmaku_item.dart';

/// GPU滚动弹幕渲染器
///
/// 专门处理滚动弹幕的渲染，直接使用传入的位置信息。
class GPUScrollDanmakuRenderer extends GPUDanmakuBaseRenderer {
  GPUScrollDanmakuRenderer({
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

    for (final item in danmakuItems) {
      if (item.type != DanmakuItemType.scroll) continue;

      final textWidth =
          item.getTextWidth(config.fontSize * item.fontSizeMultiplier);
      if (item.currentX != null &&
          item.currentY != null &&
          item.currentX! < size.width &&
          item.currentX! > -textWidth) {
        textRenderer.renderItem(
          canvas,
          item,
          item.currentX!,
          item.currentY!,
          opacity,
          fontSizeMultiplier: item.fontSizeMultiplier,
          countText: item.countText,
        );
      }
    }
  }
} 