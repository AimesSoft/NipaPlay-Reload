import 'dart:async';
import 'dart:math';
import 'utils/utils.dart';
import 'package:flutter/material.dart';
import 'danmaku_timeline.dart';
import 'models/danmaku_item.dart';
import 'scroll_danmaku_painter.dart';
import 'special_danmaku_painter.dart';
import 'static_danmaku_painter.dart';
import 'danmaku_controller.dart';
import 'dart:ui' as ui;
import 'models/danmaku_option.dart';
import 'models/danmaku_content_item.dart';

class DanmakuScreen extends StatefulWidget {
  // 创建Screen后返回控制器
  final void Function(DanmakuController) createdController;
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
  DanmakuOption _option = DanmakuOption();

  /// 滚动弹幕
  final List<DanmakuItem> _scrollDanmakuItems = [];

  /// 顶部弹幕
  final List<DanmakuItem> _topDanmakuItems = [];

  /// 底部弹幕
  final List<DanmakuItem> _bottomDanmakuItems = [];

  /// 高级弹幕
  final List<DanmakuItem> _specialDanmakuItems = [];

  /// 弹幕高度
  late double _danmakuHeight;

  /// 弹幕轨道数
  late int _trackCount;

  /// 弹幕轨道位置
  final List<double> _trackYPositions = [];

  late final _random = Random();

  /// 内部计时器
  int get _tick => _stopwatch.elapsedMilliseconds;

  final _stopwatch = Stopwatch();
  Timer? _cleanupTimer;

  /// 运行状态
  bool _running = true;

  @override
  void initState() {
    super.initState();
    _option = widget.option;
    _animationController = AnimationController(
      vsync: this,
      duration: _animationDuration(_option),
    )..repeat();

    _staticAnimationController = AnimationController(
      vsync: this,
      duration: _animationDuration(_option),
    );

    _startTick();
    _controller = DanmakuController(
      onAddDanmaku: addDanmaku,
      onUpdateOption: updateOption,
      onPause: pause,
      onResume: resume,
      onClear: clearDanmakus,
    );
    _controller.option = _option;
    WidgetsBinding.instance.addObserver(this);
    widget.createdController(_controller);
  }

