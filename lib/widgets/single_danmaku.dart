import 'package:flutter/material.dart';
import 'danmaku_content_item.dart';

class SingleDanmaku extends StatefulWidget {
  final DanmakuContentItem content;
  final double videoDuration;
  final double currentTime;
  final double danmakuTime;
  final double fontSize;
  final bool isVisible;
  final double yPosition;
  final double opacity;

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
    if (oldWidget.currentTime == widget.currentTime && oldWidget.currentTime != 0) {
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

    // 计算弹幕相对于当前时间的位置
    final timeDiff = widget.currentTime - widget.danmakuTime;
    print('[SINGLE_DANMAKU] 📍 "${widget.content.text}" 位置计算: 当前=${widget.currentTime.toStringAsFixed(3)}s, 弹幕=${widget.danmakuTime.toStringAsFixed(3)}s, 差=${timeDiff.toStringAsFixed(3)}s');
    final screenWidth = MediaQuery.of(context).size.width;
    
    // 计算弹幕宽度
    final textPainter = TextPainter(
      text: TextSpan(
        text: widget.content.text,
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
        if (timeDiff < 0) {
          // 弹幕还未出现
          _xPosition = screenWidth;
          _opacity = 0;
        } else if (timeDiff > 10) {
          // 弹幕已经消失
          _xPosition = -danmakuWidth;
          _opacity = 0;
        } else {
          // 弹幕正在滚动
          if (_isPaused) {
            // 视频暂停时，根据暂停时间计算位置，同时考虑屏幕宽度变化带来的影响
            // 固定使用暂停时间而不使用当前时间，确保停留在暂停时的相对位置
            final timeFraction = (_pauseTime - widget.danmakuTime) / 10;
            // 根据当前屏幕宽度重新计算绝对位置
            _xPosition = screenWidth - timeFraction * (screenWidth + danmakuWidth);
          } else {
            // 正常滚动
            _xPosition = screenWidth - (timeDiff / 10) * (screenWidth + danmakuWidth);
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
        
        // 只在显示时间内显示
        if (timeDiff < 0 || timeDiff > 5) {
          _opacity = 0;
        } else {
          _opacity = widget.opacity;
        }
        break;
        
      case DanmakuItemType.bottom:
        // 底部弹幕：固定位置，居中显示
        _xPosition = (screenWidth - danmakuWidth) / 2;
        
        // 只在显示时间内显示
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

    // 计算弹幕颜色的亮度
    final color = widget.content.color;
    final luminance = (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) / 255;
    // 如果亮度小于0.1，说明是深色，使用白色描边；否则使用黑色描边
    final strokeColor = luminance < 0.2 ? Colors.white : Colors.black;
    
    // 应用字体大小倍率
    final adjustedFontSize = widget.fontSize * widget.content.fontSizeMultiplier;

    // 检查是否有计数文本
    final hasCountText = widget.content.countText != null;
    
    // 创建阴影列表
    final shadowList = [
      // 八个方向的描边
      Shadow(
        offset: const Offset(-1, -1),
        blurRadius: 0,
        color: strokeColor,
      ),
      Shadow(
        offset: const Offset(1, -1),
        blurRadius: 0,
        color: strokeColor,
      ),
      Shadow(
        offset: const Offset(1, 1),
        blurRadius: 0,
        color: strokeColor,
      ),
      Shadow(
        offset: const Offset(-1, 1),
        blurRadius: 0,
        color: strokeColor,
      ),
      Shadow(
        offset: const Offset(0, -1),
        blurRadius: 0,
        color: strokeColor,
      ),
      Shadow(
        offset: const Offset(0, 1),
        blurRadius: 0,
        color: strokeColor,
      ),
      Shadow(
        offset: const Offset(-1, 0),
        blurRadius: 0,
        color: strokeColor,
      ),
      Shadow(
        offset: const Offset(1, 0),
        blurRadius: 0,
        color: strokeColor,
      ),
    ];

    return Positioned(
      left: _xPosition,
      top: widget.yPosition,
      child: Opacity(
        opacity: _opacity,
        child: hasCountText 
          ? RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: widget.content.text,
                    style: TextStyle(
                      fontSize: adjustedFontSize,
                      color: widget.content.color,
                      fontWeight: FontWeight.normal,
                      shadows: shadowList,
                    ),
                  ),
                  TextSpan(
                    text: widget.content.countText,
                    style: TextStyle(
                      fontSize: 25.0, // 固定大小字体
                      color: Colors.white,
                      fontWeight: FontWeight.bold, 
                      shadows: shadowList, // 继承相同的描边效果
                    ),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                // 描边
                Text(
                  widget.content.text,
                  style: TextStyle(
                    fontSize: adjustedFontSize,
                    color: strokeColor,
                    fontWeight: FontWeight.normal,
                    shadows: shadowList,
                  ),
                ),
                // 实际文本
                Text(
                  widget.content.text,
                  style: TextStyle(
                    fontSize: adjustedFontSize,
                    color: widget.content.color,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
      ),
    );
  }
} 