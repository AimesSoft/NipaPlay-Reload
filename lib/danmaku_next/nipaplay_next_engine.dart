import 'dart:math';

import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/danmaku_next/danmaku_next_log.dart';

/// Time-driven danmaku layout engine that keeps positions stable after seeking.
class NipaPlayNextEngine {
  Size _size = Size.zero;
  double _fontSize = 0.0;
  double _displayArea = 1.0;
  double _scrollDurationSeconds = 10.0;
  double _staticDurationSeconds = 10.0;
  bool _allowStacking = false;
  bool _mergeDanmaku = false;
  int _sourceListIdentity = 0;

  final Map<String, double> _textWidthCache = {};
  static const int _textWidthCacheLimit = 5000;
  static const double _mergeWindowSeconds = 45.0;

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
    required bool mergeDanmaku,
  }) {
    final listIdentity = identityHashCode(danmakuList);
    final mergeChanged = mergeDanmaku != _mergeDanmaku;
    if (listIdentity != _sourceListIdentity || mergeChanged) {
      _sourceListIdentity = listIdentity;
      _mergeDanmaku = mergeDanmaku;
      DanmakuNextLog.d(
        'Engine',
        'configure list changed size=${danmakuList.length} merge=$_mergeDanmaku',
        throttle: Duration.zero,
      );
      _parseDanmakuList(danmakuList);
      _layoutDirty = true;
    }

    final normalizedScrollDuration =
        scrollDurationSeconds > 0 ? scrollDurationSeconds : 10.0;
    final normalizedStaticDuration = normalizedScrollDuration;

    if (_size != size ||
        _fontSize != fontSize ||
        _displayArea != displayArea ||
        _scrollDurationSeconds != normalizedScrollDuration ||
        _staticDurationSeconds != normalizedStaticDuration ||
        _allowStacking != allowStacking) {
      _size = size;
      _fontSize = fontSize;
      _displayArea = displayArea;
      _scrollDurationSeconds = normalizedScrollDuration;
      _staticDurationSeconds = normalizedStaticDuration;
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

    final List<Map<String, dynamic>> sourceList = _mergeDanmaku
        ? _prepareMergedDanmakuList(danmakuList)
        : List<Map<String, dynamic>>.from(danmakuList);

    for (final raw in sourceList) {
      final time = _resolveTime(raw);
      final text = _resolveContent(raw);
      if (text.isEmpty) continue;

      final type = _parseType(raw['type']);
      final color = _parseColor(raw['color']);
      final isMe = raw['isMe'] == true;
      final isMerged = raw['merged'] == true;
      final mergeCount = (raw['mergeCount'] as int?) ?? 1;

      final content = DanmakuContentItem(
        text,
        type: type,
        color: color,
        isMe: isMe,
        fontSizeMultiplier: isMerged
            ? _calcMergedFontSizeMultiplier(mergeCount)
            : 1.0,
        countText: isMerged ? 'x$mergeCount' : null,
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

    double danmakuHeight = _measureTextHeight(_fontSize);
    if (_mergeDanmaku && _items.isNotEmpty) {
      double maxMultiplier = 1.0;
      for (final item in _items) {
        if (item.content.fontSizeMultiplier > maxMultiplier) {
          maxMultiplier = item.content.fontSizeMultiplier;
        }
      }
      if (maxMultiplier > 1.0) {
        danmakuHeight = _measureTextHeight(_fontSize * maxMultiplier);
      }
    }
    final effectiveHeight = max(1.0, _size.height * _displayArea);

    int trackCount;
    if (_displayArea <= 0 || _displayArea.isNaN || _displayArea.isInfinite) {
      trackCount = 1;
    } else {
      trackCount = (effectiveHeight / danmakuHeight).floor();
    }

    if (_displayArea == 1.0) {
      trackCount -= 1;
    }
    if (trackCount <= 0) trackCount = 1;

    DanmakuNextLog.d(
      'Engine',
      'layout rebuild tracks=$trackCount font=${_fontSize.toStringAsFixed(1)} area=${_displayArea.toStringAsFixed(2)} '
      'scroll=${_scrollDurationSeconds.toStringAsFixed(1)} stacking=$_allowStacking',
      throttle: Duration.zero,
    );

    final trackYPositions = List<double>.generate(
      trackCount,
      (i) => i * danmakuHeight,
    );

    final List<List<_NextItem>> scrollTracks =
        List<List<_NextItem>>.generate(trackCount, (_) => <_NextItem>[]);
    final List<_NextItem?> topTrackItems =
        List<_NextItem?>.filled(trackCount, null);
    final List<_NextItem?> bottomTrackItems =
        List<_NextItem?>.filled(trackCount, null);

    for (final item in _items) {
      final width = _measureTextWidth(
        item.content.text,
        _fontSize * item.content.fontSizeMultiplier,
      );
      item.width = width;

      switch (item.type) {
        case DanmakuItemType.scroll:
          final speed = (_size.width + width) / _scrollDurationSeconds;
          item.scrollSpeed = speed;

          final selectedTrack = _selectScrollTrackCanvas(
            item: item,
            time: item.timeSeconds,
            newWidth: width,
            tracks: scrollTracks,
            trackCount: trackCount,
          );

          if (selectedTrack < 0) {
            item.trackIndex = -1;
            continue;
          }

          item.trackIndex = selectedTrack;
          item.yPosition = trackYPositions[selectedTrack];
          scrollTracks[selectedTrack].add(item);
          break;
        case DanmakuItemType.top:
          final selectedTrack = _selectStaticTrackCanvas(
            time: item.timeSeconds,
            tracks: topTrackItems,
            trackCount: trackCount,
          );
          if (selectedTrack < 0) {
            item.trackIndex = -1;
            continue;
          }

          item.trackIndex = selectedTrack;
          topTrackItems[selectedTrack] = item;
          item.yPosition = trackYPositions[selectedTrack];
          break;
        case DanmakuItemType.bottom:
          final selectedTrack = _selectStaticTrackCanvas(
            time: item.timeSeconds,
            tracks: bottomTrackItems,
            trackCount: trackCount,
          );
          if (selectedTrack < 0) {
            item.trackIndex = -1;
            continue;
          }

          item.trackIndex = selectedTrack;
          bottomTrackItems[selectedTrack] = item;
          item.yPosition = _size.height - trackYPositions[selectedTrack] - danmakuHeight;
          break;
      }
    }
  }

  int _selectScrollTrackCanvas({
    required _NextItem item,
    required double time,
    required double newWidth,
    required List<List<_NextItem>> tracks,
    required int trackCount,
  }) {
    for (int i = 0; i < trackCount; i++) {
      final trackItems = tracks[i];
      if (trackItems.isNotEmpty) {
        trackItems.removeWhere(
          (existing) => time - existing.timeSeconds > _scrollDurationSeconds,
        );
      }

      if (_scrollCanAddToTrack(trackItems, newWidth, time)) {
        return i;
      }
    }

    if (item.content.isMe && trackCount > 0) {
      return 0;
    }

    if (_allowStacking && trackCount > 0) {
      return _pickStackedTrack(item, trackCount);
    }

    return -1;
  }

  bool _scrollCanAddToTrack(
    List<_NextItem> trackItems,
    double newWidth,
    double time,
  ) {
    for (final existing in trackItems) {
      final elapsed = time - existing.timeSeconds;
      if (elapsed < 0 || elapsed > _scrollDurationSeconds) {
        continue;
      }
      final existingX = _size.width -
          (elapsed / _scrollDurationSeconds) * (_size.width + existing.width);
      final existingEnd = existingX + existing.width;

      if (_size.width - existingEnd < 0) {
        return false;
      }
      if (existing.width < newWidth) {
        final double progress =
            (_size.width - existingX) / (existing.width + _size.width);
        if ((1 - progress) > (_size.width / (_size.width + newWidth))) {
          return false;
        }
      }
    }
    return true;
  }

  int _pickStackedTrack(_NextItem item, int trackCount) {
    final int base = item.content.text.hashCode ^ item.timeSeconds.toInt();
    final int hash = base & 0x7fffffff;
    return hash % trackCount;
  }

  int _selectStaticTrackCanvas({
    required double time,
    required List<_NextItem?> tracks,
    required int trackCount,
  }) {
    for (int i = 0; i < trackCount; i++) {
      final existing = tracks[i];
      if (existing == null) {
        return i;
      }
      if (time - existing.timeSeconds >= _staticDurationSeconds) {
        return i;
      }
    }
    return -1;
  }

  List<Map<String, dynamic>> _prepareMergedDanmakuList(
      List<Map<String, dynamic>> danmakuList) {
    if (danmakuList.isEmpty) return const [];

    final List<Map<String, dynamic>> sorted =
        List<Map<String, dynamic>>.from(danmakuList);
    sorted.sort((a, b) => _resolveTime(a).compareTo(_resolveTime(b)));

    final Map<String, int> windowContentCount = {};
    final Map<String, double> firstTime = {};
    final Map<String, Map<String, dynamic>> processed = {};

    int left = 0;
    for (int right = 0; right < sorted.length; right++) {
      final current = sorted[right];
      final content = _resolveContent(current);
      if (content.isEmpty) {
        continue;
      }
      final time = _resolveTime(current);

      windowContentCount[content] = (windowContentCount[content] ?? 0) + 1;

      while (left <= right &&
          time - _resolveTime(sorted[left]) > _mergeWindowSeconds) {
        final leftContent = _resolveContent(sorted[left]);
        if (leftContent.isNotEmpty) {
          windowContentCount[leftContent] =
              (windowContentCount[leftContent] ?? 1) - 1;
          if (windowContentCount[leftContent] == 0) {
            windowContentCount.remove(leftContent);
          }
        }
        left++;
      }

      final count = windowContentCount[content] ?? 1;
      final key = '$content-$time';

      if (count > 1) {
        firstTime[content] ??= time;
        processed[key] = {
          ...current,
          'merged': true,
          'mergeCount': count,
          'isFirstInGroup': time == firstTime[content],
          'groupContent': content,
        };
      } else {
        processed[key] = current;
      }
    }

    final List<Map<String, dynamic>> output = [];
    for (final item in sorted) {
      final content = _resolveContent(item);
      if (content.isEmpty) continue;
      final time = _resolveTime(item);
      final key = '$content-$time';
      final processedItem = processed[key] ?? item;
      if (processedItem['merged'] == true &&
          processedItem['isFirstInGroup'] == false) {
        continue;
      }
      output.add(processedItem);
    }

    return output;
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

  double _resolveTime(Map<String, dynamic> raw) {
    final value = raw['time'] ?? raw['t'];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  String _resolveContent(Map<String, dynamic> raw) {
    return (raw['content'] ?? raw['c'])?.toString() ?? '';
  }

  double _calcMergedFontSizeMultiplier(int mergeCount) {
    double multiplier = 1.0 + (mergeCount / 10.0);
    return multiplier.clamp(1.0, 2.0);
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

  double _measureTextHeight(double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: '弹幕',
        locale: const Locale('zh-Hans', 'zh'),
        style: TextStyle(
          fontSize: fontSize,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: double.infinity);

    final height = tp.size.height;
    return height.isFinite && height > 0 ? height : fontSize;
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
