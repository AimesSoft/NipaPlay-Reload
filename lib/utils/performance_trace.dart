import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Opt-in diagnostics only. Names must be fixed operation labels, never URLs,
/// tokens, filenames, search text, or server/user identifiers.
class PerformanceWindow {
  PerformanceWindow({this.maxOperations = 64});
  final int maxOperations;
  final Map<String, _Operation> _operations = {};
  final _Durations _build = _Durations();
  final _Durations _raster = _Durations();
  int frames = 0;
  int overBuildBudget = 0;
  int overRasterBudget = 0;
  int overEitherBudget = 0;
  int discardedOperations = 0;
  double? refreshHz;

  bool get isEmpty =>
      frames == 0 && _operations.isEmpty && discardedOperations == 0;

  void addFrame(
      {required int buildUs,
      required int rasterUs,
      required double refreshRate}) {
    final hz = refreshRate.isFinite && refreshRate > 0 ? refreshRate : 60.0;
    refreshHz = hz;
    final budget = 1000000 / hz;
    final buildOver = buildUs > budget;
    final rasterOver = rasterUs > budget;
    frames++;
    if (buildOver) overBuildBudget++;
    if (rasterOver) overRasterBudget++;
    if (buildOver || rasterOver) overEitherBudget++;
    _build.add(buildUs);
    _raster.add(rasterUs);
  }

  void addOperation(String name,
      {int elapsedUs = 0, int bytes = 0, int items = 0, bool failed = false}) {
    if (!_operations.containsKey(name) && _operations.length >= maxOperations) {
      discardedOperations++;
      return;
    }
    final op = _operations.putIfAbsent(name, _Operation.new);
    op.count++;
    op.elapsedUs += elapsedUs;
    op.maxUs = math.max(op.maxUs, elapsedUs);
    op.bytes += bytes;
    op.maxBytes = math.max(op.maxBytes, bytes);
    op.items += items;
    if (failed) op.failed++;
  }

  Map<String, Object?> toJson() => {
        'frames': frames,
        'refresh_hz': refreshHz,
        'ui_over_budget': overBuildBudget,
        'raster_over_budget': overRasterBudget,
        'either_over_budget': overEitherBudget,
        'ui': _build.toJson(),
        'raster': _raster.toJson(),
        'operations':
            _operations.map((key, value) => MapEntry(key, value.toJson())),
        'discarded_operations': discardedOperations,
      };
}

class _Operation {
  int count = 0, failed = 0, elapsedUs = 0, maxUs = 0;
  int bytes = 0, maxBytes = 0, items = 0;
  Map<String, Object> toJson() => {
        'count': count,
        'failed': failed,
        'elapsed_us': elapsedUs,
        'max_us': maxUs,
        'response_bytes': bytes,
        'max_response_bytes': maxBytes,
        'items': items,
      };
}

/// Fixed-size 0.5ms histogram; overflow quantiles conservatively return max.
class _Durations {
  final List<int> buckets = List.filled(402, 0);
  int count = 0, sum = 0, max = 0;
  void add(int us) {
    final value = math.max(0, us);
    buckets[((value + 499) ~/ 500).clamp(0, 401)]++;
    count++;
    sum += value;
    max = math.max(max, value);
  }

  int percentile(double fraction) {
    if (count == 0) return 0;
    final target = (count * fraction).ceil();
    var accumulated = 0;
    for (var i = 0; i < buckets.length; i++) {
      accumulated += buckets[i];
      if (accumulated >= target) return i == 401 ? max : i * 500;
    }
    return max;
  }

  Map<String, Object> toJson() => {
        'mean_us': count == 0 ? 0 : sum ~/ count,
        'p95_upper_us': percentile(.95),
        'p99_upper_us': percentile(.99),
        'max_us': max,
      };
}

class PerformanceTrace {
  static const enabled = bool.fromEnvironment('NIPAPLAY_PERFORMANCE_TRACE') ||
      bool.fromEnvironment('NIPAPLAY_FRAME_TIMING_TRACE');
  static const scene = String.fromEnvironment('NIPAPLAY_PERFORMANCE_SCENE',
      defaultValue: 'unspecified');
  static final Stopwatch _clock = Stopwatch()..start();
  static int _windowStartUs = 0;
  static PerformanceWindow _window = PerformanceWindow();

  static void frame(
      {required int buildUs,
      required int rasterUs,
      required double refreshRate}) {
    if (!enabled) return;
    final hz = refreshRate.isFinite && refreshRate > 0 ? refreshRate : 60.0;
    if (_window.refreshHz != null && _window.refreshHz != hz) flush();
    _window.addFrame(buildUs: buildUs, rasterUs: rasterUs, refreshRate: hz);
    _flushIfDue();
  }

  static void count(String operation) {
    if (!enabled) return;
    _window.addOperation(operation);
    _flushIfDue();
  }

  static bool isItemListing(String endpoint) {
    final path = endpoint.split('?').first.toLowerCase();
    return path.endsWith('/items') || path.endsWith('/items/latest');
  }

  static T measureSync<T>(String operation, T Function() task) {
    if (!enabled) return task();
    final watch = Stopwatch()..start();
    try {
      final value = task();
      _window.addOperation(operation, elapsedUs: watch.elapsedMicroseconds);
      return value;
    } catch (_) {
      _window.addOperation(operation,
          elapsedUs: watch.elapsedMicroseconds, failed: true);
      rethrow;
    } finally {
      _flushIfDue();
    }
  }

  static Future<T> measure<T>(String operation, Future<T> Function() task,
      {int Function(T)? responseBytes,
      int Function(T)? itemCount,
      bool Function(T)? isFailure}) async {
    if (!enabled) return task();
    final watch = Stopwatch()..start();
    try {
      final result = await task();
      _window.addOperation(operation,
          elapsedUs: watch.elapsedMicroseconds,
          bytes: responseBytes?.call(result) ?? 0,
          items: itemCount?.call(result) ?? 0,
          failed: isFailure?.call(result) ?? false);
      return result;
    } catch (_) {
      _window.addOperation(operation,
          elapsedUs: watch.elapsedMicroseconds, failed: true);
      rethrow;
    } finally {
      _flushIfDue();
    }
  }

  static void _flushIfDue() {
    if (_clock.elapsedMicroseconds - _windowStartUs >= 5000000) flush();
  }

  static void flush() {
    if (!enabled || _window.isEmpty) return;
    final now = _clock.elapsedMicroseconds;
    final record = {
      'scene': scene,
      'start_us': _windowStartUs,
      'end_us': now,
      ..._window.toJson(),
    };
    _window = PerformanceWindow();
    _windowStartUs = now;
    debugPrint('[nipa-perf] ${jsonEncode(record)}');
  }
}
