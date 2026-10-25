import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

final class _Timespec extends Struct {
  @IntPtr()
  external int seconds;
  @IntPtr()
  external int nanos;
}

/// Measures only synchronous callbacks in the measured zone, using the current
/// mutator thread's CPU clock. OS descheduling and other processes consume no
/// budget. A callback never migrates threads before returning to the event loop;
/// each callback takes a fresh pair of readings. Nested zone calls count once.
final class CpuBudgetProbe {
  static const _trace = bool.fromEnvironment('NEXT_PERF_TRACE');
  static const _traceMicros =
      int.fromEnvironment('NEXT_PERF_TRACE_US', defaultValue: 4000);
  final _wall = Stopwatch()..start();
  final _clock = _ThreadClock();
  final _phases = <(String, double, double)>[];
  final _occupancy = <(String, double, double)>[];
  int _depth = 0, _start = 0, _longest = 0, _held = 0, _total = 0, _markUs = 0;
  bool verbose = false;
  bool _stopped = false;

  R _measure<R>(R Function() callback) {
    if (_stopped || _depth > 0) return callback();
    _depth++;
    final stack = _trace ? StackTrace.current : null;
    _start = _clock.now;
    try {
      return callback();
    } finally {
      if (!_stopped) _record(stack);
      _depth--;
      if (_stopped && _depth == 0) _clock.close();
    }
  }

  void _record([StackTrace? stack]) {
    final end = _clock.now;
    final elapsed = end - _start;
    _start = end;
    if (_trace && stack != null && elapsed >= _traceMicros) {
      // ignore: avoid_print
      print(
          '[CPU probe stack] ${(elapsed / 1000).toStringAsFixed(3)} ms\n$stack');
    }
    if (elapsed > _longest) _longest = elapsed;
    if (elapsed > 2000) _held += elapsed;
    _total += elapsed;
  }

  Future<void> run(Future<void> Function() operation) =>
      runZoned(() => _measure(operation),
          zoneSpecification: ZoneSpecification(
            run: <R>(self, parent, zone, R Function() callback) =>
                _measure(() => parent.run(zone, callback)),
            runUnary:
                <R, T>(self, parent, zone, R Function(T) callback, T value) =>
                    _measure(() => parent.runUnary(zone, callback, value)),
            runBinary: <R, T1, T2>(self, parent, zone,
                    R Function(T1, T2) callback, T1 first, T2 second) =>
                _measure(() => parent.runBinary(zone, callback, first, second)),
          ));

  void mark(String name) {
    if (_depth > 0) _record();
    final wall = _wall.elapsedMicroseconds;
    _phases.add((name, _longest / 1000, _held / 1000));
    _occupancy.add((
      name,
      _total / 1000,
      wall == _markUs ? 0 : 100 * _total / (wall - _markUs)
    ));
    if (verbose) {
      // ignore: avoid_print
      print(
          '[CPU probe] $name: longest ${(_longest / 1000).toStringAsFixed(3)} ms, '
          'held ${(_held / 1000).toStringAsFixed(3)} ms, '
          'CPU ${(_total / 1000).toStringAsFixed(3)} ms '
          '(${_occupancy.last.$3.toStringAsFixed(2)}%)');
    }
    _longest = _held = _total = 0;
    _markUs = wall;
    if (_depth > 0) _start = _clock.now;
  }

  /// Deliberate regression, confined to the test build. The injected duration
  /// uses CPU too, so a loaded machine cannot hide it through descheduling.
  void injectBlock(Duration duration) {
    final end = _clock.now + duration.inMicroseconds;
    while (_clock.now < end) {}
  }

  List<(String, double, double)> get phases => _phases;
  void stop() {
    _stopped = true;
    if (_depth == 0) _clock.close();
    _wall.stop();
  }

  @override
  String toString() => [
        for (final (name, cpu, fraction) in _occupancy)
          '$name: CPU ${cpu.toStringAsFixed(3)} ms, occupancy ${fraction.toStringAsFixed(2)}%'
      ].join('\n');
}

final class _ThreadClock {
  _ThreadClock() {
    if (Platform.isWindows) _cyclesPerMicrosecond; // calibrate off the clock
  }

  final _time = calloc<_Timespec>();
  final _windowsTimes = calloc<Uint64>(4);
  late final _gettime = DynamicLibrary.process().lookupFunction<
      Int32 Function(Int32, Pointer<_Timespec>),
      int Function(int, Pointer<_Timespec>)>('clock_gettime');
  late final _kernel = DynamicLibrary.open('kernel32.dll');
  late final _thread = _kernel
      .lookupFunction<IntPtr Function(), int Function()>('GetCurrentThread');
  // GetThreadTimes advances in scheduler quanta (15.625 ms): a 20 microsecond
  // callback can read as a whole quantum. The thread's cycle count has no
  // such step; cycles are turned into time with the rate this thread shows
  // against the wall clock (the best of a few spins, as descheduling only
  // ever makes the rate look slower).
  late final _cycles = _kernel.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint64>),
      int Function(int, Pointer<Uint64>)>('QueryThreadCycleTime');
  late final double _cyclesPerMicrosecond = _calibrate();

  int _threadCycles() {
    if (_cycles(_thread(), _windowsTimes) == 0) {
      throw StateError('QueryThreadCycleTime failed');
    }
    return _windowsTimes[0];
  }

  double _calibrate() {
    var best = 0.0;
    for (var round = 0; round < 5; round++) {
      final wall = Stopwatch()..start();
      final first = _threadCycles();
      while (wall.elapsedMicroseconds < 4000) {}
      final rate = (_threadCycles() - first) / wall.elapsedMicroseconds;
      if (rate > best) best = rate;
    }
    return best;
  }

  int get now {
    if (Platform.isWindows) {
      final rate = _cyclesPerMicrosecond; // calibrates on first use
      return _threadCycles() ~/ rate;
    }
    if (_gettime(Platform.isMacOS ? 16 : 3, _time) != 0) {
      throw StateError('Thread CPU clock unavailable');
    }
    return _time.ref.seconds * 1000000 + _time.ref.nanos ~/ 1000;
  }

  void close() {
    calloc.free(_time);
    calloc.free(_windowsTimes);
  }
}
