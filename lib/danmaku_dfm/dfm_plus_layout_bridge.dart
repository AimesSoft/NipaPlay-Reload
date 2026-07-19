import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/constants/danmaku/mode.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/src/rust/api/dfm_plus.dart' as rust_dfm;
import 'package:nipaplay/src/rust/rust_init.dart';

class DfmPlusLayoutBridge {
  rust_dfm.DfmPlusPreparedLayout? _prepared;
  int _sourceListIdentity = 0;
  int _sourceListVersion = -1;
  double _lastFontSize = -1;
  double _lastDisplayArea = -1;
  bool _lastMergeDanmaku = false;
  double _lastTrackGapRatio = -1;
  double _lastOutlineWidth = -1;
  String _lastCustomFontFamily = '';
  String _lastCustomFontFilePath = '';
  List<String> _lastBlockWords = const [];

  Uint8List? _cachedFontBytes;
  String? _cachedFontFilePath;

  /// Reusable buffer for layout results — avoids per-frame allocation/GC.
  final List<PositionedDanmakuItem> _layoutBuffer = [];

  /// Content item cache keyed by prepared item index — avoids recreating
  /// DanmakuContentItem (with Color object) every frame for the same item.
  final Map<int, DanmakuContentItem> _contentCache = {};

  /// Positioned item cache keyed by prepared item index — avoids recreating
  /// PositionedDanmakuItem objects every frame, preserving displayX across frames
  /// for wall-clock incremental positioning.
  final Map<int, PositionedDanmakuItem> _positionedCache = {};

  /// Code points already dispatched for async prefetch-rasterization.
  /// Deduplicates so each frame sends only the delta (new chars entering the
  /// lookahead window). Cleared on configure (layout/font change).
  final Set<int> _prefetched = {};

  /// Soft-prune bookkeeping (P2-8). On long videos where the danmaku list /
  /// font size never change, configure() (which clears the caches) is never
  /// re-invoked, so _contentCache/_positionedCache grow unbounded as the
  /// visible window scrolls through ever-increasing item indices. Every
  /// ~30s, if the caches hold far more entries than the current visible
  /// window, clear them — putIfAbsent rebuilds only the currently-visible
  /// items on the next frame (one cheap Color/object allocation each).
  int _lastPruneTimestampMs = 0;
  static const int _pruneIntervalMs = 30000;

  Future<void> configure({
    required List<Map<String, dynamic>> danmakuList,
    required int danmakuListVersion,
    required Size size,
    required double fontSize,
    required double displayArea,
    required double scrollDurationSeconds,
    required bool allowStacking,
    required bool mergeDanmaku,
    int? maxQuantity,
    int? maxLinesPerType,
    double trackGapRatio = 0.15,
    double outlineWidth = 0.0,
    String customFontFamily = '',
    String customFontFilePath = '',
    List<String> blockWords = const [],
  }) async {
    final listIdentity = identityHashCode(danmakuList);
    final changed = listIdentity != _sourceListIdentity ||
        danmakuListVersion != _sourceListVersion ||
        _prepared == null ||
        (_lastFontSize - fontSize).abs() > 0.001 ||
        (_lastDisplayArea - displayArea).abs() > 0.0001 ||
        _lastMergeDanmaku != mergeDanmaku ||
        (_lastTrackGapRatio - trackGapRatio).abs() > 0.001 ||
        (_lastOutlineWidth - outlineWidth).abs() > 0.001 ||
        _lastCustomFontFamily != customFontFamily ||
        _lastCustomFontFilePath != customFontFilePath ||
        !listEquals(_lastBlockWords, blockWords) ||
        !_sameLayoutConfig(
          _prepared!,
          size: size,
          scrollDurationSeconds: scrollDurationSeconds,
        );

    if (!changed) {
      return;
    }

    final oldHandle = _prepared?.handle;
    if (oldHandle != null && oldHandle != BigInt.zero) {
      rust_dfm.dfmPlusDropLayout(handle: oldHandle);
    }

    final fontBytes = await _loadFontBytes(customFontFilePath);

    final rawItems = <rust_dfm.DfmPlusRawDanmakuItem>[];
    for (final raw in danmakuList) {
      final text = (raw['content'] ?? raw['c'])?.toString() ?? '';
      if (text.isEmpty) {
        continue;
      }
      final time = _resolveTime(raw);
      final typeCode = _parseType(raw['type']);
      final colorArgb = _parseColor(raw['color']);
      final isMe = raw['isMe'] == true;

      rawItems.add(
        rust_dfm.DfmPlusRawDanmakuItem(
          timeSeconds: time,
          text: text,
          typeCode: typeCode,
          colorArgb: colorArgb,
          isMe: isMe,
        ),
      );
    }

    await ensureRustInitialized();
    _prepared = await rust_dfm.dfmPlusPrepareLayoutFull(
      rawItems: rawItems,
      width: size.width,
      height: size.height,
      fontSize: fontSize,
      displayArea: displayArea,
      scrollDurationSeconds: scrollDurationSeconds,
      allowStacking: allowStacking,
      mergeDanmaku: mergeDanmaku,
      maxQuantity: maxQuantity,
      maxLinesPerType: maxLinesPerType,
      trackGapRatio: trackGapRatio,
      outlineWidth: outlineWidth,
      customFontBytes: fontBytes,
      blockWords: blockWords,
    );
    _sourceListIdentity = listIdentity;
    _sourceListVersion = danmakuListVersion;
    _lastFontSize = fontSize;
    _lastDisplayArea = displayArea;
    _lastMergeDanmaku = mergeDanmaku;
    _lastTrackGapRatio = trackGapRatio;
    _lastOutlineWidth = outlineWidth;
    _lastCustomFontFamily = customFontFamily;
    _lastCustomFontFilePath = customFontFilePath;
    _lastBlockWords = List.unmodifiable(blockWords);
    // Layout changed — content and position caches are stale, clear them
    _contentCache.clear();
    _positionedCache.clear();
    _prefetched.clear();
  }

