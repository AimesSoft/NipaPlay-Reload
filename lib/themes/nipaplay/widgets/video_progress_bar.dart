import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

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
  Timer? _previewDebounceTimer;
  String? _hoverThumbnailPath;
  int? _hoverBucket;

  @override
  void dispose() {
    _previewDebounceTimer?.cancel();
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay(BuildContext context, double progress,
      {Duration? displayTime, String? thumbnailPath}) {
    _removeOverlay();
    
    final RenderBox? sliderBox = _sliderKey.currentContext?.findRenderObject() as RenderBox?;
    if (sliderBox == null) return;

    final position = sliderBox.localToGlobal(Offset.zero);
    final size = sliderBox.size;
    final hasPreview =
        thumbnailPath != null && thumbnailPath.isNotEmpty && _isPreviewReady(thumbnailPath);
    debugPrint(
        'timeline preview overlay -> hasPreview=$hasPreview, thumb=$thumbnailPath');
    final previewWidth = globals.isPhone ? 140.0 : 200.0;
    final previewHeight = previewWidth * 9 / 16;
    final text = widget.formatDuration(displayTime ?? widget.videoState.position);
    final textWidth = _measureTextWidth(text);
    final bubbleWidth = hasPreview ? previewWidth + 16 : textWidth + 24;
    final bubbleHeight = hasPreview ? previewHeight + 46 : 40.0;
    final bubbleX = position.dx + (progress * size.width) - (bubbleWidth / 2);
    final bubbleY = position.dy - bubbleHeight - 8;

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
                  filter: ImageFilter.blur(sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 10 : 0, sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 10 : 0),
                  child: Container(
                    padding: const EdgeInsets.all(8),
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
                width: bubbleWidth,
                child: hasPreview
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: _buildPreviewImage(
                              thumbnailPath!,
                              previewWidth,
                              previewHeight,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                                top: 6, left: 4, right: 4, bottom: 2),
                            child: Text(
                              text,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.visible,
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: Text(
                          text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
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
            _handleHoverPreview(time, progress);
          } else {
            if (_localHoverTime != null) {
              setState(() {
                _localHoverTime = null;
              });
            }
            _previewDebounceTimer?.cancel();
            _hoverBucket = null;
            _hoverThumbnailPath = null;
            _removeOverlay();
          }
        }
      },
      onExit: (_) {
        setState(() {
          _isHovering = false;
          _isThumbHovered = false;
          _localHoverTime = null;
        });
        _previewDebounceTimer?.cancel();
        _hoverBucket = null;
        _hoverThumbnailPath = null;
        _removeOverlay();
      },
      child: GestureDetector(
        onHorizontalDragStart: (details) {
          widget.onDraggingStateChange(true);
          _updateProgressFromPosition(details.localPosition);
          _showOverlay(
            context,
            widget.videoState.progress,
            displayTime: widget.videoState.position,
          );
        },
        onHorizontalDragUpdate: (details) {
          _updateProgressFromPosition(details.localPosition);
          if (_overlayEntry != null) {
            _showOverlay(
              context,
              widget.videoState.progress,
              displayTime: widget.videoState.position,
            );
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
          _showOverlay(
            context,
            widget.videoState.progress,
            displayTime: widget.videoState.position,
          );
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
                : Stack(
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

  void _handleHoverPreview(Duration time, double progress) {
    if (!mounted) return;

    // 先展示时间气泡，避免等待缩略图时没有反馈
    _showOverlay(
      context,
      progress,
      displayTime: time,
      thumbnailPath: widget.videoState.isTimelinePreviewAvailable
          ? _hoverThumbnailPath
          : null,
    );

    if (!widget.videoState.isTimelinePreviewAvailable) {
      return;
    }

    final bucket = widget.videoState.getTimelinePreviewBucket(time);
    if (bucket == null) return;
    if (_hoverBucket == bucket && _hoverThumbnailPath != null) {
      return;
    }
    if (_hoverBucket != bucket) {
      _hoverThumbnailPath = null;
    }
    _hoverBucket = bucket;

    _previewDebounceTimer?.cancel();
      _previewDebounceTimer = Timer(const Duration(milliseconds: 120), () async {
        final resolvedBucket = widget.videoState.getTimelinePreviewBucket(time);
        if (resolvedBucket == null || _hoverBucket != bucket) return;
        final previewPath = await widget.videoState.getTimelinePreview(time);
        if (!mounted) return;
        if (_hoverBucket != bucket) return;
        final readyPath =
            (previewPath != null && _isPreviewReady(previewPath)) ? previewPath : null;
        debugPrint(
            'timeline preview resolved bucket=$bucket path=$previewPath ready=$readyPath');

        if (_hoverThumbnailPath != readyPath) {
          setState(() {
            _hoverThumbnailPath = readyPath;
          });
        }

      _showOverlay(
        context,
        progress,
        displayTime: time,
        thumbnailPath: readyPath,
      );
    });
  }

  double _measureTextWidth(String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(minWidth: 0, maxWidth: double.infinity);
    return painter.width;
  }

  Widget _buildPreviewImage(String path, double width, double height) {
    final file = File(path);
    if (!file.existsSync()) {
      return _buildPreviewPlaceholder(width, height);
    }
    return Image.file(
      file,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _buildPreviewPlaceholder(width, height),
    );
  }

  Widget _buildPreviewPlaceholder(double width, double height) {
    return Container(
      width: width,
      height: height,
      color: Colors.black.withOpacity(0.2),
      child: const Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: Colors.white70,
          size: 28,
        ),
      ),
    );
  }

  bool _isPreviewReady(String path) {
    final file = File(path);
    return file.existsSync();
  }
}
