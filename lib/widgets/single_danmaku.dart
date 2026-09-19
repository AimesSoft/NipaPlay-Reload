import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_text_renderer.dart';

class SingleDanmaku extends StatefulWidget {
  final DanmakuContentItem content;
  final double videoDuration;
  final double currentTime;
  final double danmakuTime;
  final double fontSize;
  final bool isVisible;
  final double yPosition;
  final double opacity;
  final DanmakuTextRenderer textRenderer;
  final double timeOffset;
  final double scrollDurationSeconds;

  const SingleDanmaku({
    super.key,
    required this.content,
    required this.videoDuration,
    required this.currentTime,
    required this.danmakuTime,
    required this.fontSize,
    required this.isVisible,
    required this.yPosition,
    this.opacity = 1.0,
    required this.textRenderer,
    this.timeOffset = 0.0,
    this.scrollDurationSeconds = 10.0,
  });

  @override
  State<SingleDanmaku> createState() => _SingleDanmakuState();
}

class _SingleDanmakuState extends State<SingleDanmaku> {
  late double _xPosition;
  late double _opacity;
  bool _initialized = false;
  bool _isPaused = false;
  double _pauseTime = 0.0;
  Size _previousScreenSize = Size.zero; // 添加屏幕尺寸记录

  @override
  void initState() {
    super.initState();
    // 初始化基本值
    _opacity = widget.isVisible ? widget.opacity : 0.0;
    _xPosition = 1.0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _calculatePosition();
    }
  }

  @override
  void didUpdateWidget(SingleDanmaku oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 检测视频是否暂停
    if (oldWidget.currentTime == widget.currentTime &&
        oldWidget.currentTime != 0) {
      _isPaused = true;
      _pauseTime = widget.currentTime;
    } else {
      _isPaused = false;
    }

    if (oldWidget.currentTime != widget.currentTime ||
        oldWidget.isVisible != widget.isVisible ||
        oldWidget.opacity != widget.opacity) {
      _calculatePosition();
    }
  }

  void _calculatePosition() {
    if (!widget.isVisible) {
      _opacity = 0;
      return;
    }

    // 计算弹幕相对于当前时间的位置，应用时间偏移
    final timeDiff =
        widget.currentTime - (widget.danmakuTime - widget.timeOffset);
    //print('[SINGLE_DANMAKU] "${widget.content.text}" 位置计算: 当前=${widget.currentTime.toStringAsFixed(3)}s, 弹幕=${widget.danmakuTime.toStringAsFixed(3)}s, 差=${timeDiff.toStringAsFixed(3)}s');
    final screenWidth = MediaQuery.of(context).size.width;

    // 计算弹幕宽度
    final textPainter = TextPainter(
      text: TextSpan(
        text: widget.content.text,
        locale: Locale("zh-Hans", "zh"),
        style: TextStyle(
          fontSize: widget.fontSize * widget.content.fontSizeMultiplier,
          color: widget.content.color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final danmakuWidth = textPainter.width;

    switch (widget.content.type) {
      case DanmakuItemType.scroll:
        // 滚动弹幕：从右到左
        final duration = widget.scrollDurationSeconds > 0
            ? widget.scrollDurationSeconds
            : 10.0;
        const earlyStartTime = 1.0; // 提前1秒开始

        if (timeDiff < -earlyStartTime) {
          // 弹幕还未出现
          _xPosition = screenWidth;
          _opacity = 0;
        } else if (timeDiff > duration) {
          // 弹幕已经消失
          _xPosition = -danmakuWidth;
          _opacity = 0;
        } else {
          // 🔥 修复：弹幕从更远的屏幕外开始，确保时间轴时间点时刚好在屏幕边缘
          final extraDistance = (screenWidth + danmakuWidth) / 10; // 额外距离
          final startX = screenWidth + extraDistance; // 起始位置
          final totalDistance =
              extraDistance + screenWidth + danmakuWidth; // 总移动距离
          final totalDuration = duration + earlyStartTime; // 总时长11秒

          if (_isPaused) {
            // 视频暂停时，根据暂停时间计算位置，应用时间偏移
            final pauseTimeDiff =
                _pauseTime - (widget.danmakuTime - widget.timeOffset);
            final adjustedPauseTime =
                pauseTimeDiff + earlyStartTime; // 调整到[0, 11]范围
            _xPosition =
                startX - (adjustedPauseTime / totalDuration) * totalDistance;
          } else {
            // 正常滚动
            final adjustedTime = timeDiff + earlyStartTime; // 调整到[0, 11]范围
            _xPosition =
                startX - (adjustedTime / totalDuration) * totalDistance;
          }

          // 只在弹幕进入屏幕时显示
          if (_xPosition > screenWidth) {
            _opacity = 0;
          } else if (_xPosition + danmakuWidth < 0) {
            _opacity = 0;
          } else {
            _opacity = widget.opacity;
          }
        }
        break;

      case DanmakuItemType.top:
        // 顶部弹幕：固定位置，居中显示
        _xPosition = (screenWidth - danmakuWidth) / 2;

        // 应用时间偏移，只在显示时间内显示
        if (timeDiff < 0 || timeDiff > 5) {
          _opacity = 0;
        } else {
          _opacity = widget.opacity;
        }
        break;

      case DanmakuItemType.bottom:
        // 底部弹幕：固定位置，居中显示
        _xPosition = (screenWidth - danmakuWidth) / 2;

        // 应用时间偏移，只在显示时间内显示
        if (timeDiff < 0 || timeDiff > 5) {
          _opacity = 0;
        } else {
          _opacity = widget.opacity;
        }
        break;
    }

    // 确保状态更新
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // 获取当前屏幕尺寸
    final currentScreenSize = MediaQuery.of(context).size;

    // 检测屏幕尺寸是否发生变化
    if (currentScreenSize != _previousScreenSize) {
      // 屏幕尺寸发生变化，重新计算弹幕位置
      _previousScreenSize = currentScreenSize;
      // 立即执行重新计算，不要使用微任务
      _calculatePosition();
    }

    if (!widget.isVisible) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: _xPosition,
      top: widget.yPosition,
      child: widget.textRenderer.build(
        context,
        widget.content,
        widget.fontSize,
        _opacity,
      ),
    );
  }
}