  /// Synchronous layout: computes frame positions in Dart using the
  /// prepared layout data. This avoids the async Rust FFI call that was
  /// the primary source of frame-to-frame jitter (each await introduces
  /// at least one microtask delay, and the 3-await chain could exceed
  /// the 16.67ms frame budget).
  ///
  /// The position calculation is identical to Rust's `build_dfm_plus_frame`:
  /// binary search for visible window + per-item x/y computation.
  /// Object reuse: PositionedDanmakuItem and DanmakuContentItem are cached
  /// and mutated in-place, avoiding per-frame allocation and GC pressure.
  List<PositionedDanmakuItem> layout(double currentTimeSeconds) {
    final prepared = _prepared;
    if (prepared == null) {
      return const [];
    }

    final items = prepared.items;
    final itemTimes = prepared.itemTimes;
    final width = prepared.width;
    final scrollDur = prepared.scrollDurationSeconds;
    final staticDur = prepared.staticDurationSeconds;
    final maxDur = scrollDur > staticDur ? scrollDur : staticDur;

    final windowStart = currentTimeSeconds - maxDur;
    final startIdx = _lowerBound(itemTimes, windowStart);
    final endIdx = _upperBound(itemTimes, currentTimeSeconds);

    // Soft-prune caches that drifted beyond the visible window on long
    // videos (P2-8). Clears only when caches hold far more than the current
    // window AND at least 30s since the last prune — putIfAbsent rebuilds
    // visible items next frame, so this is invisible to the user.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastPruneTimestampMs >= _pruneIntervalMs) {
      _lastPruneTimestampMs = nowMs;
      final windowSize = endIdx - startIdx;
      if (_positionedCache.length > windowSize * 2 &&
          _positionedCache.length > 64) {
        _contentCache.clear();
        _positionedCache.clear();
      }
    }

    // Reuse buffer — clear without deallocating
    final result = _layoutBuffer..clear();

    for (int i = startIdx; i < endIdx; i++) {
      final pi = items[i];
      final elapsed = currentTimeSeconds - pi.timeSeconds;
      if (elapsed < 0.0) continue;

      if (!pi.isScroll && elapsed > pi.durationSeconds) continue;

      double x;
      double offstageX;

      if (pi.isScroll) {
        final speed = pi.scrollSpeed;
        if (pi.typeCode == 6) {
          // ScrollLR
          x = speed * elapsed - pi.width;
          offstageX = -pi.width;
        } else {
          // ScrollRL
          x = width - speed * elapsed;
          offstageX = width + pi.width;
        }
      } else {
        x = pi.centeredX;
        offstageX = width;
      }

      if (pi.isScroll && x < -pi.width) continue;
      if (pi.yPosition < 0.0) continue;

      // Reuse DanmakuContentItem from cache (avoids Color() allocation)
      final content = _contentCache.putIfAbsent(
          i,
          () => DanmakuContentItem(
                pi.text,
                type: _toItemType(pi.typeCode),
                color: Color(pi.colorArgb),
                isMe: pi.isMe,
                fontSizeMultiplier: pi.fontSizeMultiplier,
                countText: pi.countText,
              ));

      // Reuse PositionedDanmakuItem from cache (preserves displayX across frames
      // for wall-clock incremental positioning).
      final positioned = _positionedCache.putIfAbsent(
          i,
          () => PositionedDanmakuItem(
                content: content,
                x: x,
                y: pi.yPosition,
                offstageX: offstageX,
                time: pi.timeSeconds,
                scrollSpeed: pi.isScroll ? pi.scrollSpeed : 0.0,
                width: pi.width,
                typeCode: pi.typeCode,
              ));

      // Update mutable fields from fresh absolute-position computation.
      // displayX is intentionally NOT overwritten — it is managed by the
      // wall-clock incremental positioning logic in DfmPlusOverlay.
      positioned.x = x;
      positioned.y = pi.yPosition;
      positioned.offstageX = offstageX;
      positioned.scrollSpeed = pi.isScroll ? pi.scrollSpeed : 0.0;
      positioned.width = pi.width;
      positioned.typeCode = pi.typeCode;

      result.add(positioned);
    }

