import 'package:flutter/material.dart';
import 'gpu_danmaku_base_renderer.dart';
import 'gpu_danmaku_item.dart';
import 'gpu_danmaku_config.dart';
import 'gpu_scroll_danmaku_track_manager.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';

/// GPU滚动弹幕渲染器
///
/// 专门处理滚动弹幕的渲染，使用轨道管理器进行不重叠的轨道分配。
class GPUScrollDanmakuRenderer extends GPUDanmakuBaseRenderer {
  late final GPUScrollDanmakuTrackManager _trackManager;
  final List<GPUDanmakuItem> _pendingItems = [];

  GPUScrollDanmakuRenderer({
    required GPUDanmakuConfig config,
    required super.opacity,
    super.onNeedRepaint,
    super.isPaused,
    super.showCollisionBoxes,
    super.showTrackNumbers,
    super.isVisible,
  }) : super(config: config) {
    _trackManager = GPUScrollDanmakuTrackManager(config: config);
  }

  @override
  void onDanmakuAdded(GPUDanmakuItem item) {
    if (item.type != DanmakuItemType.scroll) return;
    _pendingItems.add(item);
  }

  @override
  void onDanmakuRemoved(GPUDanmakuItem item) {
    _trackManager.removeItem(item);
  }

  @override
  void onDanmakuCleared() {
    _trackManager.clear();
    _pendingItems.clear();
  }

  @override
  void paintDanmaku(Canvas canvas, Size size) {
    _trackManager.updateLayout(size);
    final currentTime = getCurrentTime();

    // 1. 分配轨道
    _assignTracks(size.width);

    // 2. 渲染弹幕
    final trackItems = _trackManager.getAllTrackItems();
    trackItems.forEach((trackId, items) {
      _renderTrack(canvas, size, currentTime, trackId, items);
    });

    // 3. 移除过期的弹幕
    _removeExpiredDanmaku(currentTime, size.width);
  }

  void _assignTracks(double screenWidth) {
    if (_pendingItems.isEmpty) return;
    
    // 按时间排序
    _pendingItems.sort((a, b) => a.timeOffset.compareTo(b.timeOffset));

    final assignedItems = <GPUDanmakuItem>[];
    for (final item in _pendingItems) {
      // 计算初始X坐标
      item.scrollOriginalX = screenWidth + (item.timeOffset / 1000) * (config.scrollScreensPerSecond * screenWidth);
      final trackId = _trackManager.assignTrack(item, screenWidth);
      if (trackId != -1) {
        assignedItems.add(item);
      }
    }
    
    // 移除已分配的
    _pendingItems.removeWhere((item) => assignedItems.contains(item));
  }

  void _renderTrack(Canvas canvas, Size size, int currentTime, int trackId, List<GPUDanmakuItem> items) {
    final trackY = _trackManager.calculateTrackY(trackId);
    
    for (final item in items) {
       // 计算当前X坐标
      final elapsedTime = (currentTime - item.createdAt) / 1000.0;
      final translateX = elapsedTime * (config.scrollScreensPerSecond * size.width);
      final currentX = item.scrollOriginalX! - translateX;
      final textWidth = item.getTextWidth(config.fontSize * item.fontSizeMultiplier);

      // 判断是否在屏幕内
      if (currentX + textWidth < 0 || currentX > size.width) {
        continue;
      }
      
      textRenderer.renderItem(
        canvas,
        item,
        currentX,
        trackY,
        opacity,
        fontSizeMultiplier: item.fontSizeMultiplier,
      );

      if (showCollisionBoxes) {
        drawCollisionBox(canvas, currentX, trackY, textWidth, config.fontSize * item.fontSizeMultiplier);
      }
    }
  }

  void _removeExpiredDanmaku(int currentTime, double screenWidth) {
     final allItems = _trackManager.getAllTrackItems().values.expand((x) => x).toList();
     final expiredItems = <GPUDanmakuItem>[];

     for (final item in allItems) {
        final elapsedTime = (currentTime - item.createdAt) / 1000.0;
        final translateX = elapsedTime * (config.scrollScreensPerSecond * screenWidth);
        final currentX = item.scrollOriginalX! - translateX;
        final textWidth = item.getTextWidth(config.fontSize * item.fontSizeMultiplier);
        
        if (currentX + textWidth < 0) {
           expiredItems.add(item);
        }
     }

     for (final item in expiredItems) {
        _trackManager.removeItem(item);
     }
  }
} 