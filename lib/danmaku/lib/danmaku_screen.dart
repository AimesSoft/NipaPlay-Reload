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

  /// 内部计时器
  late int _tick;

  /// 运行状态
  bool _running = true;

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
    
    // 检查是否已存在相同内容的弹幕
    bool isDuplicate = false;
    
    // 检查滚动弹幕中是否有重复
    if (content.type == DanmakuItemType.scroll) {
      isDuplicate = _scrollDanmakuItems.any((item) => 
          item.content.text == content.text && 
          item.content.type == content.type &&
          item.content.color.value == content.color.value &&
          (_tick - item.creationTime < 200)); // 200毫秒内视为重复
    }
    
    // 检查顶部弹幕中是否有重复
    if (content.type == DanmakuItemType.top) {
      isDuplicate = _topDanmakuItems.any((item) => 
          item.content.text == content.text && 
          item.content.type == content.type &&
          item.content.color.value == content.color.value &&
          (_tick - item.creationTime < 200));
    }
    
    // 检查底部弹幕中是否有重复
    if (content.type == DanmakuItemType.bottom) {
      isDuplicate = _bottomDanmakuItems.any((item) => 
          item.content.text == content.text && 
          item.content.type == content.type &&
          item.content.color.value == content.color.value &&
          (_tick - item.creationTime < 200));
    }
    
    // 如果是重复弹幕，直接返回
    if (isDuplicate) {
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

    int idx = 1;
    for (double yPosition in _trackYPositions) {
      if (content.type == DanmakuItemType.scroll && !_option.hideScroll) {
        bool scrollCanAddToTrack =
            _scrollCanAddToTrack(yPosition, danmakuWidth);

        if (scrollCanAddToTrack) {
          _scrollDanmakuItems.add(DanmakuItem(
              yPosition: yPosition,
              xPosition: _viewWidth,
              width: danmakuWidth,
              creationTime: _tick,
              content: content,
              paragraph: paragraph,
              strokeParagraph: strokeParagraph));
          break;
        }

        /// 海量弹幕启用时进行随机添加
        if (_option.massiveMode && idx == _trackCount) {
          final random = Random();
          var randomYPosition =
              _trackYPositions[random.nextInt(_trackYPositions.length)];
          _scrollDanmakuItems.add(DanmakuItem(
              yPosition: randomYPosition,
              xPosition: _viewWidth,
              width: danmakuWidth,
              creationTime: _tick,
              content: content,
              paragraph: paragraph,
              strokeParagraph: strokeParagraph));
          break;
        }
      }

      if (content.type == DanmakuItemType.top && !_option.hideTop) {
        bool topCanAddToTrack = _topCanAddToTrack(yPosition);

        if (topCanAddToTrack) {
          _topDanmakuItems.add(DanmakuItem(
              yPosition: yPosition,
              xPosition: _viewWidth,
              width: danmakuWidth,
              creationTime: _tick,
              content: content,
              paragraph: paragraph,
              strokeParagraph: strokeParagraph));
          break;
        }
      }

      if (content.type == DanmakuItemType.bottom && !_option.hideBottom) {
        bool bottomCanAddToTrack = _bottomCanAddToTrack(yPosition);

        if (bottomCanAddToTrack) {
          _bottomDanmakuItems.add(DanmakuItem(
              yPosition: yPosition,
              xPosition: _viewWidth,
              width: danmakuWidth,
              creationTime: _tick,
              content: content,
              paragraph: paragraph,
              strokeParagraph: strokeParagraph));
          break;
        }
      }
      idx++;
    }

    if ((_scrollDanmakuItems.isNotEmpty ||
            _topDanmakuItems.isNotEmpty ||
            _bottomDanmakuItems.isNotEmpty) &&
        !_animationController.isAnimating) {
      _animationController.repeat();
    }
    // 移除屏幕外滚动弹幕
    _scrollDanmakuItems.removeWhere((item) => item.xPosition + item.width < 0);
    // 移除顶部弹幕
    _topDanmakuItems.removeWhere(
        (item) => ((_tick - item.creationTime) > (_option.duration * 1000)));
    // 移除底部弹幕
    _bottomDanmakuItems.removeWhere(
        (item) => ((_tick - item.creationTime) > (_option.duration * 1000)));

    /// 重绘静态弹幕
    setState(() {
      _staticAnimationController.value = 0;
    });
  }

  /// 暂停
  void pause() {
    if (_running) {
      setState(() {
        _running = false;
      });
      if (_animationController.isAnimating) {
        _animationController.stop();
      }
    }
  }

  /// 恢复
  void resume() {
    if (!_running) {
      setState(() {
        _running = true;
      });
      if (!_animationController.isAnimating) {
        _animationController.repeat();
        // 重启计时器
        _startTick();
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
    _option = option;
    _controller.option = _option;

    /// 清理已经存在的 Paragraph 缓存
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
    if (needRestart) {
      _animationController.repeat();
    }
    setState(() {});
  }

  /// 清空弹幕
  void clearDanmakus() {
    // 停止滚动弹幕动画
    if (_animationController.isAnimating) {
      _animationController.stop();
    }
    
    // 停止静态弹幕动画
    if (_staticAnimationController.isAnimating) {
      _staticAnimationController.stop();
    }
    
    // 清空所有弹幕列表
    setState(() {
      _scrollDanmakuItems.clear();
      _topDanmakuItems.clear();
      _bottomDanmakuItems.clear();
    });
    
    // 强制重绘
    setState(() {
      _staticAnimationController.value = 0;
      _animationController.value = 0;
    });
  }

  /// 确定滚动弹幕是否可以添加
  bool _scrollCanAddToTrack(double yPosition, double newDanmakuWidth) {
    for (var item in _scrollDanmakuItems) {
      if (item.yPosition == yPosition) {
        final existingEndPosition = item.xPosition + item.width;
        // 首先保证进入屏幕时不发生重叠，其次保证知道移出屏幕前不与速度慢的弹幕(弹幕宽度较小)发生重叠
        if (_viewWidth - existingEndPosition < 0) {
          return false;
        }
        if (item.width < newDanmakuWidth) {
          if ((1 -
                  ((_viewWidth - item.xPosition) / (item.width + _viewWidth))) >
              ((_viewWidth) / (_viewWidth + newDanmakuWidth))) {
            return false;
          }
        }
      }
    }
    return true;
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

  // 基于Stopwatch的计时器同步
  void _startTick() async {
    final stopwatch = Stopwatch()..start();
    int lastElapsedTime = 0;

    while (_running && mounted) {
      await Future.delayed(const Duration(milliseconds: 1));
      int currentElapsedTime = stopwatch.elapsedMilliseconds; // 获取当前的已用时间
      int delta = currentElapsedTime - lastElapsedTime; // 计算自上次记录以来的时间差
      _tick += delta;
      lastElapsedTime = currentElapsedTime; // 更新最后记录的时间
    }

    stopwatch.stop();
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

      /// 为字幕留出余量
      _trackCount =
          (constraints.maxHeight * _option.area / _danmakuHeight).floor() - 1;

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
                        _option.duration,
                        _option.fontSize,
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
                        _option.showStroke,
                        _danmakuHeight,
                        _running,
                        _tick),
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
