import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

/// What the playback layer costs the main isolate, measured where it is
/// spent: each entry it runs there ([span]), how often things happen
/// ([count]), how long the person waits ([latency]), and, while a window
/// is recorded with frames on, the frames, the event loop and the layer's
/// rebuilds. Read and reset through `ext.nipaplay.player.perf`; the
/// summary also goes into `runtime.diagnostics`.
abstract final class PlayerPerf {
  static final _clock = Stopwatch()..start();
  static final _spans = <String, _Series>{};
  static final _latencies = <String, _Series>{};
  static final _counts = <String, int>{};
  static final _slowest = <({String name, int us, int atMs})>[];
  static int _windowStartUs = 0;
  static _Series? _build, _raster;
  static _LoopProbe? _loop;
  static bool _frames = false;
  static bool _installed = false;

  /// Frame timings and rebuilds need Flutter; `budget.dart` supplies them
  /// through this hook so this file stays pure Dart.
  static PlayerPerfFrameSource? frameSource;

  static const _profile = bool.fromEnvironment('dart.vm.profile');

  /// Runs [run] on the main isolate and records how long it took.
  static T span<T>(String name, T Function() run) {
    final start = _clock.elapsedMicroseconds;
    try {
      return _profile
          ? developer.Timeline.timeSync('player.$name', run)
          : run();
    } finally {
      _record(name, _clock.elapsedMicroseconds - start);
    }
  }

  static final _marks = <({String name, int atMs})>[];

  /// A named instant in the window, to line up with what the event loop
  /// stalls log (at most 64, the first ones).
  static void mark(String name) {
    if (_marks.length < 64) _marks.add((name: name, atMs: _sinceWindowMs));
  }

  static void count(String name, [int by = 1]) =>
      _counts[name] = (_counts[name] ?? 0) + by;

  static void latency(String name, Duration duration) =>
      (_latencies[name] ??= _Series()).add(duration.inMicroseconds);

  static void _record(String name, int us) {
    (_spans[name] ??= _Series()).add(us);
    if (_slowest.length == 20 && us <= _slowest.last.us) return;
    _slowest.add((name: name, us: us, atMs: _sinceWindowMs));
    _slowest.sort((a, b) => b.us.compareTo(a.us));
    if (_slowest.length > 20) _slowest.removeLast();
  }

  static int get _sinceWindowMs =>
      (_clock.elapsedMicroseconds - _windowStartUs) ~/ 1000;

  /// Starts a new window. With [frames], frame timings, the event loop at
  /// 4 ms and the rebuilds of the player layer are recorded too, until the
  /// next reset.
  static void reset({bool frames = false}) {
    _spans.clear();
    _latencies.clear();
    _counts.clear();
    _slowest.clear();
    _marks.clear();
    _windowStartUs = _clock.elapsedMicroseconds;
    _stopFrames();
    if (frames) _startFrames();
  }

  static void _startFrames() {
    _frames = true;
    _build = _Series();
    _raster = _Series();
    _loop = _LoopProbe()..start();
    frameSource?.start();
  }

  static void _stopFrames() {
    if (!_frames) return;
    _frames = false;
    _loop?.stop();
    frameSource?.stop();
  }

  /// One frame's build and raster durations, from the frame source.
  static void recordFrame(Duration build, Duration raster) {
    _build?.add(build.inMicroseconds);
    _raster?.add(raster.inMicroseconds);
  }

  /// The player layer is the subtree under a widget whose type is named
  /// [layerType]; every element rebuilt under it counts (debug builds).
  static const layerType = 'NextPlayerLayer';

