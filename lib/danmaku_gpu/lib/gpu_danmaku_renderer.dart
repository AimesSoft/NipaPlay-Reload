import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'gpu_danmaku_config.dart';
import 'gpu_top_danmaku_renderer.dart';
import 'gpu_bottom_danmaku_renderer.dart';
import 'gpu_scroll_danmaku_renderer.dart';

/// GPU弹幕渲染器调度器
///
/// 管理多种类型弹幕的GPU渲染器
class GPUDanmakuRenderer extends CustomPainter with ChangeNotifier {
  GPUDanmakuConfig config;
  double opacity;
  final VoidCallback? _onNeedRepaint; // 重绘回调

  // 不同类型弹幕的渲染器
  late final GPUTopDanmakuRenderer _topRenderer;
  late final GPUScrollDanmakuRenderer _scrollRenderer;
  late final GPUBottomDanmakuRenderer _bottomRenderer;

  // 调试选项
  bool _showCollisionBoxes = false;
  bool _showTrackNumbers = false;

  // 状态管理
  bool _isPaused = false;
  bool _isVisible = true;

  // 存储所有弹幕
  List<PositionedDanmakuItem> _danmakuList = [];
  double _currentTime = 0.0;

  GPUDanmakuRenderer({
    required this.config,
    required this.opacity,
    VoidCallback? onNeedRepaint,
    bool isPaused = false,
    bool showCollisionBoxes = false,
    bool showTrackNumbers = false,
    bool isVisible = true,
  })  : _onNeedRepaint = onNeedRepaint,
        _isPaused = isPaused,
        _isVisible = isVisible,
        _showCollisionBoxes = showCollisionBoxes,
        _showTrackNumbers = showTrackNumbers {
    _initializeRenderers();
  }

  /// 获取字体大小（从配置中）
  double get fontSize => config.fontSize;

  /// 初始化各种弹幕渲染器
  void _initializeRenderers() {
    _topRenderer = GPUTopDanmakuRenderer(
      config: config,
      opacity: opacity,
      onNeedRepaint: _onNeedRepaint,
      isPaused: _isPaused,
      isVisible: _isVisible,
      showCollisionBoxes: _showCollisionBoxes,
      showTrackNumbers: _showTrackNumbers,
    );
    _scrollRenderer = GPUScrollDanmakuRenderer(
      config: config,
      opacity: opacity,
      onNeedRepaint: _onNeedRepaint,
      isPaused: _isPaused,
      isVisible: _isVisible,
      showCollisionBoxes: _showCollisionBoxes,
      showTrackNumbers: _showTrackNumbers,
    );
    _bottomRenderer = GPUBottomDanmakuRenderer(
      config: config,
      opacity: opacity,
      onNeedRepaint: _onNeedRepaint,
      isPaused: _isPaused,
      isVisible: _isVisible,
      showCollisionBoxes: _showCollisionBoxes,
      showTrackNumbers: _showTrackNumbers,
    );
  }

  /// 设置弹幕数据
  void setDanmaku(List<PositionedDanmakuItem> danmaku, double currentTime) {
    _danmakuList = danmaku;
    _currentTime = currentTime;
    
    // 清空旧数据并分发新数据
    _topRenderer.onDanmakuCleared();
    _scrollRenderer.onDanmakuCleared();
    _bottomRenderer.onDanmakuCleared();

    for (final item in _danmakuList) {
      switch (item.content.type) {
        case DanmakuItemType.top:
          _topRenderer.onDanmakuAdded(item);
          break;
        case DanmakuItemType.scroll:
          _scrollRenderer.onDanmakuAdded(item);
          break;
        case DanmakuItemType.bottom:
          _bottomRenderer.onDanmakuAdded(item);
          break;
      }
    }
    notifyListeners();
  }


  @override
  void paint(Canvas canvas, Size size) {
    if (!_isVisible) return;

    // 更新子渲染器的时间
    _topRenderer.setCurrentTime(_currentTime);
    _scrollRenderer.setCurrentTime(_currentTime);
    _bottomRenderer.setCurrentTime(_currentTime);

    // 绘制不同类型的弹幕
    _topRenderer.paintDanmaku(canvas, size);
    _scrollRenderer.paintDanmaku(canvas, size);
    _bottomRenderer.paintDanmaku(canvas, size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    // We are using a Listenable (ChangeNotifier), so this can be false.
    return false;
  }

  /// 更新显示选项
  void updateOptions({GPUDanmakuConfig? newConfig, double? opacity}) {
    bool changed = false;
    if (newConfig != null && this.config != newConfig) {
      this.config = newConfig;
      changed = true;
    }
    if (opacity != null && this.opacity != opacity) {
      this.opacity = opacity;
      changed = true;
    }
    if (changed) {
      _topRenderer.updateOptions(newConfig: config, newOpacity: this.opacity);
      _scrollRenderer.updateOptions(newConfig: config, newOpacity: this.opacity);
      _bottomRenderer.updateOptions(newConfig: config, newOpacity: this.opacity);
      notifyListeners();
    }
  }

  /// 更新调试选项
  void updateDebugOptions({bool? showCollisionBoxes, bool? showTrackNumbers}) {
    bool changed = false;
    if (showCollisionBoxes != null && _showCollisionBoxes != showCollisionBoxes) {
      _showCollisionBoxes = showCollisionBoxes;
      _topRenderer.showCollisionBoxes = showCollisionBoxes;
      _scrollRenderer.showCollisionBoxes = showCollisionBoxes;
      _bottomRenderer.showCollisionBoxes = showCollisionBoxes;
      changed = true;
    }
    if (showTrackNumbers != null && _showTrackNumbers != showTrackNumbers) {
      _showTrackNumbers = showTrackNumbers;
      _topRenderer.showTrackNumbers = showTrackNumbers;
      _scrollRenderer.showTrackNumbers = showTrackNumbers;
      _bottomRenderer.showTrackNumbers = showTrackNumbers;
      changed = true;
    }
    if(changed) notifyListeners();
  }

  /// 设置暂停状态
  void setPaused(bool isPaused) {
    if (_isPaused == isPaused) return;
    _isPaused = isPaused;
    _topRenderer.setPaused(isPaused);
    _scrollRenderer.setPaused(isPaused);
    _bottomRenderer.setPaused(isPaused);
    notifyListeners();
  }

  /// 设置可见性
  void setVisibility(bool isVisible) {
    if (_isVisible == isVisible) return;
    _isVisible = isVisible;
    _topRenderer.setVisibility(isVisible);
    _scrollRenderer.setVisibility(isVisible);
    _bottomRenderer.setVisibility(isVisible);
    notifyListeners();
  }

  // 资源释放
  @override
  void dispose() {
    _topRenderer.dispose();
    _scrollRenderer.dispose();
    _bottomRenderer.dispose();
    super.dispose();
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