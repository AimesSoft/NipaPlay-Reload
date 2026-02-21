import 'dart:math';

import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/danmaku_next/danmaku_next_log.dart';

/// Time-driven danmaku layout engine that keeps positions stable after seeking.
class NipaPlayNextEngine {
  Size _size = Size.zero;
  double _fontSize = 0.0;
  double _displayArea = 1.0;
  double _scrollDurationSeconds = 10.0;
  double _staticDurationSeconds = 5.0;
  bool _allowStacking = false;
  int _sourceListIdentity = 0;

  final Map<String, double> _textWidthCache = {};
  static const int _textWidthCacheLimit = 5000;

  final List<_NextItem> _items = [];
  final List<double> _itemTimes = [];
  bool _layoutDirty = true;

  void configure({
    required List<Map<String, dynamic>> danmakuList,
    required Size size,
    required double fontSize,
    required double displayArea,
    required double scrollDurationSeconds,
    required bool allowStacking,
  }) {
    final listIdentity = identityHashCode(danmakuList);
    if (listIdentity != _sourceListIdentity) {
      _sourceListIdentity = listIdentity;
      DanmakuNextLog.d(
        'Engine',
        'configure list changed size=${danmakuList.length}',
        throttle: Duration.zero,
      );
      _parseDanmakuList(danmakuList);
      _layoutDirty = true;
    }

    final normalizedScrollDuration =
        scrollDurationSeconds > 0 ? scrollDurationSeconds : 10.0;

    if (_size != size ||
        _fontSize != fontSize ||
        _displayArea != displayArea ||
        _scrollDurationSeconds != normalizedScrollDuration ||
        _allowStacking != allowStacking) {
      _size = size;
      _fontSize = fontSize;
      _displayArea = displayArea;
      _scrollDurationSeconds = normalizedScrollDuration;
      _allowStacking = allowStacking;
      _layoutDirty = true;
    }

    if (_layoutDirty) {
      _rebuildLayout();
    }
  }

  List<PositionedDanmakuItem> layout(double currentTimeSeconds) {
    if (_items.isEmpty || _size.isEmpty) {
      DanmakuNextLog.d(
        'Engine',
        'layout skipped items=${_items.length} size=${_size.width}x${_size.height}',
        throttle: const Duration(seconds: 2),
      );
      return const [];
    }

    final maxDuration = max(_scrollDurationSeconds, _staticDurationSeconds);
    final windowStart = currentTimeSeconds - maxDuration;
    final left = _lowerBound(windowStart);
    final right = _upperBound(currentTimeSeconds);

    final List<PositionedDanmakuItem> positioned = [];

    for (int i = left; i < right; i++) {
      final item = _items[i];
      if (item.trackIndex < 0) continue;

      final elapsed = currentTimeSeconds - item.timeSeconds;
      if (elapsed < 0) continue;

      switch (item.type) {
        case DanmakuItemType.scroll:
          if (elapsed > _scrollDurationSeconds) continue;
          final x = _size.width - item.scrollSpeed * elapsed;
          positioned.add(
            PositionedDanmakuItem(
              content: item.content,
              x: x,
              y: item.yPosition,
              offstageX: _size.width + item.width,
              time: item.timeSeconds,
            ),
          );
          break;
        case DanmakuItemType.top:
        case DanmakuItemType.bottom:
          if (elapsed > _staticDurationSeconds) continue;
          final x = (_size.width - item.width) / 2;
          positioned.add(
            PositionedDanmakuItem(
              content: item.content,
              x: x,
              y: item.yPosition,
              offstageX: _size.width,
              time: item.timeSeconds,
            ),
          );
          break;
      }
    }

    DanmakuNextLog.d(
      'Engine',
      'layout time=${currentTimeSeconds.toStringAsFixed(2)} window=[$windowStart..$currentTimeSeconds] '
      'range=[$left,$right) out=${positioned.length}',
      throttle: const Duration(seconds: 1),
    );
    return positioned;
  }