  /// 处理 Android/iOS 应用后台或熄屏导致的动画问题
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        // 只在应用真正进入后台时暂停弹幕（移动端）
        if (_running) {
          pause();
        }
        break;
      case AppLifecycleState.inactive:
        // 桌面环境下窗口失去焦点时不暂停弹幕
        // 只在移动端或真正的系统级别暂停时才暂停弹幕
        // 注：inactive状态在桌面上通常只是窗口失去焦点，不应暂停弹幕
        break;
      case AppLifecycleState.resumed:
        // 应用恢复到前台时不自动恢复播放
        // 弹幕状态应该由外部控制器根据视频实际播放状态决定
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    _running = false;
    WidgetsBinding.instance.removeObserver(this);
    _cleanupTimer?.cancel();
    _animationController.dispose();
    _staticAnimationController.dispose();
    _stopwatch.stop();
    super.dispose();
  }

  /// 添加弹幕
  /// [initialProgress] 用于 seek 后恢复滚动弹幕的水平位置。
  /// [elapsedSeconds] 用于恢复顶部/底部弹幕的剩余生命周期。
  /// 返回是否真正上屏：类型被隐藏或所有轨道均被占用时返回 false，
  /// 调用方据此只记录真正上屏的弹幕，避免被丢弃的弹幕占用去重窗口。
  bool addDanmaku(
    DanmakuContentItem content, {
    double initialProgress = 0,
    double elapsedSeconds = 0,
  }) {
    if (!mounted) {
      return false;
    }

    if (content.type == DanmakuItemType.special) {
      if (_option.hideSpecial) {
        return false;
      }
      // 计算弹幕颜色的亮度，与其他内核保持一致
      final color = content.color;
      final luminance =
          (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) / 255;
      // 如果亮度小于0.2，说明是深色，使用白色描边；否则使用黑色描边
      final strokeColor = luminance < 0.2 ? Colors.white : Colors.black;

      (content as SpecialDanmakuContentItem).painterCache = TextPainter(
        text: TextSpan(
          text: content.text,
          style: TextStyle(
            color: content.color,
            fontSize: content.fontSize,
            fontWeight: FontWeight.values[_option.fontWeight],
            shadows: content.hasStroke
                ? [
                    Shadow(
                        color: strokeColor.withOpacity(
                            content.alphaTween?.begin ??
                                content.color.opacity),
                        blurRadius: 0) // 使用0像素模糊来匹配其他内核
                  ]
                : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _specialDanmakuItems.add(DanmakuItem(
        width: 0,
        height: 0,
        creationTime: _tick,
        content: content,
        paragraph: null,
        strokeParagraph: null,
      ));
      if (_running) {
        if (!_animationController.isAnimating) {
          _animationController.repeat();
        }
      } else {
        setState(() {});
      }
      _syncCleanupTimer();
      return true;
    }

    // 在这里提前创建 Paragraph 缓存防止卡顿
    final textPainter = TextPainter(
      text: TextSpan(
          text: content.text,
          style: TextStyle(
              fontSize: _option.fontSize,
              fontWeight: FontWeight.values[_option.fontWeight])),
      textDirection: TextDirection.ltr,
    )..layout();
    final danmakuWidth = textPainter.width;
    final danmakuHeight = textPainter.height;
    final remainingDuration =
        (_option.duration - elapsedSeconds).clamp(0.0, _option.duration).toDouble();
    if (content.type != DanmakuItemType.scroll && remainingDuration <= 0) {
      return false;
    }

    // 弹幕初始 x 位置：按初始进度定位，0=从屏幕右侧进入，
    // 进度>0 表示时间跳转后弹幕应已滚动了一部分，直接出现在正确位置。
    final double initialX = _viewWidth -
        initialProgress.clamp(0.0, 1.0) * (_viewWidth + danmakuWidth);

    final ui.Paragraph paragraph = Utils.generateParagraph(
        content, danmakuWidth, _option.fontSize, _option.fontWeight);

    ui.Paragraph? strokeParagraph;
    if (_option.showStroke) {
      strokeParagraph = Utils.generateStrokeParagraph(
          content, danmakuWidth, _option.fontSize, _option.fontWeight);
    }

    final type = content.type;
    var added = false;
    var idx = 1;
    for (double yPosition in _trackYPositions) {
      if (type == DanmakuItemType.scroll && !_option.hideScroll) {
        final scrollCanAddToTrack = _scrollCanAddToTrack(
          yPosition,
          initialX,
          danmakuWidth,
        );

        if (scrollCanAddToTrack) {
          _scrollDanmakuItems.add(DanmakuItem(
              yPosition: yPosition,
              xPosition: initialX,
              width: danmakuWidth,
              height: danmakuHeight,
              creationTime: _tick,
              content: content,
              paragraph: paragraph,
              strokeParagraph: strokeParagraph));
          added = true;
          break;
        }

        /// 无法填充自己发送的弹幕时强制添加
        if (content.selfSend && idx == _trackCount) {
          _scrollDanmakuItems.add(DanmakuItem(
              yPosition: _trackYPositions[0],
              xPosition: initialX,
              width: danmakuWidth,
              height: danmakuHeight,
              creationTime: _tick,
              content: content,
              paragraph: paragraph,
              strokeParagraph: strokeParagraph));
          added = true;
          break;
        }

        /// 海量弹幕启用时进行随机添加
        if (_option.massiveMode && idx == _trackCount) {
          var randomYPosition =
              _trackYPositions[_random.nextInt(_trackYPositions.length)];
          _scrollDanmakuItems.add(DanmakuItem(
              yPosition: randomYPosition,
              xPosition: initialX,
              width: danmakuWidth,
              height: danmakuHeight,
              creationTime: _tick,
              content: content,
              paragraph: paragraph,
              strokeParagraph: strokeParagraph));
          added = true;
          break;
        }
      }

      if (type == DanmakuItemType.top && !_option.hideTop) {
        final topCanAddToTrack = _topCanAddToTrack(yPosition);

        if (topCanAddToTrack) {
          _topDanmakuItems.add(DanmakuItem(
              yPosition: yPosition,
              xPosition: _viewWidth,
              width: danmakuWidth,
              height: danmakuHeight,
              creationTime: _tick,
              remainingDurationSeconds: remainingDuration,
              lastLifetimeTick: _tick,
              content: content,
              paragraph: paragraph,
              strokeParagraph: strokeParagraph));
          added = true;
          break;
        }
      }

      if (type == DanmakuItemType.bottom && !_option.hideBottom) {
        final bottomCanAddToTrack = _bottomCanAddToTrack(yPosition);

        if (bottomCanAddToTrack) {
          _bottomDanmakuItems.add(DanmakuItem(
              yPosition: yPosition,
              xPosition: _viewWidth,
              width: danmakuWidth,
              height: danmakuHeight,
              creationTime: _tick,
              remainingDurationSeconds: remainingDuration,
              lastLifetimeTick: _tick,
              content: content,
              paragraph: paragraph,
              strokeParagraph: strokeParagraph));
          added = true;
          break;
        }
      }
      idx++;
    }

    if (!added) {
      return false;
    }

    switch (type) {
      case DanmakuItemType.top:
      case DanmakuItemType.bottom:
        // 重绘静态弹幕
        setState(() {
          _staticAnimationController.value = 0;
        });
        break;
      case DanmakuItemType.scroll:
        if (_running) {
          if (!_animationController.isAnimating &&
              (_scrollDanmakuItems.isNotEmpty ||
                  _specialDanmakuItems.isNotEmpty)) {
            _animationController.repeat();
          }
        } else {
          setState(() {});
        }
        break;
      case DanmakuItemType.special:
        break; // 已在上方处理
    }
    _syncCleanupTimer();
    return true;
  }

  /// 暂停
  void pause() {
    if (!mounted) return;
    _controller.running = false;
    if (_running) {
      _advanceStaticLifetimes(_tick, _safePlaybackRate(_option));
      setState(() {
        _running = false;
      });
      if (_animationController.isAnimating) {
        _animationController.stop();
      }
      if (_stopwatch.isRunning) {
        _stopwatch.stop();
      }
      _cleanupTimer?.cancel();
      _cleanupTimer = null;
    }
  }

  /// 恢复
  void resume() {
    if (!mounted) return;
    _controller.running = true;
    if (!_running) {
      setState(() {
        _running = true;
      });
      if (!_animationController.isAnimating) {
        _animationController.repeat();
      }
      _startTick();
    }
  }

  /// 更新弹幕设置
  void updateOption(DanmakuOption option) {
    bool needRestart = false;
    bool needClearParagraph = false;
    bool needUpdateDuration = false;
    
    if (_animationController.isAnimating) {
      _animationController.stop();
      needRestart = true;
    }

    if (option.fontSize != _option.fontSize) {
      needClearParagraph = true;
    }
    
    // 检查播放速度是否发生变化
    if (option.playbackRate != _option.playbackRate ||
        option.duration != _option.duration) {
      needUpdateDuration = true;
    }

    /// 需要隐藏弹幕时清理已有弹幕
    if (option.hideScroll && !_option.hideScroll) {
      _scrollDanmakuItems.clear();
    }
    if (option.hideTop && !_option.hideTop) {
      _topDanmakuItems.clear();
    }
    if (option.hideBottom && !_option.hideBottom) {
      _bottomDanmakuItems.clear();
    }
    _advanceStaticLifetimes(_tick, _safePlaybackRate(_option));
    _option = option;
    _controller.option = _option;

    // 如果播放速度发生变化，更新动画控制器的持续时间
    if (needUpdateDuration) {
      final duration = _animationDuration(_option);
      _animationController.duration = duration;
      _staticAnimationController.duration = duration;
    }

    /// 清理已经存在的 Paragraph 缓存
    if (needClearParagraph) {
      for (DanmakuItem item in _scrollDanmakuItems) {
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
      for (DanmakuItem item in _bottomDanmakuItems) {
        if (item.paragraph != null) {
          item.paragraph = null;
        }
        if (item.strokeParagraph != null) {
          item.strokeParagraph = null;
        }
      }
    }
    if (needRestart) {
      _animationController.repeat();
    }
    _syncCleanupTimer();
    setState(() {});
  }

  /// 清空弹幕
  void clearDanmakus() {
    if (!mounted) return;
    setState(() {
      _scrollDanmakuItems.clear();
      _topDanmakuItems.clear();
      _bottomDanmakuItems.clear();
      _specialDanmakuItems.clear();
    });
    _animationController.stop();
    _syncCleanupTimer();
  }

  /// 确定滚动弹幕是否可以添加
  bool _scrollCanAddToTrack(
    double yPosition,
    double candidateX,
    double candidateWidth,
  ) {
    final existing = _scrollDanmakuItems
        .where((item) => item.yPosition == yPosition)
        .map((item) => (x: item.xPosition, width: item.width));
    return ScrollDanmakuCollision.canPlace(
      existing: existing,
      candidateX: candidateX,
      candidateWidth: candidateWidth,
      viewWidth: _viewWidth,
      durationSeconds: _option.duration.toDouble(),
    );
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

  Duration _animationDuration(DanmakuOption option) {
    final milliseconds =
        (option.duration * 1000 / _safePlaybackRate(option)).round();
    return Duration(milliseconds: max(1, milliseconds));
  }

  double _safePlaybackRate(DanmakuOption option) {
    final rate = option.playbackRate;
    return rate.isFinite && rate > 0 ? rate : 1.0;
  }

  bool _advanceStaticLifetimes(int tick, double playbackRate) {
    var changed = false;
    for (final items in [_topDanmakuItems, _bottomDanmakuItems]) {
      for (final item in items) {
        final lastTick = item.lastLifetimeTick ?? tick;
        final wallSeconds = max(0, tick - lastTick) / 1000.0;
        item.remainingDurationSeconds = CanvasDanmakuTimeline.consumeLifetime(
          remainingSeconds:
              item.remainingDurationSeconds ?? _option.duration.toDouble(),
          wallSeconds: wallSeconds,
          playbackRate: playbackRate,
        );
        item.lastLifetimeTick = tick;
      }
      final before = items.length;
      items.removeWhere((item) =>
          (item.remainingDurationSeconds ?? _option.duration) <= 0);
      changed = changed || before != items.length;
    }
    return changed;
  }

  void _cleanupExpiredDanmaku() {
    if (!_running || !mounted) return;
    final tick = _tick;
    var changed = _advanceStaticLifetimes(
      tick,
      _safePlaybackRate(_option),
    );

    final scrollCount = _scrollDanmakuItems.length;
    _scrollDanmakuItems
        .removeWhere((item) => item.xPosition + item.width < 0);
    changed = changed || scrollCount != _scrollDanmakuItems.length;

    final specialCount = _specialDanmakuItems.length;
    _specialDanmakuItems.removeWhere((item) =>
        (tick - item.creationTime) >=
        (item.content as SpecialDanmakuContentItem).duration);
    changed = changed || specialCount != _specialDanmakuItems.length;

    if (_scrollDanmakuItems.isEmpty &&
        _specialDanmakuItems.isEmpty &&
        _animationController.isAnimating) {
      _animationController.stop();
    }
    if (changed && mounted) {
      setState(() {});
    }
    _syncCleanupTimer();
  }

  // 基于 Stopwatch 的墙钟只负责增量推进，倍速在每次清理时读取最新 option。
  void _startTick() {
    _stopwatch.start();
    if (_cleanupTimer != null) return;
    _cleanupTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _cleanupExpiredDanmaku(),
    );
  }

  /// 按当前是否有需要计时清理的弹幕，动态启停 100ms 清理定时器：
  /// 没有任何弹幕在屏时保持零定时唤醒，避免空转耗电；
  /// 有弹幕上屏（或恢复播放）时自动重启。
  /// 顺带在空闲时停掉滚动动画控制器，避免清空列表后空转逐帧重绘。
  void _syncCleanupTimer() {
    final needsTimer = _running &&
        (_scrollDanmakuItems.isNotEmpty ||
            _topDanmakuItems.isNotEmpty ||
            _bottomDanmakuItems.isNotEmpty ||
            _specialDanmakuItems.isNotEmpty);
    if (needsTimer) {
      _startTick();
    } else {
      _cleanupTimer?.cancel();
      _cleanupTimer = null;
      if (_scrollDanmakuItems.isEmpty &&
          _specialDanmakuItems.isEmpty &&
          _animationController.isAnimating) {
        _animationController.stop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    /// 计算弹幕轨道
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

      if (_option.area <= 0 || _option.area.isNaN || _option.area.isInfinite) {
        // 0.0 表示“单行显示”
        _trackCount = 1;
      } else {
        _trackCount =
            (constraints.maxHeight * _option.area / _danmakuHeight).floor();
      }

      /// 为字幕留出余量
      if (_option.safeArea && _option.area == 1.0) {
        _trackCount = _trackCount - 1;
      }
      if (_trackCount < 1) {
        _trackCount = 1;
      }

      _trackYPositions.clear();
      for (int i = 0; i < _trackCount; i++) {
        _trackYPositions.add(i * _danmakuHeight);
      }
      return ClipRect(
        child: IgnorePointer(
          child: Opacity(
            opacity: _option.opacity,
            child: Stack(children: [
              RepaintBoundary(
                  child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: ScrollDanmakuPainter(
                        _animationController.value,
                        _scrollDanmakuItems,
                        _option.duration.toDouble(),
                        _safePlaybackRate(_option),
                        _option.fontSize,
                        _option.fontWeight,
                        _option.showStroke,
                        _danmakuHeight,
                        _running,
                        _tick),
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
                        _option.fontWeight,
                        _option.showStroke,
                        _danmakuHeight,
                        _running,
                        _tick),
                    child: Container(),
                  );
                },
              )),
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _animationController, // 与滚动弹幕共用控制器
                  builder: (context, child) {
                    return CustomPaint(
                      painter: SpecialDanmakuPainter(
                          _animationController.value,
                          _specialDanmakuItems,
                          _option.fontSize,
                          _option.fontWeight,
                          _running,
                          _tick),
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
}
