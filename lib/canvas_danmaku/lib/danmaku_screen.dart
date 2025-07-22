import 'utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart'; // 添加这一行导入Ticker
import 'danmaku_item.dart';
import 'scroll_danmaku_painter.dart';
import 'static_danmaku_painter.dart';
import 'danmaku_controller.dart';
import 'dart:ui' as ui;
import 'danmaku_option.dart';
import 'danmaku_content_item.dart';
import 'dart:math';

/// 轨道信息类
class TrackInfo {
  final List<DanmakuItem> items;
  final List<DanmakuItem> activeDanmakus; // 当前时间轴上活跃的弹幕
  double lastItemEndX;
  int itemCount;

  TrackInfo()
      : items = [],
        activeDanmakus = [],
        lastItemEndX = 0,
        itemCount = 0;

  void reset() {
    items.clear();
    activeDanmakus.clear();
    lastItemEndX = 0;
    itemCount = 0;
  }

  // 更新活跃弹幕列表
  void updateActiveDanmakus(int currentTime, int duration) {
    activeDanmakus.clear();
    for (var item in items) {
      // 检查弹幕是否在当前时间窗口内
      int elapsedTime = currentTime - item.creationTime;
      if (elapsedTime >= 0 && elapsedTime < duration * 1000) {
        activeDanmakus.add(item);
      }
    }
  }

  // 检查碰撞
  bool checkCollision(DanmakuItem newDanmaku, double viewWidth) {
    for (var existingDanmaku in activeDanmakus) {
      // 计算两个弹幕的位置
      double newLeft = newDanmaku.xPosition;
      double newRight = newLeft + newDanmaku.width;
      double existingLeft = existingDanmaku.xPosition;
      double existingRight = existingLeft + existingDanmaku.width;

      // 检查是否重叠
      if (!(newRight < existingLeft || newLeft > existingRight)) {
        return true; // 发生碰撞
      }
    }
    return false;
  }
}

class DanmakuScreen extends StatefulWidget {
  // 创建Screen后返回控制器
  final Function(DanmakuController) createdController;
  final DanmakuOption option;

  const DanmakuScreen({
    required this.createdController,
    required this.option,
    super.key,
  });

  @override
  State<DanmakuScreen> createState() => _DanmakuScreenState();
}

