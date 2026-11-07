import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/scheduler.dart';
import '../../system/foreground.dart';

Map<String, Object?> frameDurations(List<int> microseconds) {
  if (microseconds.isEmpty) return {'p50': null, 'p95': null, 'max': null};
  microseconds.sort();
  double at(double fraction) =>
      microseconds[(microseconds.length * fraction)
              .ceil()
              .clamp(1, microseconds.length) -
          1] /
      1000;
  return {'p50': at(.50), 'p95': at(.95), 'max': microseconds.last / 1000};
}

/// One deadline, no extra frames requested. The timing callback can arrive
/// batched; use frame timestamps to exclude frames preceding this window.
Future<Map<String, Object?>> measureNextIdle(Duration duration) async {
  final start = Timeline.now;
  final end = start + duration.inMicroseconds;
  final before = NextRefreshMetrics.snapshot();
  final builds = <int>[], rasters = <int>[];
  void collect(List<FrameTiming> timings) {
    for (final frame in timings) {
      final at = frame.timestampInMicroseconds(FramePhase.vsyncStart);
      if (at < start || at > end) continue;
      builds.add(frame.buildDuration.inMicroseconds);
      rasters.add(frame.rasterDuration.inMicroseconds);
    }
  }

  SchedulerBinding.instance.addTimingsCallback(collect);
  late Map<String, int> after;
  try {
    await Future<void>.delayed(duration);
    after = NextRefreshMetrics.snapshot();
    // Flutter delivers profile timings in batches (up to roughly one second).
    // Keep the callback, but retain only frames inside the requested interval.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
  } finally {
    SchedulerBinding.instance.removeTimingsCallback(collect);
  }
  final refreshes = <String, int>{
    for (final entry in after.entries)
      if (entry.value != (before[entry.key] ?? 0))
        entry.key: entry.value - (before[entry.key] ?? 0),
  };
  final summaries = await _summarize(builds, rasters);
  final periodic = NextRefreshMetrics.periodicCount(refreshes);
  return {
    'seconds': duration.inMilliseconds / 1000,
    'frames': builds.length,
    'unit': 'ms',
    'build': summaries.$1,
    'raster': summaries.$2,
    'refreshes': refreshes,
    'periodicRefreshes': periodic,
    'dataRefreshes': refreshes.values.fold<int>(0, (a, b) => a + b) -
        periodic,
  };
}

// Keep the isolate closure's context limited to the two sendable lists.
Future<(Map<String, Object?>, Map<String, Object?>)> _summarize(
        List<int> builds, List<int> rasters) =>
    Isolate.run(() => (frameDurations(builds), frameDurations(rasters)));
