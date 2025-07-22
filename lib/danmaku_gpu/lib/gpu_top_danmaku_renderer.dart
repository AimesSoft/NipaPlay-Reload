import 'package:flutter/material.dart';
import 'gpu_danmaku_base_renderer.dart';
import 'gpu_danmaku_item.dart';
import 'gpu_danmaku_config.dart';
import 'gpu_danmaku_layered_track_manager.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';

/// GPU顶部弹幕渲染器
/// 
/// 专门处理顶部弹幕的渲染，使用分层轨道管理器进行轨道分配
class GPUTopDanmakuRenderer extends GPUDanmakuBaseRenderer {
  /// 分层轨道管理器
  late final GPUDanmakuLayeredTrackManager _layeredTrackManager;

  GPUTopDanmakuRenderer({
    required GPUDanmakuConfig config,
    required super.opacity,
    super.onNeedRepaint,
    super.isPaused,
    super.showCollisionBoxes,
    super.showTrackNumbers,
    super.isVisible,
  }) : super(
          config: config,
        ) {
    _layeredTrackManager = GPUDanmakuLayeredTrackManager(
      config: config,
      trackType: DanmakuTrackType.top,
    );
  }

  @override
  void onDanmakuAdded(GPUDanmakuItem item) {
    // 只处理顶部弹幕
    if (item.type != DanmakuItemType.top) return;
    
    // 如果有计数文本，也需要添加到字体图集中
    if (item.countText != null) {
      textRenderer.addTextToAtlas(item.countText!);
    }
    
    //debugPrint('GPUTopDanmakuRenderer: 添加顶部弹幕 - 文本:"${item.text}", 颜色:${item.color}');
  }

  @override
  void onDanmakuRemoved(GPUDanmakuItem item) {
    // 从分层轨道管理器中移除
    _layeredTrackManager.removeItem(item);
  }

  @override
  void onDanmakuCleared() {
    // 清空分层轨道管理器
    _layeredTrackManager.clear();
    //debugPrint('GPUTopDanmakuRenderer: 清空所有弹幕');
  }

  @override
  void paintDanmaku(Canvas canvas, Size size) {
    // 更新分层轨道管理器布局
    _layeredTrackManager.updateLayout(size);
    
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
        _layeredTrackManager.assignTrack(item);
      }
    }
  }

  /// 渲染所有轨道的弹幕
  void _renderAllTracks(Canvas canvas, Size size) {
    final trackItems = _layeredTrackManager.getAllTrackItems();
    
    int totalDanmakuCount = 0;
    trackItems.forEach((trackId, items) {
      totalDanmakuCount += items.length;
      _renderTrack(canvas, size, trackId, items);
    });
  }

  /// 渲染单个轨道的弹幕
  void _renderTrack(Canvas canvas, Size size, int trackId, List<GPUDanmakuItem> items) {
    final trackY = _layeredTrackManager.calculateTrackY(trackId, size.height);
    
    for (final item in items) {
      // 检查弹幕是否应该被屏蔽
      if (shouldBlockDanmaku(item.text)) {
        continue; // 跳过被屏蔽的弹幕，不绘制
      }
      
      // 检查弹幕是否应该被过滤（基于合并弹幕显示设置）
      if (shouldFilterDanmaku(item)) {
        continue; // 跳过被过滤的弹幕，不绘制
      }
      
      // 获取弹幕的实际显示属性（考虑合并弹幕开关状态）
      final displayProps = getDanmakuDisplayProperties(item);
      final actualFontSizeMultiplier = displayProps['fontSizeMultiplier'] as double;
      final actualCountText = displayProps['countText'] as String?;
      
      // 计算弹幕文本的实际渲染宽度（考虑字体大小倍率）
      final textWidth = textRenderer.calculateTextWidth(item.text, 
          scale: 0.5 * actualFontSizeMultiplier);
      
      // 计算计数文本的宽度（如果存在）
      double countTextWidth = 0;
      if (actualCountText != null) {
        countTextWidth = textRenderer.calculateTextWidth(actualCountText, 
            scale: 0.5 * 0.5); // 计数文本缩放为0.5
      }
      
      // 计算总宽度（弹幕文本 + 间距 + 计数文本）
      final totalWidth = textWidth + (actualCountText != null ? 5 + countTextWidth : 0);
      
      // 计算弹幕的X位置（居中显示）
      final xPos = (size.width - totalWidth) / 2;
      
      // 渲染弹幕文本（使用实际字体大小倍率）
      textRenderer.renderItem(
        canvas,
        item,
        xPos,
        trackY,
        opacity,
        fontSizeMultiplier: actualFontSizeMultiplier,
      );
      
      // 如果是合并弹幕，渲染计数文本（使用GPU渲染）
      if (actualCountText != null) {
        // 计算计数文本的Y坐标，使其与弹幕文本底对齐
        final countTextY = trackY + (config.fontSize * actualFontSizeMultiplier) - (config.fontSize * 0.5);
        _renderCountTextGPU(canvas, item, xPos + textWidth + 5, countTextY, actualCountText);
      }
      
      // 绘制调试信息
      if (showCollisionBoxes) {
        drawCollisionBox(canvas, xPos, trackY, totalWidth, config.fontSize * actualFontSizeMultiplier);
      }
      
      if (showTrackNumbers) {
        _drawLayeredTrackNumber(canvas, xPos, trackY, trackId);
      }
    }
  }

  /// 绘制分层轨道数（包含层数信息）
  void _drawLayeredTrackNumber(Canvas canvas, double x, double y, int trackId) {
    final layer = _layeredTrackManager.getTrackLayer(trackId);
    final localTrackId = _layeredTrackManager.getLocalTrackId(trackId);
    
    // 构建轨道数文本（包含层数信息）
    final trackNumberText = layer > 1 ? 'L$layer-${localTrackId + 1}' : '${localTrackId + 1}';
    
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    
    final textPainter = TextPainter(
      text: TextSpan(
        text: trackNumberText,
        style: const TextStyle(
          color: Colors.red,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    textPainter.paint(canvas, Offset(x - textPainter.width - 5, y));
  }

  /// 渲染计数文本（GPU方式）
  void _renderCountTextGPU(Canvas canvas, GPUDanmakuItem item, double x, double y, String countText) {
    // 创建临时的计数文本项目
    final countItem = GPUDanmakuItem(
      text: countText,
      color: item.color,
      type: item.type,
      timeOffset: item.timeOffset,
      createdAt: item.createdAt,
      fontSizeMultiplier: 0.5, // 计数文本使用较小的字体
    );
    
    // 渲染计数文本
    textRenderer.renderItem(
      canvas,
      countItem,
      x,
      y,
      opacity,
      scale: 0.5,
      fontSizeMultiplier: 0.5,
    );
  }

  /// 获取分层轨道管理器（供调试使用）
  GPUDanmakuLayeredTrackManager get layeredTrackManager => _layeredTrackManager;
} 