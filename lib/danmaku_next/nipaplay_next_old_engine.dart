import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, listEquals, kIsWeb, kReleaseMode;
import 'package:nipaplay/constants/danmaku/mode.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/danmaku_next/danmaku_next_log.dart';
import 'package:nipaplay/cpp_native/bindings/danmaku_layout.dart';

const String _logTag = 'NipaPlayNextOldEngine';


/// Frame log throttle: last time a frame log was emitted (global, ms)
int _lastFrameLogTimeMs = 0;

/// Next Old 引擎 — d6592232 版布局引擎（含 C++ FFI + Dart fallback）。
/// 关闭 Next++ 激进优化时，此引擎替代 NipaPlayNextEngine。
/// 与当前 NipaPlayNextEngine (Next++) 的区别：
/// - 使用绝对定位 x = width - scrollSpeed * elapsed（无 displayX 增量定位）
/// - 使用 TextPainter 逐条绘制（无精灵图集 / toImageSync / vsync）
/// - playbackTimeMs 驱动重绘（8-30Hz，非 vsync 60-240Hz）
class NipaPlayNextOldEngine {
  /// Unique instance identifier for log disambiguation
  final String _id;
  Size _size = Size.zero;
  double _fontSize = 0.0;
  double _displayArea = 1.0;
  double _scrollDurationSeconds = 10.0;
  double _staticDurationSeconds = 10.0;
  bool _allowStacking = false;
  bool _mergeDanmaku = false;
  String? _fontFamily;
  List<String>? _fontFamilyFallback;
  Locale? _locale;
  int _sourceListIdentity = 0;

  // ──── Native (C++ FFI) layout engine ────
  DanmakuLayoutEngine? _nativeEngine;
  bool _nativeEngineTried = false;
  bool _nativeEngineAvailable = false;
  bool _dartFallbackNotified = false; // 仅在首次 Dart fallback 时输出一次 Release 可见日志

  final LinkedHashMap<String, double> _textWidthCache =
      LinkedHashMap<String, double>();
  static const int _textWidthCacheLimit = 5000;
  static const double _mergeWindowSeconds = 45.0;
  static const double _minTrackGap = 2.0;
  static const double _trackGapRatio = 0.20;

  final List<_NextItem> _items = [];
  final List<double> _itemTimes = [];
  final List<PositionedDanmakuItem> _positionedBuffer = [];
  bool _layoutDirty = true;
  int _layoutVersion = 0;

  NipaPlayNextOldEngine() : _id = 'Old';

  int get layoutVersion => _layoutVersion;

  void _log(String msg) {
    developer.log('[$_id] $msg', name: _logTag);
    DanmakuNextLog.d('Engine', '[$_id] $msg', throttle: Duration.zero);
  }

  /// Native-engine init log: outputs to program log (debugPrint) in ALL modes.
  /// Only used for engine initialization result — the single log kept in Release.
  void _logNative(String msg) {
    final line = '[$_id] $msg';
    developer.log(line, name: _logTag);
    debugPrint('[$_logTag] $line');
  }

