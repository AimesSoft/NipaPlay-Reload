import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'gpu_danmaku_item.dart';
import 'gpu_danmaku_config.dart';
import 'dynamic_font_atlas.dart';
import 'gpu_danmaku_text_renderer.dart';
import '../../danmaku_abstraction/danmaku_content_item.dart';

/// GPU弹幕基础渲染器
///
/// 包含通用功能：时间管理、调试选项、生命周期管理等
/// 所有具体的弹幕渲染器都应该继承此类
abstract class GPUDanmakuBaseRenderer extends CustomPainter {
  /// 配置
  GPUDanmakuConfig config;

  /// 透明度
  double opacity;

  /// 重绘回调
  final VoidCallback? _onNeedRepaint;

  /// 弹幕项目列表
  final List<GPUDanmakuItem> danmakuItems = [];

  /// 字体图集（使用全局管理器）
  late final DynamicFontAtlas _fontAtlas;

  /// 文本渲染器
  late GpuDanmakuTextRenderer textRenderer;

  /// 初始化状态
  bool _isInitialized = false;

  /// 调试选项
  bool showCollisionBoxes = false;
  bool showTrackNumbers = false;

  /// 状态管理
  bool isPaused = false;
  bool _isVisible = true;

  /// 时间管理
  int _baseTime = DateTime.now().millisecondsSinceEpoch;
  int _pausedTime = 0;
  int _lastPauseStart = 0;
  double currentTime = 0.0;

  GPUDanmakuBaseRenderer({
    required this.config,
    required this.opacity,
    VoidCallback? onNeedRepaint,
    this.isPaused = false,
    this.showCollisionBoxes = false,
    this.showTrackNumbers = false,
    bool isVisible = true,
  })  : _onNeedRepaint = onNeedRepaint,
        _isVisible = isVisible {
    _initialize();
  }

  /// 初始化
  void _initialize() {
    if (_isInitialized) return;
    _fontAtlas = FontAtlasManager.getInstance(
      fontSize: config.fontSize,
      onAtlasUpdated: _onNeedRepaint,
    );
    textRenderer = GpuDanmakuTextRenderer(fontAtlas: _fontAtlas, config: config);
    _isInitialized = true;
  }

  /// 添加弹幕
  void onDanmakuAdded(PositionedDanmakuItem positionedItem) {
    // Convert PositionedDanmakuItem to GPUDanmakuItem
    final danmakuItem = GPUDanmakuItem(
      text: positionedItem.content.text, // Corrected from .content to .text
      color: positionedItem.content.color,
      type: positionedItem.content.type,
      timeOffset: (positionedItem.time * 1000).toInt(), // convert to ms
      createdAt: DateTime.now().millisecondsSinceEpoch,
      currentX: positionedItem.x,
      currentY: positionedItem.y,
      scrollOriginalX: positionedItem.offstageX,
      fontSizeMultiplier: positionedItem.content.fontSizeMultiplier,
      countText: positionedItem.content.countText,
    );
    danmakuItems.add(danmakuItem);
  }

  /// 移除弹幕
  void onDanmakuRemoved(GPUDanmakuItem item) {
    danmakuItems.remove(item);
  }

  /// 清空弹幕
  void onDanmakuCleared() {
    danmakuItems.clear();
  }

  /// 绘制弹幕（由子类实现）
  void paintDanmaku(Canvas canvas, Size size);

  @override
  void paint(Canvas canvas, Size size) {
    if (!_isVisible || !_isInitialized) return;
    paintDanmaku(canvas, size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // Always repaint for animations
  }

  /// 更新显示选项
  void updateOptions({GPUDanmakuConfig? newConfig, double? newOpacity}) {
    if (newConfig != null) {
      config = newConfig;
      // Re-initialize if font size changes
      if (_fontAtlas.fontSize != newConfig.fontSize) {
        _initialize();
      }
      textRenderer = GpuDanmakuTextRenderer(fontAtlas: _fontAtlas, config: newConfig);
    }
    if (newOpacity != null) {
      opacity = newOpacity;
    }
  }

  /// 设置暂停状态
  void setPaused(bool isPaused) {
    if (this.isPaused == isPaused) return;
    this.isPaused = isPaused;
    if (isPaused) {
      _lastPauseStart = DateTime.now().millisecondsSinceEpoch;
    } else {
      _pausedTime += DateTime.now().millisecondsSinceEpoch - _lastPauseStart;
    }
  }

  /// 设置可见性
  void setVisibility(bool isVisible) {
    _isVisible = isVisible;
  }
  
  void setCurrentTime(double time) {
    currentTime = time;
  }

  /// 获取当前时间（毫秒）
  int getCurrentTime() {
    if (isPaused) {
      return _lastPauseStart - _baseTime - _pausedTime;
    }
    return DateTime.now().millisecondsSinceEpoch - _baseTime - _pausedTime;
  }

  /// 资源释放
  void dispose() {
    // Font atlas is managed by FontAtlasManager, no need to dispose here
  }

  // Helper method to draw debug collision box
  void drawCollisionBox(Canvas canvas, GPUDanmakuItem item, Size size) {
    if (showCollisionBoxes && item.currentX != null && item.currentY != null) {
      final textWidth = item.getTextWidth(config.fontSize * item.fontSizeMultiplier);
      final paint = Paint()
        ..color = Colors.red.withOpacity(0.5)
        ..style = PaintingStyle.stroke;
      canvas.drawRect(
          Rect.fromLTWH(item.currentX!, item.currentY!, textWidth, config.trackHeight),
          paint);
    }
  }

  // Helper method to draw debug track numbers
  void drawTrackNumber(Canvas canvas, GPUDanmakuItem item, Size size) {
    if (showTrackNumbers && item.trackId != -1 && item.currentY != null) {
      final painter = TextPainter(
        text: TextSpan(
          text: 'T${item.trackId}',
          style: const TextStyle(color: Colors.cyan, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      );
      painter.layout();
      painter.paint(canvas, Offset(size.width - 30, item.currentY!));
    }
  }
} 