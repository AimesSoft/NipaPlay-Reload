import 'package:flutter/material.dart';
import '../../danmaku/lib/danmaku_content_item.dart';
import 'gpu_danmaku_config.dart';
import 'gpu_top_danmaku_renderer.dart';

/// GPU弹幕渲染器调度器
/// 
/// 管理多种类型弹幕的GPU渲染器
class GPUDanmakuRenderer extends CustomPainter {
  final GPUDanmakuConfig config;
  final double opacity;
  final VoidCallback? _onNeedRepaint; // 重绘回调
  
  // 不同类型弹幕的渲染器
  late final GPUTopDanmakuRenderer _topRenderer;
  // TODO: 后续添加滚动和底部弹幕渲染器
  // late final GPUScrollDanmakuRenderer _scrollRenderer;
  // late final GPUBottomDanmakuRenderer _bottomRenderer;
  
  // 调试选项
  bool _showCollisionBoxes = false;
  bool _showTrackNumbers = false;
  
  // 时间管理
  bool _isPaused = false;
  bool _isVisible = true; // 新增可见性状态

  GPUDanmakuRenderer({
    required this.config,
    required this.opacity,
    VoidCallback? onNeedRepaint,
    bool isPaused = false,
    bool showCollisionBoxes = false,
    bool showTrackNumbers = false,
    bool isVisible = true, // 在构造函数中接收
  }) : _onNeedRepaint = onNeedRepaint, 
       _isPaused = isPaused,
       _isVisible = isVisible, // 初始化
       _showCollisionBoxes = showCollisionBoxes,
       _showTrackNumbers = showTrackNumbers {
    _initializeRenderers();
  }

  /// 获取字体大小（从配置中）
  double get fontSize => config.fontSize;

  /// 初始化各种弹幕渲染器
  void _initializeRenderers() {
    // 初始化顶部弹幕渲染器
    _topRenderer = GPUTopDanmakuRenderer(
      config: config,
      opacity: opacity,
      onNeedRepaint: _onNeedRepaint,
      isPaused: _isPaused,
      showCollisionBoxes: _showCollisionBoxes,
      showTrackNumbers: _showTrackNumbers,
      isVisible: _isVisible, // 传递给子渲染器
    );
    
    // TODO: 后续初始化其他类型的弹幕渲染器
    // _scrollRenderer = GPUScrollDanmakuRenderer(...);
    // _bottomRenderer = GPUBottomDanmakuRenderer(...);
    
    debugPrint('GPUDanmakuRenderer: 初始化弹幕渲染器完成');
  }

  /// 更新调试选项
  void updateDebugOptions({bool? showCollisionBoxes, bool? showTrackNumbers}) {
    bool needsUpdate = false;
    
    if (showCollisionBoxes != null && _showCollisionBoxes != showCollisionBoxes) {
      _showCollisionBoxes = showCollisionBoxes;
      needsUpdate = true;
    }
    
    if (showTrackNumbers != null && _showTrackNumbers != showTrackNumbers) {
      _showTrackNumbers = showTrackNumbers;
      needsUpdate = true;
    }
    
    if (needsUpdate) {
      // 更新所有子渲染器的调试选项
      _topRenderer.updateDebugOptions(
        showCollisionBoxes: showCollisionBoxes,
        showTrackNumbers: showTrackNumbers,
      );
      
      // TODO: 后续更新其他渲染器的调试选项
      // _scrollRenderer.updateDebugOptions(...);
      // _bottomRenderer.updateDebugOptions(...);
      
      debugPrint('GPUDanmakuRenderer: 调试选项更新完成');
    }
  }

  /// 设置可见性
  void setVisibility(bool visible) {
    _isVisible = visible;
    _topRenderer.setVisibility(visible);
    // TODO: 其他渲染器
  }

  /// 设置暂停状态
  void setPaused(bool paused) {
    _isPaused = paused;
    
    // 更新所有子渲染器的暂停状态
    _topRenderer.setPaused(paused);
    
    // TODO: 后续更新其他渲染器的暂停状态
    // _scrollRenderer.setPaused(paused);
    // _bottomRenderer.setPaused(paused);
    
    debugPrint('GPUDanmakuRenderer: 暂停状态设置为: $paused');
  }

  /// 添加弹幕
  void addDanmaku(DanmakuContentItem item) {
    switch (item.type) {
      case DanmakuItemType.top:
        _topRenderer.addDanmaku(item);
        break;
      case DanmakuItemType.scroll:
        // TODO: 后续添加滚动弹幕支持
        // _scrollRenderer.addDanmaku(item);
        debugPrint('GPUDanmakuRenderer: 滚动弹幕暂未支持 - ${item.text}');
        break;
      case DanmakuItemType.bottom:
        // TODO: 后续添加底部弹幕支持
        // _bottomRenderer.addDanmaku(item);
        debugPrint('GPUDanmakuRenderer: 底部弹幕暂未支持 - ${item.text}');
        break;
    }
  }

  /// 清空弹幕
  void clear() {
    _topRenderer.clear();
    
    // TODO: 后续清空其他渲染器
    // _scrollRenderer.clear();
    // _bottomRenderer.clear();
    
    debugPrint('GPUDanmakuRenderer: 清空所有弹幕');
  }

  /// 更新选项
  void updateOptions({GPUDanmakuConfig? config, double? opacity}) {
    _topRenderer.updateOptions(newConfig: config, newOpacity: opacity);
    
    // TODO: 后续更新其他渲染器选项
    // _scrollRenderer.updateOptions(config: config, opacity: opacity);
    // _bottomRenderer.updateOptions(config: config, opacity: opacity);
    
    debugPrint('GPUDanmakuRenderer: 选项更新完成');
  }

  /// 释放资源
  void dispose() {
    _topRenderer.dispose();
    
    // TODO: 后续释放其他渲染器资源
    // _scrollRenderer.dispose();
    // _bottomRenderer.dispose();
    
    debugPrint('GPUDanmakuRenderer: 资源释放完成');
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制顶部弹幕
    _topRenderer.paint(canvas, size);
    
    // TODO: 后续绘制其他类型弹幕
    // _scrollRenderer.paint(canvas, size);
    // _bottomRenderer.paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // 总是重绘，因为弹幕是动态的，由AnimationController驱动
  }
}

/// GPU弹幕项目（已废弃，由各个子渲染器处理）
@deprecated
class _GPUDanmakuItem {
  final String text;
  final Color color;
  final double fontSize;
  final int timeOffset;
  final int createdAt;
  final int trackId;
  final double textWidth;

  _GPUDanmakuItem({
    required this.text,
    required this.color,
    required this.fontSize,
    required this.timeOffset,
    required this.createdAt,
    required this.trackId,
  }) : textWidth = _calculateTextWidth(text, fontSize);

  static double _calculateTextWidth(String text, double fontSize) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.normal,
          fontFeatures: const [FontFeature.proportionalFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    return textPainter.width;
  }
} 