  static Map<String, Object?> read() {
    final windowMs = math.max(1, _sinceWindowMs);
    final spanTotalUs =
        _spans.values.fold<int>(0, (sum, series) => sum + series.totalUs);
    return {
      'windowMs': windowMs,
      'spans': {
        for (final e in _spans.entries) e.key: e.value.summary(windowMs)
      },
      'mainIsolateShare': spanTotalUs / (windowMs * 1000),
      'counts': {
        for (final e in _counts.entries)
          e.key: {'n': e.value, 'perMinute': e.value * 60000 / windowMs}
      },
      'latencies': {
        for (final e in _latencies.entries) e.key: e.value.summary(windowMs)
      },
      'slowest': [
        for (final s in _slowest) {'name': s.name, 'us': s.us, 'atMs': s.atMs}
      ],
      'marks': [
        for (final m in _marks) {'name': m.name, 'atMs': m.atMs}
      ],
      if (_frames) ...{
        'frames': {
          'build': _build!.summary(windowMs),
          'raster': _raster!.summary(windowMs),
        },
        'loop': _loop!.summary(),
      },
    };
  }

  /// `ext.nipaplay.player.perf` `op=read|reset` (`frames=true` to record
  /// frames, the loop and rebuilds in the new window).
  static void install() {
    if (_installed) return;
    _installed = true;
    developer.registerExtension('ext.nipaplay.player.perf', (_, params) async {
      if (params['op'] == 'reset') reset(frames: params['frames'] == 'true');
      return developer.ServiceExtensionResponse.result(jsonEncode(read()));
    });
  }
}

/// Starts and stops the Flutter-side frame recording of [PlayerPerf].
abstract interface class PlayerPerfFrameSource {
  void start();
  void stop();
}

/// Count, total and maximum of every value; percentiles over the last
/// 4096.
final class _Series {
  static const _keep = 4096;
  final _recent = <int>[];
  int _next = 0;
  int count = 0, totalUs = 0, maxUs = 0;

  void add(int us) {
    count++;
    totalUs += us;
    if (us > maxUs) maxUs = us;
    if (_recent.length < _keep) {
      _recent.add(us);
    } else {
      _recent[_next] = us;
      _next = (_next + 1) % _keep;
    }
  }

  Map<String, Object?> summary(int windowMs) {
    final sorted = [..._recent]..sort();
    int at(double q) => sorted.isEmpty
        ? 0
        : sorted[math.min(sorted.length - 1, (q * sorted.length).floor())];
    return {
      'n': count,
      'perMinute': count * 60000 / windowMs,
      'totalMs': totalUs / 1000,
      'p50Us': at(0.5),
      'p95Us': at(0.95),
      'p99Us': at(0.99),
      'maxUs': maxUs,
    };
  }
}

/// How late a 4 ms timer runs: the event loop could not take it meanwhile.
final class _LoopProbe {
  static const _period = Duration(milliseconds: 4);
  Timer? _timer;
  final _watch = Stopwatch();
  final stallLog = <Map<String, Object?>>[];
  int _ticks = 0, over16 = 0, over50 = 0, over1000 = 0, maxLateUs = 0;
  final _late = _Series();

  void start() {
    _watch.start();
    var last = _watch.elapsedMicroseconds;
    _timer = Timer.periodic(_period, (_) {
      final now = _watch.elapsedMicroseconds;
      final late = now - last - _period.inMicroseconds;
      last = now;
      _ticks++;
      if (late <= 0) return;
      _late.add(late);
      if (late > maxLateUs) maxLateUs = late;
      if (late > 16000) {
        over16++;
        if (stallLog.length < 64) {
          stallLog
              .add({'atMs': PlayerPerf._sinceWindowMs, 'lateMs': late / 1000});
        }
      }
      if (late > 50000) over50++;
      if (late > 1000000) over1000++;
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Map<String, Object?> summary() => {
        'ticks': _ticks,
        'stallsOver16ms': over16,
        'stallsOver50ms': over50,
        'stallsOver1s': over1000,
        'stallLog': stallLog,
        'maxLateUs': maxLateUs,
        'late': _late.summary(math.max(1, _watch.elapsedMilliseconds)),
      };
}
