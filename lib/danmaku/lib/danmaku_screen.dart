import 'utils.dart';
import 'package:flutter/material.dart';
import 'danmaku_item.dart';
import 'scroll_danmaku_painter.dart';
import 'static_danmaku_painter.dart';
import 'danmaku_controller.dart';
import 'dart:ui' as ui;
import 'danmaku_option.dart';
import 'danmaku_content_item.dart';
import 'dart:math';
import '../../utils/globals.dart' as globals;

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

  /// 弹幕配置
  late DanmakuOption _option;

  /// 滚动弹幕
  final List<DanmakuItem> _scrollDanmakuItems = [];

  /// 顶部弹幕
  final List<DanmakuItem> _topDanmakuItems = [];

  /// 底部弹幕
  final List<DanmakuItem> _bottomDanmakuItems = [];

  /// 🔥 新增：溢出弹幕数据 - 溢出层
  final List<DanmakuItem> _overflowScrollDanmakuItems = [];
  final List<DanmakuItem> _overflowTopDanmakuItems = [];
  final List<DanmakuItem> _overflowBottomDanmakuItems = [];

  /// 弹幕高度
  late double _danmakuHeight;

  /// 弹幕轨道数
  late int _trackCount;

  /// 弹幕轨道位置
  final List<double> _trackYPositions = [];

  /// 内部计时器
  late int _tick;

  /// 运行状态
  bool _running = false;

  /// 🔥 添加轨道分配计数器，确保均匀分布
  int _currentScrollTrack = 0;
  int _currentTopTrack = 0;
  int _currentBottomTrack = 0;

  /// 🔥 新增：溢出层轨道分配计数器
  int _overflowScrollTrack = 0;
  int _overflowTopTrack = 0;
  int _overflowBottomTrack = 0;

  /// 🔥 修改：直接使用播放暂停状态，不需要额外的时间暂停状态
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    // 计时器初始化
    _tick = 0;
    _running = true; // 🔥 确保初始化时就开始运行
    _startTick();
    _option = widget.option;
    _controller = DanmakuController(
      onAddDanmaku: addDanmaku,
      onUpdateOption: updateOption,
      onPause: pause,
      onResume: resume,
      onClear: clearDanmakus,
    );
    _controller.option = _option;
    widget.createdController.call(
      _controller,
    );

    _animationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: _option.duration),
    )..repeat();

    _staticAnimationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: _option.duration),
    );

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
    _running = false;
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    _staticAnimationController.dispose();
    super.dispose();
  }

  /// 添加弹幕
  void addDanmaku(DanmakuContentItem content) {
    if (!_running || !mounted) {
      return;
    }
    // 在这里提前创建 Paragraph 缓存防止卡顿
    final textPainter = TextPainter(
      text: TextSpan(
          text: content.text, style: TextStyle(fontSize: _option.fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    final danmakuWidth = textPainter.width;

    final ui.Paragraph paragraph =
        Utils.generateParagraph(content, danmakuWidth, _option.fontSize);

    ui.Paragraph? strokeParagraph;

    // 🔥 关键修改：考虑时间偏移，模拟弹幕已经运动了一段时间
    final adjustedCreationTime = _tick - content.timeOffset;

    // 🔥 完全照抄NipaPlay的轨道分配策略：优先寻找最合适的轨道
    bool danmakuAdded = false;
    
    if (content.type == DanmakuItemType.scroll && !_option.hideScroll) {
      // 🔥 滚动弹幕：遍历所有轨道，优先分配不会碰撞的轨道（照抄NipaPlay）
      int? availableTrack;
      for (int track = 0; track < _trackYPositions.length; track++) {
        final yPosition = _trackYPositions[track];
        if (_scrollCanAddToTrack(yPosition, danmakuWidth)) {
          availableTrack = track;
          break;
        }
      }
      
      if (availableTrack != null) {
        final yPosition = _trackYPositions[availableTrack];
        _scrollDanmakuItems.add(DanmakuItem(
            content: content,
            xPosition: _viewWidth,
            yPosition: yPosition,
            width: danmakuWidth,
            creationTime: adjustedCreationTime,
            paragraph: paragraph,
            strokeParagraph: strokeParagraph));
        danmakuAdded = true;
      } else {
        // 🔥 主层满了，尝试分配到溢出层
        if (_option.massiveMode && _trackYPositions.isNotEmpty) {
          // 溢出层重新从第一轨道开始分配
          _overflowScrollTrack = (_overflowScrollTrack + 1) % _trackYPositions.length;
          final yPosition = _trackYPositions[_overflowScrollTrack];
          _overflowScrollDanmakuItems.add(DanmakuItem(
              content: content,
              xPosition: _viewWidth,
              yPosition: yPosition,
              width: danmakuWidth,
              creationTime: adjustedCreationTime,
              paragraph: paragraph,
              strokeParagraph: strokeParagraph));
          danmakuAdded = true;
        }
        // 如果不允许堆叠，弹幕会被丢弃（danmakuAdded保持false）
      }
    } else if (content.type == DanmakuItemType.top && !_option.hideTop) {
      // 🔥 顶部弹幕：从顶部开始逐轨道分配（照抄NipaPlay）
      for (int track = 0; track < _trackYPositions.length; track++) {
        final yPosition = _trackYPositions[track];
        if (_topCanAddToTrack(yPosition)) {
          _topDanmakuItems.add(DanmakuItem(
              content: content,
              xPosition: (_viewWidth - danmakuWidth) / 2,
              yPosition: yPosition,
              width: danmakuWidth,
              creationTime: adjustedCreationTime,
              paragraph: paragraph,
              strokeParagraph: strokeParagraph));
          danmakuAdded = true;
          break;
        }
      }
      
      // 🔥 主层满了，尝试分配到溢出层
      if (!danmakuAdded && _option.massiveMode && _trackYPositions.isNotEmpty) {
        // 溢出层重新从第一轨道开始分配
        _overflowTopTrack = (_overflowTopTrack + 1) % _trackYPositions.length;
        final yPosition = _trackYPositions[_overflowTopTrack];
        _overflowTopDanmakuItems.add(DanmakuItem(
            content: content,
            xPosition: (_viewWidth - danmakuWidth) / 2,
            yPosition: yPosition,
            width: danmakuWidth,
            creationTime: adjustedCreationTime,
            paragraph: paragraph,
            strokeParagraph: strokeParagraph));
        danmakuAdded = true;
      }
    } else if (content.type == DanmakuItemType.bottom && !_option.hideBottom) {
      // 🔥 底部弹幕：从底部开始逐轨道分配（照抄NipaPlay）
      for (int track = 0; track < _trackYPositions.length; track++) {
        final yPosition = _trackYPositions[track];
        if (_bottomCanAddToTrack(yPosition)) {
          _bottomDanmakuItems.add(DanmakuItem(
              content: content,
              xPosition: (_viewWidth - danmakuWidth) / 2,
              yPosition: yPosition,
              width: danmakuWidth,
              creationTime: adjustedCreationTime,
              paragraph: paragraph,
              strokeParagraph: strokeParagraph));
          danmakuAdded = true;
          break;
        }
      }
      
      // 🔥 主层满了，尝试分配到溢出层
      if (!danmakuAdded && _option.massiveMode && _trackYPositions.isNotEmpty) {
        // 溢出层重新从第一轨道开始分配
        _overflowBottomTrack = (_overflowBottomTrack + 1) % _trackYPositions.length;
        final yPosition = _trackYPositions[_overflowBottomTrack];
        _overflowBottomDanmakuItems.add(DanmakuItem(
            content: content,
            xPosition: (_viewWidth - danmakuWidth) / 2,
            yPosition: yPosition,
            width: danmakuWidth,
            creationTime: adjustedCreationTime,
            paragraph: paragraph,
            strokeParagraph: strokeParagraph));
        danmakuAdded = true;
      }
    }

    // 🔥 修改：只有在未暂停时才启动动画控制器
    if (!_isPaused && _running && mounted) {
      if ((_scrollDanmakuItems.isNotEmpty || _overflowScrollDanmakuItems.isNotEmpty) &&
          !_animationController.isAnimating) {
        _animationController.repeat();
      }
      if ((_topDanmakuItems.isNotEmpty || _bottomDanmakuItems.isNotEmpty ||
          _overflowTopDanmakuItems.isNotEmpty || _overflowBottomDanmakuItems.isNotEmpty)) {
        _staticAnimationController.value = 0;
      }
    }
    // 移除屏幕外滚动弹幕 - 主层和溢出层
    _scrollDanmakuItems.removeWhere((item) => item.xPosition + item.width < 0);
    _overflowScrollDanmakuItems.removeWhere((item) => item.xPosition + item.width < 0);
    // 🔥 修改：顶部弹幕显示时间改为5秒，与NipaPlay保持一致 - 主层和溢出层
    _topDanmakuItems.removeWhere(
        (item) => ((_tick - item.creationTime) > (5 * 1000))); // 5秒而不是_option.duration
    _overflowTopDanmakuItems.removeWhere(
        (item) => ((_tick - item.creationTime) > (5 * 1000))); // 5秒而不是_option.duration
    // 🔥 修改：底部弹幕显示时间改为5秒，与NipaPlay保持一致 - 主层和溢出层
    _bottomDanmakuItems.removeWhere(
        (item) => ((_tick - item.creationTime) > (5 * 1000))); // 5秒而不是_option.duration
    _overflowBottomDanmakuItems.removeWhere(
        (item) => ((_tick - item.creationTime) > (5 * 1000))); // 5秒而不是_option.duration

    /// 重绘静态弹幕
    setState(() {
      _staticAnimationController.value = 0;
    });
  }

  /// 暂停
  void pause() {
    setState(() {
      _isPaused = true;
    });
    // 🔥 关键修改：暂停时停止动画控制器
    _animationController.stop();
    _staticAnimationController.stop();
  }

  /// 恢复
  void resume() {
    setState(() {
      _isPaused = false;
    });
    
    // 🔥 关键修改：恢复时重新启动动画控制器
    if (_running && mounted) {
      if (_scrollDanmakuItems.isNotEmpty || _overflowScrollDanmakuItems.isNotEmpty) {
        _animationController.repeat();
      }
      if (_topDanmakuItems.isNotEmpty || _bottomDanmakuItems.isNotEmpty ||
          _overflowTopDanmakuItems.isNotEmpty || _overflowBottomDanmakuItems.isNotEmpty) {
        _staticAnimationController.value = 0;
      }
    }
  }

  /// 更新弹幕设置
  void updateOption(DanmakuOption option) {
    bool needRestart = false;
    if (_animationController.isAnimating) {
      _animationController.stop();
      needRestart = true;
    }

    /// 需要隐藏弹幕时清理已有弹幕 - 主层和溢出层
    if (option.hideScroll && !_option.hideScroll) {
      _scrollDanmakuItems.clear();
      _overflowScrollDanmakuItems.clear();
    }
    if (option.hideTop && !_option.hideTop) {
      _topDanmakuItems.clear();
      _overflowTopDanmakuItems.clear();
    }
    if (option.hideBottom && !_option.hideBottom) {
      _bottomDanmakuItems.clear();
      _overflowBottomDanmakuItems.clear();
    }
    _option = option;
    _controller.option = _option;

    /// 清理已经存在的 Paragraph 缓存 - 主层和溢出层
    for (DanmakuItem item in _scrollDanmakuItems) {
      if (item.paragraph != null) {
        item.paragraph = null;
      }
      if (item.strokeParagraph != null) {
        item.strokeParagraph = null;
      }
    }
    for (DanmakuItem item in _overflowScrollDanmakuItems) {
      if (item.paragraph != null) {
        item.paragraph = null;
      }
      if (item.strokeParagraph != null) {
        item.strokeParagraph = null;
      }
    }
    for (DanmakuItem item in _topDanmakuItems) {
      if (item.paragraph != null) {
        item.paragraph = null;
      }
      if (item.strokeParagraph != null) {
        item.strokeParagraph = null;
      }
    }
    for (DanmakuItem item in _overflowTopDanmakuItems) {
      if (item.paragraph != null) {
        item.paragraph = null;
      }
      if (item.strokeParagraph != null) {
        item.strokeParagraph = null;
      }
    }
    for (DanmakuItem item in _bottomDanmakuItems) {
      if (item.paragraph != null) {
        item.paragraph = null;
      }
      if (item.strokeParagraph != null) {
        item.strokeParagraph = null;
      }
    }
    for (DanmakuItem item in _overflowBottomDanmakuItems) {
      if (item.paragraph != null) {
        item.paragraph = null;
      }
      if (item.strokeParagraph != null) {
        item.strokeParagraph = null;
      }
    }
    if (needRestart) {
      _animationController.repeat();
    }
    setState(() {});
  }

  /// 清空弹幕
  void clearDanmakus() {
    setState(() {
      _scrollDanmakuItems.clear();
      _topDanmakuItems.clear();
      _bottomDanmakuItems.clear();
      _overflowScrollDanmakuItems.clear();
      _overflowTopDanmakuItems.clear();
      _overflowBottomDanmakuItems.clear();
      
      // 🔥 重置轨道计数器 - 主层和溢出层
      _currentScrollTrack = 0;
      _currentTopTrack = 0;
      _currentBottomTrack = 0;
      _overflowScrollTrack = 0;
      _overflowTopTrack = 0;
      _overflowBottomTrack = 0;
    });
    _animationController.stop();
  }

  /// 确定滚动弹幕是否可以添加 - 照抄NipaPlay逻辑
  bool _scrollCanAddToTrack(double yPosition, double newDanmakuWidth) {
    for (var item in _scrollDanmakuItems) {
      if (item.yPosition == yPosition) {
        // 🔥 完全照抄NipaPlay的碰撞检测逻辑
        final existingTime = item.creationTime / 1000.0; // 转换为秒
        final newTime = _tick / 1000.0; // 转换为秒
        
        final existingWidth = item.width;
        final newWidth = newDanmakuWidth;
        
        // 计算现有弹幕的当前位置（10秒运动时间）
        final existingElapsed = newTime - existingTime;
        final existingPosition = _viewWidth - (existingElapsed / 10) * (_viewWidth + existingWidth);
        final existingLeft = existingPosition;
        final existingRight = existingPosition + existingWidth;
        
        // 计算新弹幕的当前位置
        final newElapsed = 0.0; // 新弹幕刚开始
        final newPosition = _viewWidth - (newElapsed / 10) * (_viewWidth + newWidth);
        final newLeft = newPosition;
        final newRight = newPosition + newWidth;
        
        // 安全距离：屏幕宽度的2%
        final safetyMargin = _viewWidth * 0.02;
        
        // 如果两个弹幕在屏幕上的位置有重叠，且距离小于安全距离，则会发生碰撞
        if ((existingRight + safetyMargin > newLeft) && 
            (existingLeft - safetyMargin < newRight)) {
          return false;
        }
      }
    }
    return true;
  }

  /// 确定顶部弹幕是否可以添加 - 照抄NipaPlay逻辑
  bool _topCanAddToTrack(double yPosition) {
    for (var item in _topDanmakuItems) {
      if (item.yPosition == yPosition) {
        // 🔥 完全照抄NipaPlay的时间重叠检测逻辑
        final existingTime = item.creationTime / 1000.0; // 转换为秒
        final newTime = _tick / 1000.0; // 转换为秒
        
        // 计算两个弹幕的显示时间范围
        final existingStartTime = existingTime;
        final existingEndTime = existingTime + 5; // 顶部弹幕显示5秒
        
        final newStartTime = newTime;
        final newEndTime = newTime + 5;
        
        // 增加安全时间间隔，避免弹幕过于接近
        const safetyTime = 0.5; // 0.5秒的安全时间
        
        // 如果两个弹幕的显示时间有重叠，且间隔小于安全时间，则会发生重叠
        if (newStartTime <= existingEndTime + safetyTime && 
            newEndTime + safetyTime >= existingStartTime) {
          return false;
        }
      }
    }
    return true;
  }

  /// 确定底部弹幕是否可以添加 - 照抄NipaPlay逻辑
  bool _bottomCanAddToTrack(double yPosition) {
    for (var item in _bottomDanmakuItems) {
      if (item.yPosition == yPosition) {
        // 🔥 完全照抄NipaPlay的时间重叠检测逻辑
        final existingTime = item.creationTime / 1000.0; // 转换为秒
        final newTime = _tick / 1000.0; // 转换为秒
        
        // 计算两个弹幕的显示时间范围
        final existingStartTime = existingTime;
        final existingEndTime = existingTime + 5; // 底部弹幕显示5秒
        
        final newStartTime = newTime;
        final newEndTime = newTime + 5;
        
        // 增加安全时间间隔，避免弹幕过于接近
        const safetyTime = 0.5; // 0.5秒的安全时间
        
        // 如果两个弹幕的显示时间有重叠，且间隔小于安全时间，则会发生重叠
        if (newStartTime <= existingEndTime + safetyTime && 
            newEndTime + safetyTime >= existingStartTime) {
          return false;
        }
      }
    }
    return true;
  }

  // 基于Stopwatch的计时器同步
  void _startTick() async {
    final stopwatch = Stopwatch()..start();
    int lastElapsedTime = 0;

    while (_running && mounted) {
      await Future.delayed(const Duration(milliseconds: 1));
      int currentElapsedTime = stopwatch.elapsedMilliseconds; // 获取当前的已用时间
      int delta = currentElapsedTime - lastElapsedTime; // 计算自上次记录以来的时间差
      
      // 🔥 关键修改：只有在未暂停时才更新时间
      if (!_isPaused) {
        _tick += delta;
      }
      
      lastElapsedTime = currentElapsedTime; // 更新最后记录的时间
    }

    stopwatch.stop();
  }

  @override
  Widget build(BuildContext context) {
    /// 🔥 修改：统一设置垂直间距为10.0，电脑和手机保持一致
    final verticalSpacing = 10.0;
    final textPainter = TextPainter(
      text: TextSpan(text: '弹幕', style: TextStyle(fontSize: _option.fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    _danmakuHeight = textPainter.height;
    
    return LayoutBuilder(builder: (context, constraints) {
      /// 计算视图宽度
      if (constraints.maxWidth != _viewWidth) {
        _viewWidth = constraints.maxWidth;
      }

      /// 计算轨道数量，考虑垂直间距
      final trackHeight = _danmakuHeight + verticalSpacing;
      _trackCount = ((constraints.maxHeight * _option.area - verticalSpacing) / trackHeight).floor();
      
      /// 重新计算轨道位置，加入垂直间距
      _trackYPositions.clear();
      for (int i = 0; i < _trackCount; i++) {
        _trackYPositions.add(i * trackHeight + verticalSpacing);
      }
      
      return ClipRect(
        child: IgnorePointer(
          child: Opacity(
            opacity: _option.opacity,
            child: Stack(children: [
              // 主层弹幕
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
                        _isPaused), // 🔥 传递暂停状态
                    child: Container(),
                  );
                },
              )),
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
                        _isPaused), // 🔥 传递暂停状态
                    child: Container(),
                  );
                },
              )),
              // 🔥 溢出层弹幕
              RepaintBoundary(
                  child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: ScrollDanmakuPainter(
                        _animationController.value,
                        _overflowScrollDanmakuItems,
                        _option.duration,
                        _option.fontSize,
                        _option.showStroke,
                        _danmakuHeight,
                        _running,
                        _tick,
                        _isPaused), // 🔥 传递暂停状态
                    child: Container(),
                  );
                },
              )),
              RepaintBoundary(
                  child: AnimatedBuilder(
                animation: _staticAnimationController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: StaticDanmakuPainter(
                        _staticAnimationController.value,
                        _overflowTopDanmakuItems,
                        _overflowBottomDanmakuItems,
                        _option.duration,
                        _option.fontSize,
                        _option.showStroke,
                        _danmakuHeight,
                        _running,
                        _tick,
                        _isPaused), // 🔥 传递暂停状态
                    child: Container(),
                  );
                },
              )),
            ]),
          ),
        ),
      );
    });
  }


}
