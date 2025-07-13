import 'package:flutter/material.dart';
import 'gpu_danmaku_base_renderer.dart';
import 'gpu_danmaku_item.dart';
import 'gpu_danmaku_config.dart';
import 'gpu_danmaku_track_manager.dart';
import '../../danmaku/lib/danmaku_content_item.dart';

/// GPU顶部弹幕渲染器
/// 
/// 专门处理顶部弹幕的渲染，使用轨道管理器进行轨道分配
class GPUTopDanmakuRenderer extends GPUDanmakuBaseRenderer {
  /// 轨道管理器
  late final GPUDanmakuTrackManager _trackManager;

  GPUTopDanmakuRenderer({
    required GPUDanmakuConfig config,
    required double opacity,
    VoidCallback? onNeedRepaint,
    bool isPaused = false,
    bool showCollisionBoxes = false,
    bool showTrackNumbers = false,
    bool isVisible = true,
  }) : super(
          config: config,
          opacity: opacity,
          onNeedRepaint: onNeedRepaint,
          isPaused: isPaused,
          showCollisionBoxes: showCollisionBoxes,
          showTrackNumbers: showTrackNumbers,
          isVisible: isVisible,
        ) {
    _trackManager = GPUDanmakuTrackManager(
      config: config,
      trackType: DanmakuTrackType.top,
    );
  }

  @override
  void onDanmakuAdded(GPUDanmakuItem item) {
    // 只处理顶部弹幕
    if (item.type != DanmakuItemType.top) return;
    
    debugPrint('GPUTopDanmakuRenderer: 添加顶部弹幕 - 文本:"${item.text}", 颜色:${item.color}');
  }

  @override
  void onDanmakuRemoved(GPUDanmakuItem item) {
    // 从轨道管理器中移除
    _trackManager.removeItem(item);
  }

  @override
  void onDanmakuCleared() {
    // 清空轨道管理器
    _trackManager.clear();
    debugPrint('GPUTopDanmakuRenderer: 清空所有弹幕');
  }

  @override
  void paintDanmaku(Canvas canvas, Size size) {
    // 更新轨道管理器布局
    _trackManager.updateLayout(size);
    
    // 获取当前时间
    final currentTime = getCurrentTime();
    
    // 处理弹幕轨道分配
    _updateDanmakuTracks(currentTime);
    
    // 绘制所有轨道的弹幕
    _renderAllTracks(canvas, size);
  }

  /// 更新弹幕轨道分配
  void _updateDanmakuTracks(int currentTime) {
    final visibleItems = <GPUDanmakuItem>[];
    
    // 收集可见的弹幕项目
    for (final item in danmakuItems) {
      if (item.type == DanmakuItemType.top && item.shouldShow(currentTime)) {
        visibleItems.add(item);
      }
    }
    
    // 为未分配轨道的弹幕分配轨道
    for (final item in visibleItems) {
      if (item.trackId == -1) {
        _trackManager.assignTrack(item);
      }
    }
  }

  /// 渲染所有轨道的弹幕
  void _renderAllTracks(Canvas canvas, Size size) {
    final trackItems = _trackManager.getAllTrackItems();
    
    int totalDanmakuCount = 0;
    trackItems.forEach((trackId, items) {
      totalDanmakuCount += items.length;
      _renderTrack(canvas, size, trackId, items);
    });
    
    if (totalDanmakuCount > 0) {
      debugPrint('GPUTopDanmakuRenderer: 渲染 $totalDanmakuCount 个顶部弹幕');
    }
  }

  /// 渲染单个轨道的弹幕
  void _renderTrack(Canvas canvas, Size size, int trackId, List<GPUDanmakuItem> items) {
    final trackY = _trackManager.calculateTrackY(trackId, size.height);
    
    for (final item in items) {
      // 计算弹幕的X位置（居中显示）
      final textWidth = textRenderer.calculateTextWidth(item.text);
      final xPos = (size.width - textWidth) / 2;
      
      // 渲染弹幕文本
      textRenderer.renderItem(
        canvas,
        item,
        xPos,
        trackY,
        opacity,
      );
      
      // 绘制调试信息
      drawCollisionBox(canvas, xPos, trackY, textWidth, fontSize);
      drawTrackNumber(canvas, xPos, trackY + fontSize, trackId);
    }
  }

  /// 获取轨道管理器（供调试使用）
  GPUDanmakuTrackManager get trackManager => _trackManager;
} 