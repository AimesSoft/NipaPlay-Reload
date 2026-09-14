import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:ui' show FramePhase;

import 'package:flutter/scheduler.dart';

/// Keeps the newest samples if the platform thread cannot accept a batch.
class FrameTraceBuffer {
  FrameTraceBuffer({this.capacity = 8192}) : assert(capacity > 0);
  final int capacity;
  final Queue<Map<String, Object?>> _events = Queue();
  int _dropped = 0;

  void add(Map<String, Object?> event) {
    if (_events.length >= capacity) {
      _events.removeFirst();
      _dropped++;
    }
    _events.addLast(event);
  }

  Map<String, Object?> drain() {
    final data = <String, Object?>{
      'clock': 'dart_timeline_us',
      'dropped': _dropped,
      'events': _events.toList(growable: false),
    };
    _events.clear();
    _dropped = 0;
    return data;
  }
}

class Next2FrameTrace {
  Next2FrameTrace(this._send);
  final Future<void> Function(Map<String, Object?>) _send;
  final FrameTraceBuffer _buffer = FrameTraceBuffer();
  Timer? _timer;
  TimingsCallback? _timings;
  bool _sending = false;
  bool _flushAfterSend = false;
  bool enabled = false;
  bool _disposed = false;
  int engine = 0;
  int _startedUs = 0;
  static int _nextFrame = 0;
  static final Set<Next2FrameTrace> _active = {};

  /// Correlate low-frequency playback work with the animation timeline.
  static void recordPlaybackEvent(String event, Map<String, Object?> fields) {
    for (final trace in _active) {
      trace.add(event, fields);
    }
  }

  int nextFrame() => enabled ? ++_nextFrame : 0;

  void start(int handle) {
    if (_disposed) return;
    engine = handle;
    if (enabled) return;
    enabled = true;
    _active.add(this);
    _startedUs = developer.Timeline.now;
    _timings = (timings) {
      for (final timing in timings) {
        add('flutter_frame', {
          'vsync_us': timing.timestampInMicroseconds(FramePhase.vsyncStart),
          'build_start_us':
              timing.timestampInMicroseconds(FramePhase.buildStart),
          'build_end_us':
              timing.timestampInMicroseconds(FramePhase.buildFinish),
          'raster_start_us':
              timing.timestampInMicroseconds(FramePhase.rasterStart),
          'raster_end_us':
              timing.timestampInMicroseconds(FramePhase.rasterFinish),
        });
      }
    };
    SchedulerBinding.instance.addTimingsCallback(_timings!);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (developer.Timeline.now - _startedUs >= 600000000) {
        stop();
      } else {
        unawaited(_flush());
      }
    });
    add('trace_start', {});
  }

  void add(String event, Map<String, Object?> fields, {int frame = 0}) {
    if (!enabled) return;
    _buffer.add({
      't_us': developer.Timeline.now,
      'event': event,
      'engine': engine,
      'frame': frame,
      ...fields,
    });
  }

  Future<void> _flush() async {
    if (_sending) return;
    _sending = true;
    try {
      await _send(_buffer.drain());
    } catch (_) {
      // Explicitly flag a failed batch on the next successful flush.
      _buffer
          .add({'event': 'dart_batch_failed', 't_us': developer.Timeline.now});
    } finally {
      _sending = false;
      if (_flushAfterSend) {
        _flushAfterSend = false;
        unawaited(_flush());
      }
    }
  }

  void stop() {
    if (!enabled) return;
    add('trace_stop', {});
    enabled = false;
    _active.remove(this);
    _timer?.cancel();
    final callback = _timings;
    if (callback != null) {
      SchedulerBinding.instance.removeTimingsCallback(callback);
    }
    _timings = null;
    if (_sending) {
      _flushAfterSend = true;
    } else {
      unawaited(_flush());
    }
  }

  void dispose() {
    _disposed = true;
    stop();
  }
}