class _DanmakuScreenState extends State<DanmakuScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// 视图宽度
  double _viewWidth = 0;

  /// 弹幕控制器
  late DanmakuController _controller;

  /// 弹幕动画控制器
  late AnimationController _animationController;

  /// 静态弹幕动画控制器
  late AnimationController _staticAnimationController;
  
  /// 🔥 新增：计时器
  Ticker? _ticker;

  /// 弹幕配置
  DanmakuOption _option = DanmakuOption();

  /// 滚动弹幕
  final List<DanmakuItem> _scrollDanmakuItems = [];

  /// 顶部弹幕
  final List<DanmakuItem> _topDanmakuItems = [];

  /// 底部弹幕
  final List<DanmakuItem> _bottomDanmakuItems = [];

  /// 弹幕高度
  late double _danmakuHeight;

  /// 弹幕轨道数
  late int _trackCount;

  /// 弹幕轨道位置
  final List<double> _trackYPositions = [];

  /// 轨道信息
  final List<TrackInfo> _trackInfos = [];

  /// 内部计时器
  late int _tick;

  /// 运行状态
  bool _running = true;

  /// 是否是时间跳转或恢复状态
  bool _isTimeJumpOrRestoring = false;

  /// 每个轨道最大弹幕数量
  static const int maxDanmakuPerTrack = 5;

  /// 最小弹幕间距
  static const double minDanmakuGap = 100;

  /// 最大弹幕间距
  static const double maxDanmakuGap = 200;

  @override
  void initState() {
    super.initState();
    // 计时器初始化
    _tick = 0;
    _startTick();
    _option = widget.option;
    _controller = DanmakuController(
      onAddDanmaku: addDanmaku,
      onUpdateOption: updateOption,
      onPause: pause,
      onResume: resume,
      onClear: clearDanmakus,
      onResetAll: resetAll,
      onGetCurrentTick: getCurrentTick,
      onSetCurrentTick: setCurrentTick,
      onGetDanmakuStates: getDanmakuStates,
      onSetTimeJumpOrRestoring: setTimeJumpOrRestoring,
    );
    _controller.option = _option;
    widget.createdController.call(_controller);

    // 🔥 关键修复：设置更短的动画周期（500ms），增加动画流畅度
    // 使用更短的周期能够提高动画的平滑度
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    
    // 🔥 关键修复：确保动画一开始就启动，并设为连续重复模式
    _animationController.repeat();

    _staticAnimationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: _option.duration),
    );
    
    // 🔥 关键修复：启动静态弹幕动画控制器
    _staticAnimationController.forward();

    WidgetsBinding.instance.addObserver(this);
  }

  /// 处理 Android/iOS 应用后台或熄屏导致的动画问题
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      pause();
    }
  }

  @override
  void dispose() {
    // 确保在dispose之前停止并处理掉所有Ticker
    _running = false;
    
    // 移除观察者
    WidgetsBinding.instance.removeObserver(this);
    
    // 停止并释放Ticker（需要在super.dispose()之前）
    if (_ticker != null) {
      _ticker!.stop();
      _ticker!.dispose();
      _ticker = null;
    }
    
    // 安全地处理动画控制器
    try {
      if (_animationController.isAnimating) {
        _animationController.stop();
      }
      _animationController.dispose();
      
      if (_staticAnimationController.isAnimating) {
        _staticAnimationController.stop();
      }
      _staticAnimationController.dispose();
    } catch (e) {
      // 捕获可能的异常，避免崩溃
      print('处理动画控制器异常: $e');
    }
    
    // 清空弹幕列表，避免后续可能的引用
    _scrollDanmakuItems.clear();
    _topDanmakuItems.clear();
    _bottomDanmakuItems.clear();
    
    // 清空轨道信息
    for (var trackInfo in _trackInfos) {
      trackInfo.reset();
    }
    _trackInfos.clear();
    _trackYPositions.clear();
    
    super.dispose();
  }

  /// 获取当前时间
  int getCurrentTick() {
    return _tick;
  }

  /// 设置当前时间
  void setCurrentTick(int tick) {
    _tick = tick;
  }

  /// 设置时间跳转或恢复标记
  void setTimeJumpOrRestoring(bool value) {
    _isTimeJumpOrRestoring = value;
    if (value) {
      // 重置所有轨道信息
      for (var trackInfo in _trackInfos) {
        trackInfo.reset();
      }
    }
  }

  /// 彻底重置
  void resetAll() {
    clearDanmakus();
    for (var trackInfo in _trackInfos) {
      trackInfo.reset();
    }
  }

  /// 获取弹幕状态
  List<DanmakuState> getDanmakuStates() {
    final List<DanmakuState> states = [];
    
    // 处理滚动弹幕
    for (final item in _scrollDanmakuItems) {
      final elapsedTime = _tick - item.creationTime;
      final totalDuration = _option.duration * 1000;
      final remainingTime = totalDuration - elapsedTime;
      if (remainingTime > 0) {
        states.add(DanmakuState(
          content: item.content.text,
          type: item.content.type,
          normalizedProgress: elapsedTime / totalDuration,
          originalCreationTime: item.creationTime,
          remainingTime: remainingTime,
          yPosition: item.yPosition,
          trackIndex: _getTrackIndexFromYPosition(item.yPosition),
          color: item.content.color,
        ));
      }
    }
    
    // 处理顶部和底部弹幕（保持不变）
    for (final item in _topDanmakuItems) {
      final elapsedTime = _tick - item.creationTime;
      final totalDuration = 5000; // 顶部弹幕显示5秒
      final remainingTime = totalDuration - elapsedTime;
      if (remainingTime > 0) {
        states.add(DanmakuState(
          content: item.content.text,
          type: item.content.type,
          normalizedProgress: elapsedTime / totalDuration,
          originalCreationTime: item.creationTime,
          remainingTime: remainingTime,
          yPosition: item.yPosition,
          trackIndex: _getTrackIndexFromYPosition(item.yPosition),
          color: item.content.color,
        ));
      }
    }
    
    for (final item in _bottomDanmakuItems) {
      final elapsedTime = _tick - item.creationTime;
      final totalDuration = 5000; // 底部弹幕显示5秒
      final remainingTime = totalDuration - elapsedTime;
      if (remainingTime > 0) {
        states.add(DanmakuState(
          content: item.content.text,
          type: item.content.type,
          normalizedProgress: elapsedTime / totalDuration,
          originalCreationTime: item.creationTime,
          remainingTime: remainingTime,
          yPosition: item.yPosition,
          trackIndex: _getTrackIndexFromYPosition(item.yPosition),
          color: item.content.color,
        ));
      }
    }
    
    return states;
  }

  /// 根据Y位置获取轨道索引
  int _getTrackIndexFromYPosition(double yPosition) {
    for (int i = 0; i < _trackYPositions.length; i++) {
      if ((_trackYPositions[i] - yPosition).abs() < 1.0) {
        return i;
      }
    }
    return 0;
  }

  /// 添加弹幕
  void addDanmaku(DanmakuContentItem content) {
    if (!_running || !mounted) {
      return;
    }

    // 处理时间偏移
    final adjustedCreationTime = _tick - content.timeOffset;

    // 在这里提前创建 Paragraph 缓存防止卡顿
    final textPainter = TextPainter(
      text: TextSpan(
          text: content.text, style: TextStyle(fontSize: _option.fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    final danmakuWidth = textPainter.width;

    final ui.Paragraph paragraph =
        Utils.generateParagraph(
          content, 
          danmakuWidth, 
          _option.fontSize,
          showStroke: _option.showStroke,
          strokeWidth: _option.strokeWidth,
          // 不传递strokeColor，让getShadowColor方法根据文本颜色自动计算描边颜色
          // strokeColor: Color(_option.strokeColor),
        );

    ui.Paragraph? strokeParagraph;

    bool added = false;
    if (content.type == DanmakuItemType.scroll && !_option.hideScroll) {
      _addScrollDanmaku(content, danmakuWidth, adjustedCreationTime, paragraph, strokeParagraph);
      added = true;
    } else if (content.type == DanmakuItemType.top && !_option.hideTop) {
      added = _addTopDanmaku(content, danmakuWidth, adjustedCreationTime, paragraph, strokeParagraph);
    } else if (content.type == DanmakuItemType.bottom && !_option.hideBottom) {
      added = _addBottomDanmaku(content, danmakuWidth, adjustedCreationTime, paragraph, strokeParagraph);
    }

    if (added && !_animationController.isAnimating) {
      _animationController.repeat();
    }

    // 清理过期弹幕
    _cleanupDanmaku();

    /// 重绘静态弹幕
    setState(() {
      _staticAnimationController.value = 0;
    });
  }

  /// 添加滚动弹幕
  void _addScrollDanmaku(
    DanmakuContentItem content,
    double danmakuWidth,
    int creationTime,
    ui.Paragraph paragraph,
    ui.Paragraph? strokeParagraph,
  ) {
    // 从轨道0开始尝试
    int currentTrack = 0;
    bool added = false;

    while (!added && currentTrack < _trackInfos.length) {
      TrackInfo trackInfo = _trackInfos[currentTrack];
      
      // 更新当前轨道的活跃弹幕
      trackInfo.updateActiveDanmakus(_tick, _option.duration);

      // 创建新弹幕 - 所有弹幕都从屏幕右侧开始
      final danmaku = DanmakuItem(
        yPosition: _trackYPositions[currentTrack],
        xPosition: _viewWidth, // 始终从屏幕右侧开始
        width: danmakuWidth,
        creationTime: creationTime,
        content: content,
        paragraph: paragraph,
        strokeParagraph: strokeParagraph,
      );

      // 检查碰撞 - 始终进行碰撞检测
      if (!trackInfo.checkCollision(danmaku, _viewWidth)) {
        // 更新轨道信息
        trackInfo.items.add(danmaku);
        trackInfo.lastItemEndX = _viewWidth; // 更新最后位置为屏幕右侧
        
        // 添加到显示列表
        _scrollDanmakuItems.add(danmaku);
        added = true;
      } else {
        currentTrack++; // 尝试下一个轨道
      }
    }

    // 如果所有轨道都尝试过还是没有找到合适的位置，就放弃这条弹幕
  }

  /// 添加顶部弹幕
  bool _addTopDanmaku(
    DanmakuContentItem content,
    double danmakuWidth,
    int creationTime,
    ui.Paragraph paragraph,
    ui.Paragraph? strokeParagraph,
  ) {
    // 从上往下找空闲轨道，使用全部轨道
    for (int i = 0; i < _trackYPositions.length; i++) {
      double yPosition = _trackYPositions[i];
      bool canAdd = true;
      
      // 检查该轨道是否有活跃的顶部弹幕
      for (var item in _topDanmakuItems) {
        if (item.yPosition == yPosition) {
          // 检查时间窗口是否重叠
          int elapsedTime = _tick - item.creationTime;
          if (elapsedTime < 5000) {  // 5秒显示时间
            canAdd = false;
            break;
          }
        }
      }

      if (canAdd) {
        _topDanmakuItems.add(DanmakuItem(
          yPosition: yPosition,
          xPosition: (_viewWidth - danmakuWidth) / 2,  // 居中显示
          width: danmakuWidth,
          creationTime: creationTime,
          content: content,
          paragraph: paragraph,
          strokeParagraph: strokeParagraph,
        ));
        return true;
      }
    }
    return false;
  }

  /// 添加底部弹幕
  bool _addBottomDanmaku(
    DanmakuContentItem content,
    double danmakuWidth,
    int creationTime,
    ui.Paragraph paragraph,
    ui.Paragraph? strokeParagraph,
  ) {
    // 从下往上找空闲轨道，使用全部轨道
    for (int i = _trackYPositions.length - 1; i >= 0; i--) {
      double yPosition = _trackYPositions[i];
      bool canAdd = true;
      
      // 检查该轨道是否有活跃的底部弹幕
      for (var item in _bottomDanmakuItems) {
        if (item.yPosition == yPosition) {
          // 检查时间窗口是否重叠
          int elapsedTime = _tick - item.creationTime;
          if (elapsedTime < 5000) {  // 5秒显示时间
            canAdd = false;
            break;
          }
        }
      }

      if (canAdd) {
        _bottomDanmakuItems.add(DanmakuItem(
          yPosition: yPosition,
          xPosition: (_viewWidth - danmakuWidth) / 2,  // 居中显示
          width: danmakuWidth,
          creationTime: creationTime,
          content: content,
          paragraph: paragraph,
          strokeParagraph: strokeParagraph,
        ));
        return true;
      }
    }
    return false;
  }

  /// 清理过期弹幕
  void _cleanupDanmaku() {
    // 清理滚动弹幕并更新轨道信息
    for (var trackInfo in _trackInfos) {
      trackInfo.items.removeWhere((item) {
        bool shouldRemove = item.xPosition + item.width < 0;
        return shouldRemove;
      });
      // 更新活跃弹幕
      trackInfo.updateActiveDanmakus(_tick, _option.duration);
    }
    _scrollDanmakuItems.removeWhere((item) => item.xPosition + item.width < 0);

    // 清理静态弹幕
    _topDanmakuItems.removeWhere((item) {
      int elapsedTime = _tick - item.creationTime;
      return elapsedTime > 5000;  // 5秒后移除
    });
    _bottomDanmakuItems.removeWhere((item) {
      int elapsedTime = _tick - item.creationTime;
      return elapsedTime > 5000;  // 5秒后移除
    });
  }

  /// 暂停
  void pause() {
    if (_running) {
      // 安全检查：确保组件仍然挂载
      if (mounted) {
        setState(() {
          _running = false;
        });
      } else {
        _running = false;
      }
      
      // 暂停Ticker
      _ticker?.muted = true;
      
      // 🔥 关键修复：暂停时保持动画控制器活跃，但不增加tick值
      // 这样弹幕会保持可见，但不会移动位置
      if (_animationController.isAnimating) {
        // 不停止动画控制器，让它继续驱动重绘
        // 但tick值不再增加，所以弹幕位置不会变化
      }
    }
  }

  /// 恢复
  void resume() {
    if (!_running) {
      // 安全检查：确保组件仍然挂载
      if (mounted) {
        setState(() {
          _running = true;
        });
      } else {
        _running = true;
        return; // 如果组件已经卸载，不执行后续操作
      }
      
      // 恢复Ticker
      _ticker?.muted = false;
      
      // 确保动画控制器正常运行
      if (!_animationController.isAnimating) {
        _animationController.repeat();
      }
      
      // 确保静态动画控制器也正常运行
      if (!_staticAnimationController.isAnimating) {
        _staticAnimationController.reset();
        _staticAnimationController.forward();
      }
      
      // 强制重绘，确保弹幕能够立即显示
      // 安全检查：确保组件仍然挂载
      if (mounted) {
        setState(() {});
      }
    }
  }

  /// 更新弹幕设置
  void updateOption(DanmakuOption option) {
    // 添加mounted检查，确保组件仍然挂载
    if (!mounted) return;
    
    bool needRestart = false;
    if (_animationController.isAnimating) {
      _animationController.stop();
      needRestart = true;
    }

    /// 需要隐藏弹幕时清理已有弹幕
    if (option.hideScroll && !_option.hideScroll) {
      _scrollDanmakuItems.clear();
      for (var trackInfo in _trackInfos) {
        trackInfo.reset();
      }
    }
    if (option.hideTop && !_option.hideTop) {
      _topDanmakuItems.clear();
    }
    if (option.hideBottom && !_option.hideBottom) {
      _bottomDanmakuItems.clear();
    }
    _option = option;
    _controller.option = _option;

    /// 清理已经存在的 Paragraph 缓存
    for (DanmakuItem item in _scrollDanmakuItems) {
      item.paragraph = null;
      item.strokeParagraph = null;
    }
    for (DanmakuItem item in _topDanmakuItems) {
      item.paragraph = null;
      item.strokeParagraph = null;
    }
    for (DanmakuItem item in _bottomDanmakuItems) {
      item.paragraph = null;
      item.strokeParagraph = null;
    }
    if (needRestart) {
      _animationController.repeat();
    }
    
    // 添加mounted检查，确保组件仍然挂载
    if (mounted) {
      setState(() {});
    }
  }

  /// 清空弹幕
  void clearDanmakus() {
    setState(() {
      _scrollDanmakuItems.clear();
      _topDanmakuItems.clear();
      _bottomDanmakuItems.clear();
      for (var trackInfo in _trackInfos) {
        trackInfo.reset();
      }
    });
    _animationController.stop();
  }

  /// 确定顶部弹幕是否可以添加
  bool _topCanAddToTrack(double yPosition) {
    for (var item in _topDanmakuItems) {
      if (item.yPosition == yPosition) {
        return false;
      }
    }
    return true;
  }

  /// 确定底部弹幕是否可以添加
  bool _bottomCanAddToTrack(double yPosition) {
    for (var item in _bottomDanmakuItems) {
      if (item.yPosition == yPosition) {
        return false;
      }
    }
    return true;
  }

  // 修改_startTick方法
  void _startTick() {
    // 确保之前的ticker被处理
    _ticker?.dispose();
    
    // 创建新的ticker
    _ticker = createTicker((elapsed) {
      if (!mounted || !_running) return;
      
      // 每帧更新时间（通常是16.67ms或与刷新率同步）
      _tick += 16;
      
      // 强制重绘（仅在状态变化时）
      if (mounted) {
        setState(() {});
      }
    });
    
    // 启动ticker
    _ticker!.start();
    
    // 设置运行状态
    _running = true;
  }
  
  // 新增：更新时间戳的方法，由外部定时器调用
  void updateTick(int delta) {
    if (_running) {
      _tick += delta;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPainter = TextPainter(
      text: TextSpan(text: '弹幕', style: TextStyle(fontSize: _option.fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    _danmakuHeight = textPainter.height;

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth != _viewWidth) {
        _viewWidth = constraints.maxWidth;
      }

      _trackCount = (constraints.maxHeight * _option.area / _danmakuHeight).floor() - 1;

      // 初始化或更新轨道信息
      if (_trackYPositions.length != _trackCount) {
        _trackYPositions.clear();
        _trackInfos.clear();
        for (int i = 0; i < _trackCount; i++) {
          _trackYPositions.add(i * _danmakuHeight);
          _trackInfos.add(TrackInfo());
        }
      }

      return ClipRect(
        child: IgnorePointer(
          child: Opacity(
            // 使用映射后的不透明度值
            opacity: _debugOpacity(),
            child: Stack(children: [
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: ScrollDanmakuPainter(
                        _animationController.value,
                        _scrollDanmakuItems,
                        _option.duration,
                        _option.fontSize,
                        _option.showStroke,
                        _danmakuHeight,
                        _running,
                        _tick,
                        _option.showCollisionBoxes,
                        _option.showTrackNumbers,
                        _trackYPositions,
                        option: _option,
                      ),
                      child: Container(),
                    );
                  },
                ),
              ),
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _staticAnimationController,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: StaticDanmakuPainter(
                        _staticAnimationController.value,
                        _topDanmakuItems,
                        _bottomDanmakuItems,
                        _option.duration,
                        _option.fontSize,
                        _option.showStroke,
                        _danmakuHeight,
                        _running,
                        _tick,
                        _option.showCollisionBoxes,
                        _option.showTrackNumbers,
                        _trackYPositions,
                        option: _option,
                      ),
                      child: Container(),
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }

  // 调试函数，查看不透明度值
  double _debugOpacity() {
    double mappedValue = _mapOpacity(_option.opacity);
    //print("原始不透明度: ${_option.opacity}, 映射后不透明度: $mappedValue");
    return mappedValue;
  }

  // 将原始不透明度值进行非线性映射，避免低透明度时弹幕过快消失
  // 与nipaPlay内核保持一致的不透明度处理
  double _mapOpacity(double originalOpacity) {
    // 使用分段线性函数，确保整个范围内都有明显的变化
    // 0%   -> 10%（最低底线，确保永远可见）
    // 10%  -> 40%（低值区域快速提升可见度）
    // 30%  -> 60%（中值区域适度提升）
    // 50%  -> 75%（中高值区域）
    // 70%  -> 85%（高值区域）
    // 100% -> 100%（最高值保持不变）
    
    if (originalOpacity <= 0.0) {
      return 0.0; // 安全检查
    } else if (originalOpacity < 0.1) {
      // 0-10% 映射到 10-40%
      return 0.1 + (originalOpacity * 3.0);
    } else if (originalOpacity < 0.3) {
      // 10-30% 映射到 40-60%
      return 0.4 + ((originalOpacity - 0.1) * 1.0);
    } else if (originalOpacity < 0.5) {
      // 30-50% 映射到 60-75%
      return 0.6 + ((originalOpacity - 0.3) * 0.75);
    } else if (originalOpacity < 0.7) {
      // 50-70% 映射到 75-85%
      return 0.75 + ((originalOpacity - 0.5) * 0.5);
    } else {
      // 70-100% 映射到 85-100%
      return 0.85 + ((originalOpacity - 0.7) * 0.5);
    }
  }
}
