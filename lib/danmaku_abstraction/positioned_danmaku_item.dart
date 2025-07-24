import 'package:flutter/material.dart';
import 'danmaku_content_item.dart';

/// A data class that represents a danmaku item with its calculated position.
/// This is used to pass layout information from the CPU logic (DanmakuContainer)
/// to the GPU renderer (GPUDanmakuOverlay).
class PositionedDanmakuItem {
  final DanmakuContentItem content;
  final double x;
  final double y;
  final double offstageX; // The starting X position when it's off-screen
  final double time; // The original time of the danmaku

  PositionedDanmakuItem({
    required this.content,
    required this.x,
    required this.y,
    required this.offstageX,
    required this.time,
  });
} 