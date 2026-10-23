import 'dart:async';

/// How long this isolate's event loop was held, told by a timer that asks
/// to run every [tick]: a run that comes late by more than [slack] means the
/// isolate was busy for that long without returning to its event loop.
///
/// The test isolate stands for the main isolate: what a test runs on it
/// directly (not inside `Isolate.run`) is what the app would run on its UI
/// isolate.
final class MainThreadProbe {
  MainThreadProbe._(this.tick, this.slack);

  final Duration tick, slack;
  final _clock = Stopwatch();
  Timer? _timer;
  int _last = 0;
  final _stretches = <int>[];
  final _marks = <(String, int, int)>[];
  int _markIndex = 0;

  /// Starts measuring now.
  static MainThreadProbe start(
      {Duration tick = const Duration(milliseconds: 1),
      Duration slack = const Duration(milliseconds: 2)}) {
    final probe = MainThreadProbe._(tick, slack);
    probe._clock.start();
    probe._last = probe._clock.elapsedMicroseconds;
    probe._timer = Timer.periodic(tick, (_) => probe._observe());
    return probe;
  }

  void _observe() {
    final now = _clock.elapsedMicroseconds;
    final late = now - _last - tick.inMicroseconds;
    if (late > slack.inMicroseconds) _stretches.add(late);
    _last = now;
  }

  /// Names what ran since the previous mark, for the report.
  void mark(String name) {
    _observe();
    _marks.add((name, _markIndex, _stretches.length));
    _markIndex = _stretches.length;
  }

  /// Longest single stretch, in milliseconds.
  double get longestMs =>
      _stretches.isEmpty ? 0 : _stretches.reduce((a, b) => a > b ? a : b) / 1000;

  /// Sum of the stretches longer than [slack], in milliseconds.
  double get heldMs => _stretches.fold<int>(0, (a, b) => a + b) / 1000;

  Duration get elapsed => _clock.elapsed;

  /// Per mark: (name, longest ms, held ms).
  List<(String, double, double)> get phases => [
        for (final (name, from, to) in _marks)
          (
            name,
            from == to
                ? 0
                : _stretches
                        .sublist(from, to)
                        .reduce((a, b) => a > b ? a : b) /
                    1000,
            _stretches.sublist(from, to).fold<int>(0, (a, b) => a + b) / 1000
          )
      ];

  /// Stops measuring.
  void stop() {
    _observe();
    _timer?.cancel();
    _clock.stop();
  }

  @override
  String toString() => [
        'longest ${longestMs.toStringAsFixed(1)} ms, held ${heldMs.toStringAsFixed(1)} ms '
            'over ${(_clock.elapsedMicroseconds / 1000).toStringAsFixed(0)} ms',
        for (final (name, longest, held) in phases)
          '  $name: longest ${longest.toStringAsFixed(1)} ms, held ${held.toStringAsFixed(1)} ms',
      ].join('\n');
}