    return result;
  }

  /// Lookahead prefetch: returns a string of chars appearing in danmaku with
  /// time in [currentTime, currentTime + lookaheadSec] that haven't been
  /// prefetched yet (the delta), or null if no new chars. Recorded chars are
  /// added to `_prefetched` so subsequent calls skip them.
  ///
  /// Drives async MSDF rasterization on the Rust side so glyphs are ready in
  /// the atlas before the danmaku enters the visible window - avoids the
  /// synchronous rasterize-and-block fallback that causes frame hitches.
  String? prefetchChars(double currentTime, double lookaheadSec) {
    final prepared = _prepared;
    if (prepared == null) return null;
    final items = prepared.items;
    final itemTimes = prepared.itemTimes;
    if (items.isEmpty || itemTimes.isEmpty) return null;

    final end = currentTime + lookaheadSec;
    final startIdx = _upperBound(itemTimes, currentTime);
    final endIdx = _upperBound(itemTimes, end);
    if (startIdx >= endIdx) return null;

    final buf = StringBuffer();
    for (int i = startIdx; i < endIdx; i++) {
      final text = items[i].text;
      for (final code in text.runes) {
        if (_prefetched.add(code)) {
          buf.writeCharCode(code);
        }
      }
    }
    if (buf.isEmpty) return null;
    return buf.toString();
  }

  /// Reset prefetch tracking. Called on configure (layout/font/danmaku change)
  /// so the new content gets freshly prefetched.
  void resetPrefetch() {
    _prefetched.clear();
  }

  /// Binary search: first index where itemTimes[i] >= target.
  int _lowerBound(Float64List times, double target) {
    int lo = 0;
    int hi = times.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (times[mid] < target) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Binary search: first index where itemTimes[i] > target.
  int _upperBound(Float64List times, double target) {
    int lo = 0;
    int hi = times.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (times[mid] <= target) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  void dispose() {
    final handle = _prepared?.handle;
    if (handle != null && handle != BigInt.zero) {
      rust_dfm.dfmPlusDropLayout(handle: handle);
    }
    _prepared = null;
    _contentCache.clear();
    _positionedCache.clear();
    _prefetched.clear();
  }

  bool _sameLayoutConfig(
    rust_dfm.DfmPlusPreparedLayout prepared, {
    required Size size,
    required double scrollDurationSeconds,
  }) {
    return (prepared.width - size.width).abs() < 0.5 &&
        (prepared.height - size.height).abs() < 0.5 &&
        (prepared.scrollDurationSeconds - scrollDurationSeconds).abs() < 0.001;
  }

  /// Load custom font file bytes. Cached to avoid re-reading on every configure() call.
  Future<Uint8List?> _loadFontBytes(String fontFilePath) async {
    if (fontFilePath.isEmpty) {
      return null;
    }
    if (_cachedFontFilePath == fontFilePath && _cachedFontBytes != null) {
      return _cachedFontBytes;
    }
    try {
      final file = io.File(fontFilePath);
      if (await file.exists()) {
        _cachedFontBytes = await file.readAsBytes();
        _cachedFontFilePath = fontFilePath;
        return _cachedFontBytes;
      }
    } catch (_) {
      // Fall through to no custom font
    }
    _cachedFontBytes = null;
    _cachedFontFilePath = fontFilePath;
    return null;
  }

  double _resolveTime(Map<String, dynamic> raw) {
    final value = raw['time'] ?? raw['t'];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  int _parseType(dynamic raw) {
    if (raw is num) {
      final code = raw.toInt();
      return code;
    }
    return DanmakuMode.fromTypeName(raw?.toString()).code;
  }

  int _parseColor(dynamic raw) {
    if (raw is int) {
      final value = raw & 0x00FFFFFF;
      return (0xFF000000 | value).toSigned(32);
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
        return Color.fromARGB(255, parts[0], parts[1], parts[2]).toARGB32();
      }
    }

    if (value.startsWith('#')) {
      final hex = value.substring(1);
      final parsed = int.tryParse(hex, radix: 16);
      if (parsed != null) {
        return (0xFF000000 | parsed).toSigned(32);
      }
    }

    if (value.startsWith('0x')) {
      final parsed = int.tryParse(value.substring(2), radix: 16);
      if (parsed != null) {
        return (0xFF000000 | parsed).toSigned(32);
      }
    }

    return Colors.white.toARGB32();
  }

  DanmakuItemType _toItemType(int typeCode) {
    switch (DanmakuMode.fromCode(typeCode)) {
      case DanmakuMode.top:
        return DanmakuItemType.top;
      case DanmakuMode.bottom:
        return DanmakuItemType.bottom;
      default:
        return DanmakuItemType.scroll;
    }
  }
}
