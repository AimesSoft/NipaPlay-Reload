import 'package:flutter/material.dart';
import 'gpu_danmaku_base_renderer.dart';
import 'gpu_danmaku_item.dart';
import 'gpu_danmaku_config.dart';
import 'gpu_danmaku_layered_track_manager.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';

/// GPU底部弹幕渲染器
///
/// 专门处理底部弹幕的渲染，使用分层轨道管理器进行轨道分配
class GPUBottomDanmakuRenderer extends GPUDanmakuBaseRenderer {
  /// 分层轨道管理器
  late final GPUDanmakuLayeredTrackManager _layeredTrackManager;

  GPUBottomDanmakuRenderer({
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
      trackType: DanmakuTrackType.bottom,
    );
  }

  @override
  void onDanmakuAdded(GPUDanmakuItem item) {
    // 只处理底部弹幕
    if (item.type != DanmakuItemType.bottom) return;

    if (item.countText != null) {
      textRenderer.addTextToAtlas(item.countText!);
    }
  }

  @override
  void onDanmakuRemoved(GPUDanmakuItem item) {
    _layeredTrackManager.removeItem(item);
  }

  @override
  void onDanmakuCleared() {
    _layeredTrackManager.clear();
  }

  @override
  void paintDanmaku(Canvas canvas, Size size) {
    _layeredTrackManager.updateLayout(size);
    final currentTime = getCurrentTime();
    _updateDanmakuTracks(currentTime);
    _renderAllTracks(canvas, size);
  }

  void _updateDanmakuTracks(int currentTime) {
    final visibleItems = <GPUDanmakuItem>[];
    for (final item in danmakuItems) {
      if (item.type == DanmakuItemType.bottom && item.shouldShow(currentTime)) {
        visibleItems.add(item);
      }
    }

    for (final item in visibleItems) {
      if (item.trackId == -1) {
        _layeredTrackManager.assignTrack(item);
      }
    }
  }

  void _renderAllTracks(Canvas canvas, Size size) {
    final trackItems = _layeredTrackManager.getAllTrackItems();
    trackItems.forEach((trackId, items) {
      _renderTrack(canvas, size, trackId, items);
    });
  }

  void _renderTrack(
      Canvas canvas, Size size, int trackId, List<GPUDanmakuItem> items) {
    final trackY = _layeredTrackManager.calculateTrackY(trackId, size.height);

    for (final item in items) {
      if (shouldBlockDanmaku(item.text) || shouldFilterDanmaku(item)) {
        continue;
      }

      final displayProps = getDanmakuDisplayProperties(item);
      final actualFontSizeMultiplier =
          displayProps['fontSizeMultiplier'] as double;
      final actualCountText = displayProps['countText'] as String?;

      final textWidth = textRenderer.calculateTextWidth(item.text,
          scale: 0.5 * actualFontSizeMultiplier);
      double countTextWidth = 0;
      if (actualCountText != null) {
        countTextWidth =
            textRenderer.calculateTextWidth(actualCountText, scale: 0.5 * 0.5);
      }
      final totalWidth = textWidth + (actualCountText != null ? 5 + countTextWidth : 0);
      final xPos = (size.width - totalWidth) / 2;

      textRenderer.renderItem(
        canvas,
        item,
        xPos,
        trackY,
        opacity,
        fontSizeMultiplier: actualFontSizeMultiplier,
      );

      if (actualCountText != null) {
        final countTextY = trackY +
            (config.fontSize * actualFontSizeMultiplier) -
            (config.fontSize * 0.5);
        _renderCountTextGPU(
            canvas, item, xPos + textWidth + 5, countTextY, actualCountText);
      }

      if (showCollisionBoxes) {
        drawCollisionBox(canvas, xPos, trackY, totalWidth,
            config.fontSize * actualFontSizeMultiplier);
      }

      if (showTrackNumbers) {
        _drawLayeredTrackNumber(canvas, xPos, trackY, trackId);
      }
    }
  }

  void _drawLayeredTrackNumber(
      Canvas canvas, double x, double y, int trackId) {
    final layer = _layeredTrackManager.getTrackLayer(trackId);
    final localTrackId = _layeredTrackManager.getLocalTrackId(trackId);
    final trackNumberText =
        layer > 1 ? 'L$layer-${localTrackId + 1}' : '${localTrackId + 1}';

    final textPainter = TextPainter(
      text: TextSpan(
        text: trackNumberText,
        style: const TextStyle(
            color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(canvas, Offset(x - textPainter.width - 5, y));
  }

  void _renderCountTextGPU(
      Canvas canvas, GPUDanmakuItem item, double x, double y, String countText) {
    final countItem = GPUDanmakuItem(
      text: countText,
      color: item.color,
      type: item.type,
      timeOffset: item.timeOffset,
      createdAt: item.createdAt,
      fontSizeMultiplier: 0.5,
    );
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

  GPUDanmakuLayeredTrackManager get layeredTrackManager => _layeredTrackManager;
} 