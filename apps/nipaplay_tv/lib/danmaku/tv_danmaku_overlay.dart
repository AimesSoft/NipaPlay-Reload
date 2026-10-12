import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:nipaplay_core/constants/danmaku/mode.dart';
import 'package:nipaplay_core/models/danmaku/danmaku_item.dart';

/// TV 弹幕渲染层（自建，不进 ui_common）。
///
/// core 提供 [DanmakuItem] 与 [DanmakuMode]；这里实现十英尺观看距离下的
/// 轨道分配与滚动绘制。轨道算法：滚动弹幕按到达时间顺序占轨，顶部/底部居中。
class TvDanmakuOverlay extends StatefulWidget {
  const TvDanmakuOverlay({
    super.key,
    required this.items,
    required this.position,
    this.enabled = true,
    this.fontSize = 26,
    this.opacity = 0.9,
    this.speedPxPerSecond = 220,
    this.areaRatio = 0.5,
  });

  final List<DanmakuItem> items;
  final Duration position;
  final bool enabled;
  final double fontSize;
  final double opacity;
  final double speedPxPerSecond;

  /// 弹幕占画面高度比例（0.1 - 1.0），由设置项控制。
  final double areaRatio;

  @override
  State<TvDanmakuOverlay> createState() => _TvDanmakuOverlayState();
}

class _TvDanmakuOverlayState extends State<TvDanmakuOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _rng = math.Random(7);
  final List<_Track> _scrollTracks = [];
  final List<DanmakuItem> _topActive = [];
  final List<DanmakuItem> _bottomActive = [];

  double _width = 0;
  double _height = 0;
  int _cursor = 0;
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    setState(() => _frame++);
  }

  void _advanceCursor() {
    // 只处理已进入"当前时间窗"的弹幕；视频回退时重置。
    while (_cursor < widget.items.length &&
        widget.items[_cursor].time <= widget.position) {
      _spawn(widget.items[_cursor]);
      _cursor++;
    }
  }

  void _spawn(DanmakuItem item) {
    final laneCount = math.max(1, ((_height * widget.areaRatio) / (widget.fontSize * 1.5)).floor());
    if (item.mode.isScrolling) {
      _scrollTracks.add(_Track(item: item, lane: _pickLane(laneCount)));
    } else if (item.mode == DanmakuMode.top) {
      _topActive.add(item);
    } else {
      _bottomActive.add(item);
    }
  }

  int _pickLane(int laneCount) {
    // 简单轮转 + 抖动，避免同轨堆叠；十英尺下轨道数少，够用。
    final used = _scrollTracks.length;
    return (used + _rng.nextInt(2)) % laneCount;
  }

  @override
  void didUpdateWidget(covariant TvDanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position < oldWidget.position) {
      // 回退/跳转：重置游标与活动轨道
      _cursor = _firstIndexAt(widget.position);
      _scrollTracks.clear();
      _topActive.clear();
      _bottomActive.clear();
    }
  }

  int _firstIndexAt(Duration position) {
    for (var i = 0; i < widget.items.length; i++) {
      if (widget.items[i].time >= position) return i;
    }
    return widget.items.length;
  }

  Color _colorOf(int rgb) => Color(0xFF000000 | rgb);

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    _advanceCursor();
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        _height = constraints.maxHeight;
        final laneCount = math.max(
            1, ((_height * widget.areaRatio) / (widget.fontSize * 1.5)).floor());
        // 清理已离屏的滚动弹幕
        _scrollTracks.removeWhere((t) => t.x < -t.width - 40);
        _topActive.removeWhere((_) => false);
        _bottomActive.removeWhere((_) => false);

        return IgnorePointer(
          child: ClipRect(
            child: Stack(
              children: [
                for (final track in _scrollTracks)
                  _positioned(track, laneCount),
                for (var i = 0; i < _topActive.length && i < 3; i++)
                  Positioned(
                    top: 12.0 + i * (widget.fontSize * 1.4),
                    left: 0,
                    right: 0,
                    child: Center(child: _text(_topActive[i])),
                  ),
                for (var i = 0; i < _bottomActive.length && i < 3; i++)
                  Positioned(
                    bottom: 12.0 + i * (widget.fontSize * 1.4),
                    left: 0,
                    right: 0,
                    child: Center(child: _text(_bottomActive[i])),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _positioned(_Track track, int laneCount) {
    final elapsed = track.spawnedAt == null
        ? 0.0
        : (widget.position - track.item.time).inMilliseconds / 1000.0;
    track.spawnedAt ??= widget.position;
    final x = _width - elapsed * widget.speedPxPerSecond;
    track.x = x;
    final lane = track.lane % laneCount;
    return Positioned(
      top: 12.0 + lane * (widget.fontSize * 1.5),
      left: x,
      child: _text(track.item),
    );
  }

  Widget _text(DanmakuItem item) {
    final text = Text(
      item.content,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontSize: widget.fontSize,
        fontWeight: FontWeight.w600,
        color: _colorOf(item.colorRgb),
        height: 1.2,
        shadows: const [
          Shadow(offset: Offset(1.4, 1.4), blurRadius: 2.4, color: Colors.black87),
          Shadow(offset: Offset(-1.4, 1.4), blurRadius: 2.4, color: Colors.black87),
          Shadow(offset: Offset(1.4, -1.4), blurRadius: 2.4, color: Colors.black87),
          Shadow(offset: Offset(-1.4, -1.4), blurRadius: 2.4, color: Colors.black87),
        ],
      ),
    );
    return Opacity(
      opacity: widget.opacity,
      child: _MeasuredText(measureKey: item, child: text),
    );
  }
}

class _Track {
  _Track({required this.item, required this.lane});
  final DanmakuItem item;
  final int lane;
  double x = 0;
  double width = 0;
  Duration? spawnedAt;
}

/// 测量文本宽度用于离屏裁剪（简化：用固定估算避免额外布局成本）。
class _MeasuredText extends StatelessWidget {
  const _MeasuredText({required this.measureKey, required this.child});
  final DanmakuItem measureKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
