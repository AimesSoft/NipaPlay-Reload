import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/player_abstraction/player_data_models.dart';
import 'package:provider/provider.dart';
import 'control_shadow.dart';

class VideoProgressBar extends StatefulWidget {
  final VideoPlayerState videoState;
  final Duration? hoverTime;
  final bool isDragging;
  final Function(Offset) onPositionUpdate;
  final Function(bool) onDraggingStateChange;
  final String Function(Duration) formatDuration;
  /// MKV 章节列表（用于在轨道上画章节起点竖线标记 + 当前章节高亮段）。
  /// 参考 REFERENCE/mpv/player/lua/osc.lua:2512 markers。
  final List<PlayerChapter> chapters;
  /// 媒体总时长（毫秒），用于计算章节标记位置。
  final int durationMs;
  /// 当前章节索引（用于在轨道上高亮当前章节段）。-1 表示无/首章前。
  final int currentChapter;

  const VideoProgressBar({
    super.key,
    required this.videoState,
    required this.hoverTime,
    required this.isDragging,
    required this.onPositionUpdate,
    required this.onDraggingStateChange,
    required this.formatDuration,
    this.chapters = const [],
    this.durationMs = 0,
    this.currentChapter = -1,
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
  /// 当前 hover/tap 命中的章节分割线索引（-1=未命中任何分割线）。
  /// 用于 _ChapterTickMarks 高亮放大该分割线。
  int _hitChapterTickIndex = -1;
  /// 章节分割线命中容差（像素）。点击/悬停在该像素范围内才触发章节跳转。
  static const double _chapterTickHitTolerance = 8.0;
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

    final RenderBox? sliderBox =
        _sliderKey.currentContext?.findRenderObject() as RenderBox?;
    if (sliderBox == null) return;

    final position = sliderBox.localToGlobal(Offset.zero);
    final size = sliderBox.size;
    final hasPreview = thumbnailPath != null &&
        thumbnailPath.isNotEmpty &&
        _isPreviewReady(thumbnailPath);
    final previewWidth = globals.isPhone ? 140.0 : 200.0;
    final previewHeight = previewWidth * 9 / 16;
    final text =
        widget.formatDuration(displayTime ?? widget.videoState.position);
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
              child: kIsWeb
                  ? Container(
                      padding: const EdgeInsets.all(8),
                      width: bubbleWidth,
                      decoration: BoxDecoration(
                        color: const Color(0xFF202020),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 0.5,
                        ),
                      ),
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
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                            sigmaX: context
                                    .watch<AppearanceSettingsProvider>()
                                    .enableWidgetBlurEffect
                                ? 10
                                : 0,
                            sigmaY: context
                                    .watch<AppearanceSettingsProvider>()
                                    .enableWidgetBlurEffect
                                ? 10
                                : 0),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.58),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 0.5,
                            ),
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

        final RenderBox? sliderBox =
            _sliderKey.currentContext?.findRenderObject() as RenderBox?;
        if (sliderBox != null) {
          final localPosition = sliderBox.globalToLocal(event.position);
          final width = sliderBox.size.width;

          final progress = (localPosition.dx / width).clamp(0.0, 1.0);
          final time = Duration(
            milliseconds:
                (progress * widget.videoState.duration.inMilliseconds).toInt(),
          );

          final progressRect =
              Rect.fromLTWH(0, 0, width, sliderBox.size.height);
          final thumbSize = globals.isPhone ? 20.0 : 12.0;
          final thumbSizeHovered = globals.isPhone ? 24.0 : 16.0;
          final currentThumbSize =
              _isThumbHovered ? thumbSizeHovered : thumbSize;
          final halfThumbSize = currentThumbSize / 2;
          final baseVerticalMargin = globals.isPhone ? 24.0 : 20.0;
          final hitPadding = globals.isPhone ? 12.0 : 8.0;
          final verticalMargin = baseVerticalMargin + hitPadding;
          final trackHeight = globals.isPhone ? 6.0 : 4.0;
          final thumbRect = Rect.fromLTWH(
              (widget.videoState.progress * width) - halfThumbSize,
              verticalMargin + (trackHeight / 2) - halfThumbSize,
              currentThumbSize,
              currentThumbSize);

          // 章节分割线 hover 命中检测：命中则高亮放大该分割线，鼠标变 pointer
          final hitTick = _hitTestChapterTick(localPosition.dx, width);
          setState(() {
            _isThumbHovered = thumbRect.contains(localPosition);
            _hitChapterTickIndex = hitTick;
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
          _hitChapterTickIndex = -1;
        });
        _previewDebounceTimer?.cancel();
        _hoverBucket = null;
        _hoverThumbnailPath = null;
        _removeOverlay();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
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
          // isTapGesture: true → 命中章节分割线走 seekToChapter（keyframe 对齐）。
          // drag 手势（onHorizontalDrag*）默认 false，始终走精确 seekTo，避免
          // 在章节边界 ±8px 内拖拽被章节跳转劫持。
          _updateProgressFromPosition(details.localPosition, isTapGesture: true);
          _showOverlay(
            context,
            widget.videoState.progress,
            displayTime: widget.videoState.position,
          );
        },
        onTapUp: (details) {
          widget.onDraggingStateChange(false);
          // 不重复 seek：onTapDown 已完成定位（章节分割线命中跳转或普通 seek）。
          // 若此处再次 _updateProgressFromPosition，tap down→up 间鼠标微动会
          // 导致 up 时未命中分割线，普通 seekTo 覆盖 onTapDown 的章节跳转。
          // drag 场景由 onHorizontalDragEnd 处理，不受影响。
          widget.onPositionUpdate(Offset.zero);
          _removeOverlay();
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 安全地计算进度值
            double progress = 0.0;
            if (widget.videoState.duration.inMilliseconds > 0) {
              progress = (widget.videoState.position.inMilliseconds /
                      widget.videoState.duration.inMilliseconds)
                  .clamp(0.0, 1.0);
            } else {
              // 如果总时长为0或无效，则进度也为0
              progress = 0.0;
            }
            // 确保 progress 值不会是 NaN 或 Infinity， clamp 已经处理了 Infinity，这里额外处理 NaN
            if (progress.isNaN) {
              progress = 0.0;
            }
            double bufferProgress = widget.videoState.bufferedProgress;
            if (bufferProgress.isNaN || bufferProgress.isInfinite) {
              bufferProgress = 0.0;
            }
            bufferProgress = bufferProgress.clamp(0.0, 1.0).toDouble();
            if (bufferProgress < progress) {
              bufferProgress = progress;
            }

            // 根据设备类型调整尺寸
            final trackHeight = globals.isPhone ? 6.0 : 4.0;
            final baseVerticalMargin = globals.isPhone ? 24.0 : 20.0;
            final hitPadding = globals.isPhone ? 12.0 : 8.0;
            final verticalMargin = baseVerticalMargin + hitPadding;
            final thumbSize = globals.isPhone ? 20.0 : 12.0;
            final thumbSizeHovered = globals.isPhone ? 24.0 : 16.0;
            final currentThumbSize = _isThumbHovered || widget.isDragging
                ? thumbSizeHovered
                : thumbSize;
            final halfThumbSize = currentThumbSize / 2;
            const trackBaseColor = Color.fromARGB(255, 160, 160, 160);
            const bufferTrackColor = Color.fromARGB(255, 225, 225, 225);
            const playedTrackColor = Color(0xFFFFFFFF);
            return widget.isDragging
                ? Stack(
                    key: _sliderKey,
                    clipBehavior: Clip.none,
                    children: [
                      // 背景轨道
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: verticalMargin),
                        child: Opacity(
                          opacity: 0.3,
                          child: ControlShadow(
                            borderRadius: BorderRadius.circular(trackHeight / 2),
                            child: Container(
                              height: trackHeight,
                              decoration: BoxDecoration(
                                color: trackBaseColor,
                                borderRadius:
                                    BorderRadius.circular(trackHeight / 2),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 章节标记 overlay（竖线标记 + 当前章节高亮段）
                      // 公共方法 _buildChapterOverlayWidgets 消除两布局分支重复
                      ..._buildChapterOverlayWidgets(verticalMargin, trackHeight),
                      // 缓存轨道
                      Positioned(
                        left: 0,
                        right: 0,
                        top: verticalMargin,
                        child: FractionallySizedBox(
                          widthFactor: bufferProgress,
                          alignment: Alignment.centerLeft,
                          child: Opacity(
                            opacity: 0.3,
                            child: Container(
                              height: trackHeight,
                              decoration: BoxDecoration(
                                color: bufferTrackColor,
                                borderRadius:
                                    BorderRadius.circular(trackHeight / 2),
                              ),
                            ),
                          ),
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
                              color: playedTrackColor,
                              borderRadius:
                                  BorderRadius.circular(trackHeight / 2),
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
                                  color: const Color.fromARGB(100, 0, 0, 0),
                                  blurRadius:
                                      _isThumbHovered || widget.isDragging
                                          ? 12
                                          : 8,
                                  offset: const Offset(0, 2),
                                ),
                                BoxShadow(
                                  color: const Color.fromARGB(100, 0, 0, 0),
                                  blurRadius:
                                      _isThumbHovered || widget.isDragging
                                          ? 20
                                          : 14,
                                  offset: const Offset(0, 6),
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
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: verticalMargin),
                        child: Opacity(
                          opacity: 0.5,
                          child: ControlShadow(
                            borderRadius: BorderRadius.circular(trackHeight / 2),
                            child: Container(
                              height: trackHeight,
                              decoration: BoxDecoration(
                                color: trackBaseColor,
                                borderRadius:
                                    BorderRadius.circular(trackHeight / 2),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 章节标记 overlay（竖线标记 + 当前章节高亮段）
                      // 公共方法 _buildChapterOverlayWidgets 消除两布局分支重复
                      ..._buildChapterOverlayWidgets(verticalMargin, trackHeight),
                      // 缓存轨道
                      Positioned(
                        left: 0,
                        right: 0,
                        top: verticalMargin,
                        child: FractionallySizedBox(
                          widthFactor: bufferProgress,
                          alignment: Alignment.centerLeft,
                          child: Opacity(
                            opacity: 0.5,
                            child: Container(
                              height: trackHeight,
                              decoration: BoxDecoration(
                                color: bufferTrackColor,
                                borderRadius:
                                    BorderRadius.circular(trackHeight / 2),
                              ),
                            ),
                          ),
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
                              color: playedTrackColor,
                              borderRadius:
                                  BorderRadius.circular(trackHeight / 2),
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
                                  color: Color.fromARGB(100, 0, 0, 0),
                                  blurRadius:
                                      _isThumbHovered || widget.isDragging
                                          ? 12
                                          : 8,
                                  offset: const Offset(0, 2),
                                ),
                                BoxShadow(
                                  color: Color.fromARGB(100, 0, 0, 0),
                                  blurRadius:
                                      _isThumbHovered || widget.isDragging
                                          ? 20
                                          : 14,
                                  offset: const Offset(0, 6),
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

  /// 构建章节标记 overlay widgets（竖线标记 + 当前章节高亮段）。
  /// PR review 注意点3：进度条有 isDragging/非 isDragging 两种布局分支，
  /// 章节标记在两分支中重复。提取此公共方法消除重复，两分支复用同一构建逻辑。
  /// 返回 List<Widget>，由调用方 spread 进各自 Stack 的 children。
  List<Widget> _buildChapterOverlayWidgets(double verticalMargin, double trackHeight) {
    if (widget.chapters.isEmpty || widget.durationMs <= 0) {
      return const [];
    }
    return [
      // 章节起点竖线标记（MKV 自带章节，参考 mpv osc.lua markers）
      // hitIndex 命中的分割线高亮放大
      Positioned(
        left: 0,
        right: 0,
        top: verticalMargin,
        child: _ChapterTickMarks(
          chapters: widget.chapters,
          durationMs: widget.durationMs,
          trackHeight: trackHeight,
          hitIndex: _hitChapterTickIndex,
        ),
      ),
      // 当前章节高亮段（覆盖在轨道上，标识当前所在章节）
      if (widget.currentChapter >= 0)
        Positioned(
          left: 0,
          right: 0,
          top: verticalMargin,
          child: _ChapterActiveSegment(
            chapters: widget.chapters,
            durationMs: widget.durationMs,
            currentChapter: widget.currentChapter,
            trackHeight: trackHeight,
          ),
        ),
    ];
  }

  /// 检测 localPosition 是否命中某个章节分割线（章节起点竖线）± 容差像素内。
  /// 返回命中的章节索引，未命中返回 -1。
  /// 分割线位置 = startMs / durationMs * trackWidth（像素）。
  int _hitTestChapterTick(double localDx, double trackWidth) {
    final chapters = widget.chapters;
    final durationMs = widget.durationMs;
    if (chapters.isEmpty || durationMs <= 0 || trackWidth <= 0) return -1;
    double bestDist = _chapterTickHitTolerance;
    int bestIdx = -1;
    for (int i = 0; i < chapters.length; i++) {
      final ratio = chapters[i].startMs / durationMs;
      if (ratio <= 0 || ratio >= 1) continue;
      final tickX = ratio * trackWidth;
      final dist = (localDx - tickX).abs();
      if (dist <= bestDist) {
        bestDist = dist;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  void _updateProgressFromPosition(Offset localPosition, {bool isTapGesture = false}) {
    final RenderBox? sliderBox =
        _sliderKey.currentContext?.findRenderObject() as RenderBox?;
    if (sliderBox != null) {
      final width = sliderBox.size.width;
      final progress = (localPosition.dx / width).clamp(0.0, 1.0);
      final durationMs = widget.videoState.duration.inMilliseconds;
      final targetMs = (progress * durationMs).toInt();
      final time = Duration(milliseconds: targetMs);

      // MKV 章节分割线点击跳转：仅 tap 手势命中章节分割线（章节起点竖线）
      // ±8px 内才触发章节跳转（mpv set chapter，keyframe 对齐），此时该分割线
      // 高亮放大。drag（拖拽 scrubbing）手势不走此分支，避免在章节边界 ±8px
      // 内拖拽时被 seekToChapter 劫持而无法精确 scrub。
      // 其他位置（或 drag）走普通精确 seekTo。
      if (isTapGesture) {
        final hitIdx = _hitTestChapterTick(localPosition.dx, width);
        if (hitIdx >= 0 && hitIdx != widget.currentChapter) {
          debugPrint('[CHAPTER-DIAG] 点击命中分割线 #$hitIdx '
              '"${widget.chapters[hitIdx].title}" @ ${widget.chapters[hitIdx].startMs}ms '
              '(x=${localPosition.dx.toStringAsFixed(1)}, 容差=${_chapterTickHitTolerance}px) → seekToChapter');
          widget.videoState.seekToChapter(hitIdx);
          return;
        }
      }

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
      final readyPath = (previewPath != null && _isPreviewReady(previewPath))
          ? previewPath
          : null;
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
      color: const Color(0xFF2A2A2A),
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

/// 章节起点竖线标记层：在进度条轨道上按 chapter.startMs/durationMs 比例
/// 画细竖线，标记每个章节起点。
/// 参考 REFERENCE/mpv/player/lua/osc.lua:2512 markers[n] = chapter.time/duration*100。
class _ChapterTickMarks extends LeafRenderObjectWidget {
  final List<PlayerChapter> chapters;
  final int durationMs;
  final double trackHeight;
  /// 当前 hover/tap 命中的章节分割线索引（-1=未命中）。
  /// 命中的分割线会高亮放大，提示可点击跳转。
  final int hitIndex;

  const _ChapterTickMarks({
    required this.chapters,
    required this.durationMs,
    required this.trackHeight,
    this.hitIndex = -1,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderChapterTickMarks(
      chapters: chapters,
      durationMs: durationMs,
      trackHeight: trackHeight,
      hitIndex: hitIndex,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant _RenderChapterTickMarks renderObject) {
    renderObject
      ..chapters = chapters
      ..durationMs = durationMs
      ..trackHeight = trackHeight
      ..hitIndex = hitIndex;
  }
}

class _RenderChapterTickMarks extends RenderBox {
  _RenderChapterTickMarks({
    required List<PlayerChapter> chapters,
    required int durationMs,
    required double trackHeight,
    int hitIndex = -1,
  })  : _chapters = chapters,
        _durationMs = durationMs,
        _trackHeight = trackHeight,
        _hitIndex = hitIndex;

  List<PlayerChapter> _chapters;
  set chapters(List<PlayerChapter> value) {
    if (_chapters == value) return;
    _chapters = value;
    markNeedsPaint();
  }

  int _durationMs;
  set durationMs(int value) {
    if (_durationMs == value) return;
    _durationMs = value;
    markNeedsPaint();
  }

  double _trackHeight;
  set trackHeight(double value) {
    if (_trackHeight == value) return;
    _trackHeight = value;
    markNeedsPaint();
  }

  int _hitIndex;
  set hitIndex(int value) {
    if (_hitIndex == value) return;
    _hitIndex = value;
    markNeedsPaint();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
    return Size(w, _trackHeight);
  }

  @override
  void performLayout() {
    final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
    size = Size(w, _trackHeight);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final list = _chapters;
    if (list.isEmpty || _durationMs <= 0 || size.width <= 0) return;

    // 普通竖线标记：半透明白色细竖线，略高于轨道上下各 1px
    final paint = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    // 命中竖线：强调色 + 更宽 + 更高（上下各延伸 4px），提示可点击跳转
    final hitPaint = Paint()
      ..color = const Color(0xFFFFD54F) // Material amber 300
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < list.length; i++) {
      final ratio = list[i].startMs / _durationMs;
      if (ratio <= 0 || ratio >= 1) continue;
      final x = offset.dx + ratio * size.width;
      if (i == _hitIndex) {
        // 命中分割线：高亮放大
        canvas.drawLine(
          Offset(x, offset.dy - 4),
          Offset(x, offset.dy + _trackHeight + 4),
          hitPaint,
        );
      } else {
        canvas.drawLine(
          Offset(x, offset.dy - 1),
          Offset(x, offset.dy + _trackHeight + 1),
          paint,
        );
      }
    }
  }
}

/// 当前章节高亮段：在进度条轨道上覆盖当前所在章节的区间，
/// 用半透明强调色标识当前章节范围。参考 mpv osc.lua 当前章节高亮。
class _ChapterActiveSegment extends LeafRenderObjectWidget {
  final List<PlayerChapter> chapters;
  final int durationMs;
  final int currentChapter;
  final double trackHeight;

  const _ChapterActiveSegment({
    required this.chapters,
    required this.durationMs,
    required this.currentChapter,
    required this.trackHeight,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderChapterActiveSegment(
      chapters: chapters,
      durationMs: durationMs,
      currentChapter: currentChapter,
      trackHeight: trackHeight,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderChapterActiveSegment)
      ..chapters = chapters
      ..durationMs = durationMs
      ..currentChapter = currentChapter
      ..trackHeight = trackHeight;
  }
}

class _RenderChapterActiveSegment extends RenderBox {
  _RenderChapterActiveSegment({
    required List<PlayerChapter> chapters,
    required int durationMs,
    required int currentChapter,
    required double trackHeight,
  })  : _chapters = chapters,
        _durationMs = durationMs,
        _currentChapter = currentChapter,
        _trackHeight = trackHeight;

  List<PlayerChapter> _chapters;
  set chapters(List<PlayerChapter> value) {
    if (_chapters == value) return;
    _chapters = value;
    markNeedsPaint();
  }

  int _durationMs;
  set durationMs(int value) {
    if (_durationMs == value) return;
    _durationMs = value;
    markNeedsPaint();
  }

  int _currentChapter;
  set currentChapter(int value) {
    if (_currentChapter == value) return;
    _currentChapter = value;
    markNeedsPaint();
  }

  double _trackHeight;
  set trackHeight(double value) {
    if (_trackHeight == value) return;
    _trackHeight = value;
    markNeedsPaint();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
    return Size(w, _trackHeight);
  }

  @override
  void performLayout() {
    final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
    size = Size(w, _trackHeight);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final list = _chapters;
    if (list.isEmpty || _durationMs <= 0 || size.width <= 0) return;
    final idx = _currentChapter;
    if (idx < 0 || idx >= list.length) return;

    final startMs = list[idx].startMs;
    final endMs = idx + 1 < list.length ? list[idx + 1].startMs : _durationMs;
    if (endMs <= startMs) return;

    final startX = offset.dx + (startMs / _durationMs) * size.width;
    final endX = offset.dx + (endMs / _durationMs) * size.width;
    final segWidth = (endX - startX).clamp(1.0, size.width);

    // 半透明强调色覆盖当前章节段，圆角与轨道一致
    final paint = Paint()
      ..color = const Color(0x554FC3F7) // Material light blue 100, 33% alpha
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(startX, offset.dy, segWidth, _trackHeight),
        Radius.circular(_trackHeight / 2),
      ),
      paint,
    );
  }
}
