import 'package:flutter/material.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'tooltip_bubble.dart';
import 'dart:ui';

class VideoProgressBar extends StatefulWidget {
  final VideoPlayerState videoState;
  final Duration? hoverTime;
  final bool isDragging;
  final Function(Offset) onPositionUpdate;
  final Function(bool) onDraggingStateChange;
  final String Function(Duration) formatDuration;

  const VideoProgressBar({
    super.key,
    required this.videoState,
    required this.hoverTime,
    required this.isDragging,
    required this.onPositionUpdate,
    required this.onDraggingStateChange,
    required this.formatDuration,
  });

  @override
  State<VideoProgressBar> createState() => _VideoProgressBarState();
}

class _VideoProgressBarState extends State<VideoProgressBar> {
  final GlobalKey _sliderKey = GlobalKey();
  Duration? _localHoverTime;
  bool _isHovering = false;
  bool _isThumbHovered = false;
  OverlayEntry? _overlayEntry;
  DateTime? _lastSeekTime;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay(BuildContext context, double progress) {
    _removeOverlay();
    
    final RenderBox? sliderBox = _sliderKey.currentContext?.findRenderObject() as RenderBox?;
    if (sliderBox == null) return;

    final position = sliderBox.localToGlobal(Offset.zero);
    final size = sliderBox.size;
    final bubbleX = position.dx + (progress * size.width) - 20;
    final bubbleY = position.dy - 40;

    _overlayEntry = OverlayEntry(
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned(
              left: bubbleX,
              top: bubbleY,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      widget.formatDuration(widget.videoState.position),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() {
          _isHovering = true;
        });
      },
      onHover: (event) {
        if (!_isHovering || widget.isDragging) return;
        
        final RenderBox? sliderBox = _sliderKey.currentContext?.findRenderObject() as RenderBox?;
        if (sliderBox != null) {
          final localPosition = sliderBox.globalToLocal(event.position);
          final width = sliderBox.size.width;
          
          final progress = (localPosition.dx / width).clamp(0.0, 1.0);
          final time = Duration(
            milliseconds: (progress * widget.videoState.duration.inMilliseconds).toInt(),
          );
          
          final progressRect = Rect.fromLTWH(0, 0, width, sliderBox.size.height);
          final thumbSize = globals.isPhone ? 20.0 : 12.0;
          final thumbSizeHovered = globals.isPhone ? 24.0 : 16.0;
          final currentThumbSize = _isThumbHovered ? thumbSizeHovered : thumbSize;
          final halfThumbSize = currentThumbSize / 2;
          final verticalMargin = globals.isPhone ? 24.0 : 20.0;
          final trackHeight = globals.isPhone ? 6.0 : 4.0;
          final thumbRect = Rect.fromLTWH(
            (widget.videoState.progress * width) - halfThumbSize,
            verticalMargin + (trackHeight / 2) - halfThumbSize,
            currentThumbSize,
            currentThumbSize
          );
          
          setState(() {
            _isThumbHovered = thumbRect.contains(localPosition);
          });
          
          if (localPosition.dx >= progressRect.left && 
              localPosition.dx <= progressRect.right &&
              localPosition.dy >= progressRect.top && 
              localPosition.dy <= progressRect.bottom) {
            if (_localHoverTime != time) {
              setState(() {
                _localHoverTime = time;
              });
            }
          } else {
            if (_localHoverTime != null) {
              setState(() {
                _localHoverTime = null;
              });
            }
          }
        }
      },
      onExit: (_) {
        setState(() {
          _isHovering = false;
          _isThumbHovered = false;
          _localHoverTime = null;
        });
      },
      child: GestureDetector(
        onHorizontalDragStart: (details) {
          widget.onDraggingStateChange(true);
          _updateProgressFromPosition(details.localPosition);
          _showOverlay(context, widget.videoState.progress);
        },
        onHorizontalDragUpdate: (details) {
          _updateProgressFromPosition(details.localPosition);
          if (_overlayEntry != null) {
            _showOverlay(context, widget.videoState.progress);
          }
        },
        onHorizontalDragEnd: (details) {
          widget.onDraggingStateChange(false);
          _updateProgressFromPosition(details.localPosition);
          widget.onPositionUpdate(Offset.zero);
          _removeOverlay();
        },
        onTapDown: (details) {
          widget.onDraggingStateChange(true);
          _updateProgressFromPosition(details.localPosition);
          _showOverlay(context, widget.videoState.progress);
        },
        onTapUp: (details) {
          widget.onDraggingStateChange(false);
          _updateProgressFromPosition(details.localPosition);
          widget.onPositionUpdate(Offset.zero);
          _removeOverlay();
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 安全地计算进度值
            double progress = 0.0;
            if (widget.videoState.duration.inMilliseconds > 0) {
              progress = (widget.videoState.position.inMilliseconds / widget.videoState.duration.inMilliseconds)
                  .clamp(0.0, 1.0);
            } else {
              // 如果总时长为0或无效，则进度也为0
              progress = 0.0;
            }
            // 确保 progress 值不会是 NaN 或 Infinity， clamp 已经处理了 Infinity，这里额外处理 NaN
            if (progress.isNaN) {
              progress = 0.0;
            }

            // 根据设备类型调整尺寸
            final trackHeight = globals.isPhone ? 6.0 : 4.0;
            final verticalMargin = globals.isPhone ? 24.0 : 20.0;
            final thumbSize = globals.isPhone ? 20.0 : 12.0;
            final thumbSizeHovered = globals.isPhone ? 24.0 : 16.0;
            final currentThumbSize = _isThumbHovered || widget.isDragging ? thumbSizeHovered : thumbSize;
            final halfThumbSize = currentThumbSize / 2;
            
            return widget.isDragging 
                ? Stack(
                    key: _sliderKey,
                    clipBehavior: Clip.none,
                    children: [
                      // 背景轨道
                      Container(
                        height: trackHeight,
                        margin: EdgeInsets.symmetric(vertical: verticalMargin),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(trackHeight / 2),
                        ),
                      ),
                      // 进度轨道
                      Positioned(
                        left: 0,
                        right: 0,
                        top: verticalMargin,
                        child: FractionallySizedBox(
                          widthFactor: progress,
                          alignment: Alignment.centerLeft,
                          child: Container(
                            height: trackHeight,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(trackHeight / 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.3),
                                  blurRadius: 2,
                                  spreadRadius: 0.5,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // 滑块
                      Positioned(
                        left: (progress * constraints.maxWidth) - halfThumbSize,
                        top: verticalMargin + (trackHeight / 2) - halfThumbSize,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutBack,
                            width: currentThumbSize,
                            height: currentThumbSize,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: _isThumbHovered || widget.isDragging ? 6 : 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : TooltipBubble(
                    text: _isHovering && _localHoverTime != null 
                        ? widget.formatDuration(_localHoverTime!) 
                        : '',
                    showOnTop: true,
                    followMouse: true,
                    position: null,
                    verticalOffset: 30,
                    child: Stack(
                      key: _sliderKey,
                      clipBehavior: Clip.none,
                      children: [
                        // 背景轨道
                        Container(
                          height: trackHeight,
                          margin: EdgeInsets.symmetric(vertical: verticalMargin),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(trackHeight / 2),
                          ),
                        ),
                        // 进度轨道
                        Positioned(
                          left: 0,
                          right: 0,
                          top: verticalMargin,
                          child: FractionallySizedBox(
                            widthFactor: progress,
                            alignment: Alignment.centerLeft,
                            child: Container(
                              height: trackHeight,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(trackHeight / 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withOpacity(0.3),
                                    blurRadius: 2,
                                    spreadRadius: 0.5,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // 滑块
                        Positioned(
                          left: (progress * constraints.maxWidth) - halfThumbSize,
                          top: verticalMargin + (trackHeight / 2) - halfThumbSize,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOutBack,
                              width: currentThumbSize,
                              height: currentThumbSize,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: _isThumbHovered || widget.isDragging ? 6 : 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
          },
        ),
      ),
    );
  }

  void _updateProgressFromPosition(Offset localPosition) {
    final RenderBox? sliderBox = _sliderKey.currentContext?.findRenderObject() as RenderBox?;
    if (sliderBox != null) {
      final width = sliderBox.size.width;
      final progress = (localPosition.dx / width).clamp(0.0, 1.0);
      final time = Duration(
        milliseconds: (progress * widget.videoState.duration.inMilliseconds).toInt(),
      );
      
      widget.videoState.seekTo(time);
      
      if (_localHoverTime != time) {
        setState(() {
          _localHoverTime = time;
        });
      }
    }
  }
}