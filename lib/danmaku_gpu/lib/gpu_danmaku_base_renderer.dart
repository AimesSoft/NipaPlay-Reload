import 'package:flutter/material.dart';
import 'gpu_danmaku_item.dart';
import 'gpu_danmaku_config.dart';
import 'dynamic_font_atlas.dart';
import 'gpu_danmaku_text_renderer.dart';
import '../../danmaku/lib/danmaku_content_item.dart';

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
  final List<GPUDanmakuItem> _danmakuItems = [];
  
  /// 字体图集
  final DynamicFontAtlas _fontAtlas;
  
  /// 文本渲染器
  late final GPUDanmakuTextRenderer _textRenderer;
  
  /// 初始化状态
  bool _isInitialized = false;
  
  /// 调试选项
  bool _showCollisionBoxes = false;
  bool _showTrackNumbers = false;
  
  /// 状态管理
  bool _isPaused = false;
  bool _isVisible = true;
  
  /// 时间管理
  int _baseTime = DateTime.now().millisecondsSinceEpoch;
  int _pausedTime = 0;
  int _lastPauseStart = 0;

  GPUDanmakuBaseRenderer({
    required this.config,
    required this.opacity,
    VoidCallback? onNeedRepaint,
    bool isPaused = false,
    bool showCollisionBoxes = false,
    bool showTrackNumbers = false,
    bool isVisible = true,
  }) : _onNeedRepaint = onNeedRepaint,
       _isPaused = isPaused,
       _showCollisionBoxes = showCollisionBoxes,
       _showTrackNumbers = showTrackNumbers,
       _isVisible = isVisible,
       _fontAtlas = DynamicFontAtlas(
         fontSize: config.fontSize,
         onAtlasUpdated: onNeedRepaint,
       ) {
    _textRenderer = GPUDanmakuTextRenderer(
      fontAtlas: _fontAtlas,
      config: config,
    );
    _initialize();
  }

  /// 初始化
  Future<void> _initialize() async {
    await _fontAtlas.generate();
    _isInitialized = true;
    _onNeedRepaint?.call();
    debugPrint('${runtimeType}: 初始化完成');
  }

  /// 获取字体大小
  double get fontSize => config.fontSize;

  /// 获取字体图集
  DynamicFontAtlas get fontAtlas => _fontAtlas;

  /// 获取文本渲染器
  GPUDanmakuTextRenderer get textRenderer => _textRenderer;

  /// 获取所有弹幕项目
  List<GPUDanmakuItem> get danmakuItems => List.unmodifiable(_danmakuItems);

  /// 检查是否初始化完成
  bool get isInitialized => _isInitialized;

  /// 检查是否可见
  bool get isVisible => _isVisible;

  /// 检查是否暂停
  bool get isPaused => _isPaused;

  /// 获取当前时间
  int getCurrentTime() {
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    return _isPaused ? (_lastPauseStart - _baseTime - _pausedTime) : (currentTime - _baseTime - _pausedTime);
  }

  /// 更新配置选项
  void updateOptions({GPUDanmakuConfig? newConfig, double? newOpacity}) {
    bool needsUpdate = false;
    
    if (newConfig != null && config != newConfig) {
      config = newConfig;
      needsUpdate = true;
    }
    
    if (newOpacity != null && opacity != newOpacity) {
      opacity = newOpacity;
      needsUpdate = true;
    }
    
    if (needsUpdate) {
      _onNeedRepaint?.call();
    }
  }

  /// 更新调试选项
  void updateDebugOptions({bool? showCollisionBoxes, bool? showTrackNumbers}) {
    if ((showCollisionBoxes != null && _showCollisionBoxes != showCollisionBoxes) ||
        (showTrackNumbers != null && _showTrackNumbers != showTrackNumbers)) {
      _showCollisionBoxes = showCollisionBoxes ?? _showCollisionBoxes;
      _showTrackNumbers = showTrackNumbers ?? _showTrackNumbers;
      _onNeedRepaint?.call();
    }
  }

  /// 设置可见性
  void setVisibility(bool visible) {
    if (_isVisible != visible) {
      _isVisible = visible;
      _onNeedRepaint?.call();
    }
  }

  /// 设置暂停状态
  void setPaused(bool paused) {
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    if (paused && !_isPaused) {
      _lastPauseStart = currentTime;
    } else if (!paused && _isPaused) {
      if (_lastPauseStart > 0) {
        _pausedTime += currentTime - _lastPauseStart;
      }
    }
    _isPaused = paused;
  }

  /// 添加弹幕
  void addDanmaku(DanmakuContentItem item) {
    final danmakuItem = GPUDanmakuItem.fromDanmakuContentItem(item, getCurrentTime());
    _danmakuItems.add(danmakuItem);
    
    // 优化：检查字体图集是否已经包含该文本，避免重复添加
    if (!_textRenderer.canRender(item.text)) {
      _textRenderer.addTextToAtlas(item.text);
    }
    
    // 调用子类的添加弹幕逻辑
    onDanmakuAdded(danmakuItem);
  }

  /// 清空弹幕
  void clear() {
    _danmakuItems.clear();
    _baseTime = DateTime.now().millisecondsSinceEpoch;
    _pausedTime = 0;
    
    // 调用子类的清理逻辑
    onDanmakuCleared();
  }

  /// 移除过期弹幕
  void removeExpiredDanmaku() {
    if (_isPaused) return; // 暂停时不移除弹幕
    
    final currentTime = getCurrentTime();
    final expiredItems = <GPUDanmakuItem>[];
    
    _danmakuItems.removeWhere((item) {
      if (item.isExpired(currentTime, config.danmakuDuration)) {
        expiredItems.add(item);
        return true;
      }
      return false;
    });
    
    // 通知子类有弹幕被移除
    for (final item in expiredItems) {
      onDanmakuRemoved(item);
    }
  }

  /// 释放资源
  void dispose() {
    _fontAtlas.dispose();
    debugPrint('${runtimeType}: 资源释放完成');
  }

  /// 绘制碰撞盒（调试用）
  void drawCollisionBox(Canvas canvas, double x, double y, double width, double height) {
    if (!_showCollisionBoxes) return;
    
    final paint = Paint()
      ..color = Colors.red.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(Rect.fromLTWH(x, y, width, height), paint);
  }

  /// 绘制轨道号（调试用）
  void drawTrackNumber(Canvas canvas, double x, double y, int trackIndex) {
    if (!_showTrackNumbers) return;
    
    final textPainter = TextPainter(
      text: TextSpan(
        text: trackIndex.toString(),
        style: const TextStyle(color: Colors.red, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(x - 20, y - 12));
  }

  /// 主绘制方法
  @override
  void paint(Canvas canvas, Size size) {
    if (!_isVisible || !_isInitialized || _fontAtlas.atlasTexture == null) {
      return;
    }
    
    // 移除过期弹幕
    removeExpiredDanmaku();
    
    // 调用子类的绘制逻辑
    paintDanmaku(canvas, size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  // 以下方法由子类实现

  /// 当弹幕被添加时调用
  /// 
  /// 参数:
  /// - item: 被添加的弹幕项目
  void onDanmakuAdded(GPUDanmakuItem item);

  /// 当弹幕被移除时调用
  /// 
  /// 参数:
  /// - item: 被移除的弹幕项目
  void onDanmakuRemoved(GPUDanmakuItem item);

  /// 当弹幕被清空时调用
  void onDanmakuCleared();

  /// 绘制弹幕
  /// 
  /// 参数:
  /// - canvas: 画布
  /// - size: 画布尺寸
  void paintDanmaku(Canvas canvas, Size size);
} 