  void _parseDanmakuList(List<Map<String, dynamic>> danmakuList) {
    _items.clear();
    _itemTimes.clear();

    for (final raw in danmakuList) {
      final time = (raw['time'] as num?)?.toDouble() ?? 0.0;
      final text = raw['content']?.toString() ?? '';
      if (text.isEmpty) continue;

      final type = _parseType(raw['type']);
      final color = _parseColor(raw['color']);
      final isMe = raw['isMe'] == true;

      final content = DanmakuContentItem(
        text,
        type: type,
        color: color,
        isMe: isMe,
      );

      _items.add(
        _NextItem(
          timeSeconds: time,
          content: content,
          type: type,
        ),
      );
    }

    _items.sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));
    for (final item in _items) {
      _itemTimes.add(item.timeSeconds);
    }

    if (_items.isEmpty) {
      DanmakuNextLog.d('Engine', 'parse list empty', throttle: Duration.zero);
    } else {
      final first = _items.first.timeSeconds;
      final last = _items.last.timeSeconds;
      DanmakuNextLog.d(
        'Engine',
        'parse list ok count=${_items.length} timeRange=[${first.toStringAsFixed(2)}..${last.toStringAsFixed(2)}]',
        throttle: Duration.zero,
      );
    }
  }

  void _rebuildLayout() {
    _layoutDirty = false;

    if (_items.isEmpty || _size.isEmpty) {
      DanmakuNextLog.d(
        'Engine',
        'layout rebuild skipped items=${_items.length} size=${_size.width}x${_size.height}',
        throttle: Duration.zero,
      );
      return;
    }

    final baseVerticalSpacing = globals.isPhone ? 10.0 : 20.0;
    final defaultFontSize = globals.isPhone ? 20.0 : 30.0;
    final scale = (_fontSize / defaultFontSize).clamp(0.7, 2.5);
    final verticalSpacing = baseVerticalSpacing * scale;
    final lineHeight = _fontSize * 1.1;
    final trackHeight = lineHeight + verticalSpacing;
    final effectiveHeight = max(1.0, _size.height * _displayArea);

    int trackCount = (effectiveHeight / trackHeight).floor();
    if (trackCount <= 0) trackCount = 1;

    DanmakuNextLog.d(
      'Engine',
      'layout rebuild tracks=$trackCount font=${_fontSize.toStringAsFixed(1)} area=${_displayArea.toStringAsFixed(2)} '
      'scroll=${_scrollDurationSeconds.toStringAsFixed(1)} stacking=$_allowStacking',
      throttle: Duration.zero,
    );

    final scrollTracks = List<_ScrollTrackState>.generate(
      trackCount,
      (_) => _ScrollTrackState.empty(),
    );
    final topTrackLastTime = List<double>.filled(
      trackCount,
      double.negativeInfinity,
    );
    final bottomTrackLastTime = List<double>.filled(
      trackCount,
      double.negativeInfinity,
    );

    final safeMargin = _size.width * 0.02;

    for (final item in _items) {
      final width = _measureTextWidth(item.content.text, _fontSize);
      item.width = width;

      switch (item.type) {
        case DanmakuItemType.scroll:
          final speed = (_size.width + width) / _scrollDurationSeconds;
          item.scrollSpeed = speed;

          final selectedTrack = _selectScrollTrack(
            time: item.timeSeconds,
            speed: speed,
            tracks: scrollTracks,
            trackCount: trackCount,
            allowStacking: _allowStacking,
          );

          if (selectedTrack < 0) {
            item.trackIndex = -1;
            continue;
          }

          item.trackIndex = selectedTrack;
          item.yPosition = selectedTrack * trackHeight +
              verticalSpacing -
              _fontSize * 2 / 3;

          final nextAvailable = item.timeSeconds +
              _scrollDurationSeconds *
                  ((width + safeMargin) / (_size.width + width));

          scrollTracks[selectedTrack] = _ScrollTrackState(
            timeSeconds: item.timeSeconds,
            width: width,
            speed: speed,
            nextAvailableTime: nextAvailable,
          );
          break;
        case DanmakuItemType.top:
          final selectedTrack = _selectStaticTrack(
            time: item.timeSeconds,
            lastTimes: topTrackLastTime,
            trackCount: trackCount,
            allowStacking: _allowStacking,
          );
          if (selectedTrack < 0) {
            item.trackIndex = -1;
            continue;
          }

          item.trackIndex = selectedTrack;
          topTrackLastTime[selectedTrack] = item.timeSeconds;
          item.yPosition = selectedTrack * trackHeight +
              verticalSpacing -
              _fontSize * 2 / 3;
          break;
        case DanmakuItemType.bottom:
          final selectedTrack = _selectStaticTrack(
            time: item.timeSeconds,
            lastTimes: bottomTrackLastTime,
            trackCount: trackCount,
            allowStacking: _allowStacking,
          );
          if (selectedTrack < 0) {
            item.trackIndex = -1;
            continue;
          }

          item.trackIndex = selectedTrack;
          bottomTrackLastTime[selectedTrack] = item.timeSeconds;
          item.yPosition = _size.height -
              (selectedTrack + 1) * trackHeight -
              lineHeight;
          break;
      }
    }
  }

  int _selectScrollTrack({
    required double time,
    required double speed,
    required List<_ScrollTrackState> tracks,
    required int trackCount,
    required bool allowStacking,
  }) {
    int? selected;
    double earliestNextAvailable = double.infinity;
    int earliestTrack = 0;

    for (int i = 0; i < trackCount; i++) {
      final track = tracks[i];
      if (track.isEmpty) {
        selected = i;
        break;
      }

      if (track.nextAvailableTime <= time) {
        if (speed <= track.speed) {
          selected = i;
          break;
        }

        final trackLeaveTime = track.timeSeconds +
            (_size.width + track.width) / track.speed;
        if (time >= trackLeaveTime) {
          selected = i;
          break;
        }
      }

      if (track.nextAvailableTime < earliestNextAvailable) {
        earliestNextAvailable = track.nextAvailableTime;
        earliestTrack = i;
      }
    }

    if (selected != null) return selected;
    if (!allowStacking) return -1;
    return earliestTrack;
  }

  int _selectStaticTrack({
    required double time,
    required List<double> lastTimes,
    required int trackCount,
    required bool allowStacking,
  }) {
    int? selected;
    double earliestTime = double.infinity;
    int earliestTrack = 0;

    for (int i = 0; i < trackCount; i++) {
      final lastTime = lastTimes[i];
      if (time - lastTime >= _staticDurationSeconds) {
        selected = i;
        break;
      }
      if (lastTime < earliestTime) {
        earliestTime = lastTime;
        earliestTrack = i;
      }
    }

    if (selected != null) return selected;
    if (!allowStacking) return -1;
    return earliestTrack;
  }

  DanmakuItemType _parseType(dynamic raw) {
    if (raw is DanmakuItemType) return raw;
    if (raw is num) {
      final code = raw.toInt();
      if (code == 5) return DanmakuItemType.top;
      if (code == 4) return DanmakuItemType.bottom;
      return DanmakuItemType.scroll;
    }

    final value = raw?.toString().toLowerCase() ?? 'scroll';
    switch (value) {
      case 'top':
        return DanmakuItemType.top;
      case 'bottom':
        return DanmakuItemType.bottom;
      case 'scroll':
      case 'right':
      default:
        return DanmakuItemType.scroll;
    }
  }

  Color _parseColor(dynamic raw) {
    if (raw is Color) return raw;
    if (raw is int) {
      final value = raw & 0xFFFFFF;
      return Color(0xFF000000 | value);
    }

    final value = raw?.toString() ?? '';
    if (value.startsWith('rgb')) {
      final parts = value
          .replaceAll('rgb(', '')
          .replaceAll(')', '')
          .split(',')
          .map((s) => int.tryParse(s.trim()) ?? 255)
          .toList();
      if (parts.length >= 3) {
        return Color.fromARGB(255, parts[0], parts[1], parts[2]);
      }
    }

    if (value.startsWith('#')) {
      final hex = value.substring(1);
      final parsed = int.tryParse(hex, radix: 16);
      if (parsed != null) {
        return Color(0xFF000000 | parsed);
      }
    }

    if (value.startsWith('0x')) {
      final parsed = int.tryParse(value.substring(2), radix: 16);
      if (parsed != null) {
        return Color(0xFF000000 | parsed);
      }
    }

    return Colors.white;
  }

  double _measureTextWidth(String text, double fontSize) {
    final key = '$fontSize|$text';
    final cached = _textWidthCache[key];
    if (cached != null) return cached;

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        locale: const Locale('zh-Hans', 'zh'),
        style: TextStyle(
          fontSize: fontSize,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: double.infinity);

    final width = tp.size.width;
    if (_textWidthCache.length > _textWidthCacheLimit) {
      _textWidthCache.clear();
    }
    _textWidthCache[key] = width;
    return width;
  }

  int _lowerBound(double value) {
    int lo = 0;
    int hi = _itemTimes.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_itemTimes[mid] < value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  int _upperBound(double value) {
    int lo = 0;
    int hi = _itemTimes.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_itemTimes[mid] <= value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

class _NextItem {
  final double timeSeconds;
  final DanmakuContentItem content;
  final DanmakuItemType type;

  int trackIndex = -1;
  double yPosition = 0.0;
  double width = 0.0;
  double scrollSpeed = 0.0;

  _NextItem({
    required this.timeSeconds,
    required this.content,
    required this.type,
  });
}

class _ScrollTrackState {
  final double timeSeconds;
  final double width;
  final double speed;
  final double nextAvailableTime;

  const _ScrollTrackState({
    required this.timeSeconds,
    required this.width,
    required this.speed,
    required this.nextAvailableTime,
  });

  factory _ScrollTrackState.empty() {
    return const _ScrollTrackState(
      timeSeconds: double.negativeInfinity,
      width: 0.0,
      speed: 0.0,
      nextAvailableTime: double.negativeInfinity,
    );
  }

  bool get isEmpty => timeSeconds == double.negativeInfinity;
}