  /// Frame-level log: Debug/Profile only, throttled to ~1 per 2s.
  /// Completely eliminated in Release builds (early return + tree-shaking).
  void _logFrame(String msg) {
    if (kReleaseMode) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastFrameLogTimeMs < 2000) return;
    _lastFrameLogTimeMs = nowMs;
    developer.log('[$_id] $msg', name: _logTag);
  }

  /// Attempt to initialize the native C++ layout engine.
  /// Returns the engine if available, null otherwise.
  /// Caches the result so we only try once.
  DanmakuLayoutEngine? _tryInitNativeEngine() {
    if (kIsWeb) return null;
    if (_nativeEngineTried) {
      return _nativeEngineAvailable ? _nativeEngine : null;
    }
    _nativeEngineTried = true;
    try {
      _nativeEngine = DanmakuLayoutEngine();
      _nativeEngineAvailable = true;
      _logNative('[OK] native C++ layout engine INITIALIZED successfully (handle=${_nativeEngine!.itemCount})');
      return _nativeEngine;
    } catch (e) {
      _nativeEngineAvailable = false;
      _logNative('[ERR] native C++ layout engine UNAVAILABLE, using Dart fallback: $e');
      return null;
    }
  }

  /// Disable the native engine and fall back to Dart permanently.
  void _disableNativeEngine() {
    _logNative('[FALLBACK] native C++ engine DISABLED, falling back to Dart path permanently');
    if (_nativeEngine != null) {
      try {
        _nativeEngine!.dispose();
      } catch (_) {}
      _nativeEngine = null;
    }
    _nativeEngineAvailable = false;
  }

  /// Release native (C++ FFI) engine handle and output buffers.
  /// Must be called when the overlay/widget owning this engine is disposed,
  /// otherwise native handles and FFI-allocated buffers remain alive until
  /// Dart GC finalizers run — which can accumulate noticeably for large
  /// comment lists when opening/closing videos or toggling kernels.
  void dispose() {
    if (_nativeEngine != null) {
      try {
        _nativeEngine!.dispose();
      } catch (_) {}
      _nativeEngine = null;
    }
    _nativeEngineTried = false;
    _nativeEngineAvailable = false;
    _textWidthCache.clear();
    _items.clear();
    _itemTimes.clear();
    _positionedBuffer.clear();
  }

  void configure({
    required List<Map<String, dynamic>> danmakuList,
    required Size size,
    required double fontSize,
    required double displayArea,
    required double scrollDurationSeconds,
    required bool allowStacking,
    required bool mergeDanmaku,
    String? fontFamily,
    List<String>? fontFamilyFallback,
    Locale? locale,
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

    final fontFamilyChanged = fontFamily != _fontFamily;
    final fallbackChanged =
        !listEquals(fontFamilyFallback, _fontFamilyFallback);
    final localeChanged = locale != _locale;
    if (fontFamilyChanged || fallbackChanged || localeChanged) {
      _fontFamily = fontFamily;
      _fontFamilyFallback = fontFamilyFallback == null
          ? null
          : List<String>.from(fontFamilyFallback);
      _locale = locale;
      _textWidthCache.clear();
      _layoutDirty = true;
    }

    if (_layoutDirty) {
      final native = _tryInitNativeEngine();
      if (native != null) {
        _logFrame('configure -> _rebuildLayoutNative (C++ path)');
        _rebuildLayoutNative(native);
      } else {
        _log('configure -> _rebuildLayout (Dart fallback path)');
        _rebuildLayout();
      }
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

    // Try native C++ path
    if (_nativeEngineAvailable && _nativeEngine != null) {
      try {
        return _layoutNative(currentTimeSeconds);
      } catch (e) {
        _logFrame('[ERR] native frame EXCEPTION, falling back to Dart: $e');
        _disableNativeEngine();
        _layoutDirty = true;
        _rebuildLayout();
      }
    }

    // Dart fallback
    return _layoutDart(currentTimeSeconds);
  }

  /// Native C++ layout: query frame results from the C++ engine
  /// and map them to [PositionedDanmakuItem].
  List<PositionedDanmakuItem> _layoutNative(double currentTimeSeconds) {
    final frameResult = _nativeEngine!.frame(currentTimeSeconds);
    if (!frameResult.isOk) {
      _logFrame('[ERR] native frame ERROR: ${frameResult.errorMessage}, falling back to Dart');
      _disableNativeEngine();
      _layoutDirty = true;
      _rebuildLayout();
      return _layoutDart(currentTimeSeconds);
    }

    final layoutResults = frameResult.requireValue;
    _logFrame('native frame(t=${currentTimeSeconds.toStringAsFixed(2)}) -> ${layoutResults.length} visible items');
    _positionedBuffer.clear();

    for (final r in layoutResults) {
      if (r.itemIndex < 0 || r.itemIndex >= _items.length) continue;
      if (r.trackIndex < 0) continue;

      final item = _items[r.itemIndex];
      final elapsed = currentTimeSeconds - item.timeSeconds;
      if (elapsed < 0) continue;

      switch (item.type) {
        case DanmakuItemType.scroll:
          if (elapsed > _scrollDurationSeconds) continue;
          final x = _size.width - r.scrollSpeed * elapsed;
          _positionedBuffer.add(_toPositionedItem(
            source: item,
            x: x,
            y: r.yPosition,
            offstageX: _size.width + item.width,
            scrollSpeed: item.scrollSpeed,
            width: item.width,
          ));
          break;
        case DanmakuItemType.top:
        case DanmakuItemType.bottom:
          if (elapsed > _staticDurationSeconds) continue;
          final x = (_size.width - item.width) / 2;
          _positionedBuffer.add(_toPositionedItem(
            source: item,
            x: x,
            y: r.yPosition,
            offstageX: _size.width,
            scrollSpeed: 0.0,
            width: item.width,
          ));
          break;
      }
    }

    if (!kReleaseMode) {
      DanmakuNextLog.d(
        'Engine',
        'layout(native) time=${currentTimeSeconds.toStringAsFixed(2)} out=${_positionedBuffer.length}',
        throttle: const Duration(seconds: 1),
      );
    }
    return _positionedBuffer;
  }

  /// Dart fallback layout: original time-window query + binary search logic.
  List<PositionedDanmakuItem> _layoutDart(double currentTimeSeconds) {
    if (!_dartFallbackNotified) {
      _dartFallbackNotified = true;
      _logNative('[FALLBACK] using Dart layout path (first frame)');
    }
    _logFrame('layout -> Dart fallback path');
    final maxDuration = max(_scrollDurationSeconds, _staticDurationSeconds);
    final windowStart = currentTimeSeconds - maxDuration;
    final left = _lowerBound(windowStart);
    final right = _upperBound(currentTimeSeconds);

    _positionedBuffer.clear();

    for (int i = left; i < right; i++) {
      final item = _items[i];
      if (item.trackIndex < 0) continue;

      final elapsed = currentTimeSeconds - item.timeSeconds;
      if (elapsed < 0) continue;

      switch (item.type) {
        case DanmakuItemType.scroll:
          if (elapsed > _scrollDurationSeconds) continue;
          final x = _size.width - item.scrollSpeed * elapsed;
          _positionedBuffer.add(_toPositionedItem(
            source: item,
            x: x,
            y: item.yPosition,
            offstageX: _size.width + item.width,
            scrollSpeed: item.scrollSpeed,
            width: item.width,
          ));
          break;
        case DanmakuItemType.top:
        case DanmakuItemType.bottom:
          if (elapsed > _staticDurationSeconds) continue;
          final x = (_size.width - item.width) / 2;
          _positionedBuffer.add(_toPositionedItem(
            source: item,
            x: x,
            y: item.yPosition,
            offstageX: _size.width,
            scrollSpeed: 0.0,
            width: item.width,
          ));
          break;
      }
    }

    DanmakuNextLog.d(
      'Engine',
      'layout(dart) time=${currentTimeSeconds.toStringAsFixed(2)} window=[$windowStart..$currentTimeSeconds] '
          'range=[$left,$right) out=${_positionedBuffer.length}',
      throttle: const Duration(seconds: 1),
    );
    return _positionedBuffer;
  }

  PositionedDanmakuItem _toPositionedItem({
    required _NextItem source,
    required double x,
    required double y,
    required double offstageX,
    required double scrollSpeed,
    required double width,
  }) {
    final existing = source.positionedItem;
    if (existing == null) {
      final created = PositionedDanmakuItem(
        content: source.content,
        x: x,
        y: y,
        offstageX: offstageX,
        time: source.timeSeconds,
        scrollSpeed: scrollSpeed,
        width: width,
      );
      source.positionedItem = created;
      return created;
    }

    existing.x = x;
    existing.y = y;
    existing.offstageX = offstageX;
    existing.scrollSpeed = scrollSpeed;
    existing.width = width;
    return existing;
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
      final countText = isMerged ? 'x$mergeCount' : null;

      final content = DanmakuContentItem(
        text,
        type: type,
        color: color,
        isMe: isMe,
        fontSizeMultiplier:
            isMerged ? _calcMergedFontSizeMultiplier(mergeCount) : 1.0,
        countText: countText,
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

  // ════════════════════════════════════════════════════════════════
  //  Native (C++ FFI) layout rebuild
  // ════════════════════════════════════════════════════════════════

  /// Build layout using the native C++ engine.
  /// Dart pre-measures text widths via TextPainter, then passes structured
  /// arrays to C++ which handles the heavy O(n*tracks) track allocation.
  void _rebuildLayoutNative(DanmakuLayoutEngine native) {
    _layoutDirty = false;
    _layoutVersion++;

    if (_items.isEmpty || _size.isEmpty) {
      if (!kReleaseMode) {
        DanmakuNextLog.d(
          'Engine',
          'layout rebuild(native) skipped items=${_items.length} size=${_size.width}x${_size.height}',
          throttle: Duration.zero,
        );
      }
      return;
    }

    // Measure text dimensions (Dart-only, TextPainter required)
    final double baseDanmakuHeight = _measureTextHeight(_fontSize);
    final double baseTrackHeight = _resolveBaseTrackHeight(baseDanmakuHeight);

    // Build FFI inputs: Dart pre-measures text widths, C++ does layout math
    final inputs = <DanmakuLayoutInput>[];
    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      final width = _measureTextWidth(
        item.content.text,
        _fontSize * item.content.fontSizeMultiplier,
      );
      item.width = width;

      inputs.add(DanmakuLayoutInput(
        timeSeconds: item.timeSeconds,
        textWidth: width,
        fontSizeMultiplier: item.content.fontSizeMultiplier,
        type: item.type.index, // 0=scroll, 1=top, 2=bottom
        isMe: item.content.isMe,
        stackHash: (item.content.text.hashCode ^ item.timeSeconds.toInt()) & 0x7fffffff,
      ));
    }

    _logFrame('native configure: ${_items.length} items, size=${_size.width.toStringAsFixed(0)}x${_size.height.toStringAsFixed(0)}, '
        'font=${_fontSize.toStringAsFixed(1)}, area=${_displayArea.toStringAsFixed(2)}, '
        'scroll=${_scrollDurationSeconds.toStringAsFixed(1)}, stacking=$_allowStacking, '
        'baseH=${baseDanmakuHeight.toStringAsFixed(1)}, trackH=${baseTrackHeight.toStringAsFixed(1)}');

    final result = native.configure(
      inputs: inputs,
      width: _size.width,
      height: _size.height,
      fontSize: _fontSize,
      displayArea: _displayArea,
      scrollDuration: _scrollDurationSeconds,
      allowStacking: _allowStacking,
      baseDanmakuHeight: baseDanmakuHeight,
      baseTrackHeight: baseTrackHeight,
    );

    if (!result.isOk) {
      _logFrame('[ERR] native configure FAILED: ${result.errorMessage}, falling back to Dart');
      _disableNativeEngine();
      _layoutDirty = true;
      _rebuildLayout(); // Fallback to Dart
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  Dart fallback layout rebuild (original logic)
  // ════════════════════════════════════════════════════════════════

  void _rebuildLayout() {
    _layoutDirty = false;
    _layoutVersion++;

    if (_items.isEmpty || _size.isEmpty) {
      DanmakuNextLog.d(
        'Engine',
        'layout rebuild skipped items=${_items.length} size=${_size.width}x${_size.height}',
        throttle: Duration.zero,
      );
      return;
    }

    final double baseDanmakuHeight = _measureTextHeight(_fontSize);
    final double baseTrackHeight = _resolveBaseTrackHeight(baseDanmakuHeight);
    final effectiveHeight = max(1.0, _size.height * _displayArea);

    int trackCount;
    if (_displayArea <= 0 || _displayArea.isNaN || _displayArea.isInfinite) {
      trackCount = 1;
    } else {
      trackCount = (effectiveHeight / baseTrackHeight).floor();
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

    final List<List<_NextItem>> scrollTracks =
        List<List<_NextItem>>.generate(trackCount, (_) => <_NextItem>[]);
    final List<_NextItem?> topTrackItems =
        List<_NextItem?>.filled(trackCount, null);
    final List<_NextItem?> bottomTrackItems =
        List<_NextItem?>.filled(trackCount, null);
    final List<double> scrollTrackHeights =
        List<double>.filled(trackCount, baseTrackHeight);
    final List<double> topTrackHeights =
        List<double>.filled(trackCount, baseTrackHeight);
    final List<double> bottomTrackHeights =
        List<double>.filled(trackCount, baseTrackHeight);

    for (final item in _items) {
      final width = _measureTextWidth(
        item.content.text,
        _fontSize * item.content.fontSizeMultiplier,
      );
      item.width = width;
      final itemHeight = baseDanmakuHeight * item.content.fontSizeMultiplier;

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
          scrollTracks[selectedTrack].add(item);
          if (itemHeight > scrollTrackHeights[selectedTrack]) {
            scrollTrackHeights[selectedTrack] = itemHeight;
          }
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
          if (itemHeight > topTrackHeights[selectedTrack]) {
            topTrackHeights[selectedTrack] = itemHeight;
          }
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
          if (itemHeight > bottomTrackHeights[selectedTrack]) {
            bottomTrackHeights[selectedTrack] = itemHeight;
          }
          break;
      }
    }

    final List<double> scrollTrackOffsets =
        List<double>.filled(trackCount, 0.0);
    final List<double> topTrackOffsets = List<double>.filled(trackCount, 0.0);
    final List<double> bottomTrackOffsets =
        List<double>.filled(trackCount, 0.0);

    double scrollOffset = 0.0;
    double topOffset = 0.0;
    double bottomAccumulated = 0.0;
    for (int i = 0; i < trackCount; i++) {
      scrollTrackOffsets[i] = scrollOffset;
      scrollOffset += scrollTrackHeights[i];

      topTrackOffsets[i] = topOffset;
      topOffset += topTrackHeights[i];

      bottomAccumulated += bottomTrackHeights[i];
      bottomTrackOffsets[i] = _size.height - bottomAccumulated;
    }

    for (final item in _items) {
      final track = item.trackIndex;
      if (track < 0 || track >= trackCount) continue;
      switch (item.type) {
        case DanmakuItemType.scroll:
          item.yPosition = scrollTrackOffsets[track];
          break;
        case DanmakuItemType.top:
          item.yPosition = topTrackOffsets[track];
          break;
        case DanmakuItemType.bottom:
          item.yPosition = bottomTrackOffsets[track];
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

  double _calcMergedFontSizeMultiplier(int mergeCount) {
    return (1.0 + mergeCount / 10.0).clamp(1.0, 2.0);
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
          final nextCount = (windowContentCount[leftContent] ?? 1) - 1;
          if (nextCount <= 0) {
            windowContentCount.remove(leftContent);
            firstTime.remove(leftContent);
          } else {
            windowContentCount[leftContent] = nextCount;
          }
        }
        left++;
      }

      final count = windowContentCount[content] ?? 1;
      final key = '$content-$time';

      if (count > 1) {
        final first = firstTime[content] ?? time;
        firstTime[content] ??= first;
        final firstKey = '$content-$first';
        final firstRaw = processed[firstKey] ?? current;

        processed[firstKey] = {
          ...firstRaw,
          'merged': true,
          'mergeCount': count,
          'isFirstInGroup': true,
          'groupContent': content,
        };

        processed[key] = {
          ...current,
          'merged': true,
          'mergeCount': count,
          'isFirstInGroup': time == first,
          'groupContent': content,
        };
      } else {
        firstTime[content] = time;
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
      switch (DanmakuMode.fromCode(raw.toInt()))
      {
      case DanmakuMode.top    : return DanmakuItemType.top;
      case DanmakuMode.bottom : return DanmakuItemType.bottom;
      default                 : return DanmakuItemType.scroll;
      }
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

  double _measureTextWidth(String text, double fontSize) {
    final key = '$fontSize|$text';
    final cached = _textWidthCache[key];
    if (cached != null) {
      _textWidthCache.remove(key);
      _textWidthCache[key] = cached;
      return cached;
    }

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFamilyFallback,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      locale: _locale,
    )..layout(minWidth: 0, maxWidth: double.infinity);

    final width = tp.size.width;
    if (_textWidthCache.length >= _textWidthCacheLimit &&
        _textWidthCache.isNotEmpty) {
      _textWidthCache.remove(_textWidthCache.keys.first);
    }
    _textWidthCache[key] = width;
    return width;
  }

  double _measureTextHeight(double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: '弹幕',
        style: TextStyle(
          fontSize: fontSize,
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFamilyFallback,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      locale: _locale,
    )..layout(minWidth: 0, maxWidth: double.infinity);

    final height = tp.size.height;
    return height.isFinite && height > 0 ? height : fontSize;
  }

  double _resolveBaseTrackHeight(double baseDanmakuHeight) {
    final gap = max(_minTrackGap, _fontSize * _trackGapRatio);
    return baseDanmakuHeight + gap;
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

  PositionedDanmakuItem? positionedItem;
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
