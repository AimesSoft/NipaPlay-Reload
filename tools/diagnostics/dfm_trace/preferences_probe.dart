// Read-only codec benchmark. Does not modify preferences or print their values.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ffi';
import '../../../packages/shared_preferences_windows/lib/src/preferences_codec.dart';

Map<String, double> distribution(List<double> values) {
  values.sort();
  return {
    'median_ms': values[values.length ~/ 2],
    'p99_ms': values[((values.length - 1) * .99).round()],
    'max_ms': values.last
  };
}

Future<Map<String, Object>> measure(
    Map<String, Object> prefs, bool worker) async {
  final gaps = <double>[], operations = <double>[];
  final clock = Stopwatch()..start();
  var previous = clock.elapsedMicroseconds;
  final timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
    final now = clock.elapsedMicroseconds;
    gaps.add((now - previous) / 1000);
    previous = now;
  });
  var bytes = 0;
  try {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final start = clock.elapsedMicroseconds;
      // Include the same snapshot capture performed by the storage plugin.
      final snapshot = prefs.map((key, value) => MapEntry(
          key, value is List<String> ? List<String>.of(value) : value));
      bytes = (worker
              ? await encodePreferences(snapshot)
              : utf8.encode(jsonEncode(snapshot)))
          .length;
      operations.add((clock.elapsedMicroseconds - start) / 1000);
    }
    await Future<void>.delayed(const Duration(milliseconds: 15));
  } finally {
    timer.cancel();
  }
  return {
    'bytes': bytes,
    'operations': distribution(operations),
    'ui_timer_gaps': distribution(gaps),
    'gaps_over_11ms': gaps.where((x) => x > 11).length
  };
}

Future<void> main(List<String> args) async {
  // Standalone Dart otherwise uses ~15.6 ms timers on Windows. Keep this
  // temporary request confined to the benchmark and restore it on completion.
  int Function(int)? endPeriod;
  if (Platform.isWindows) {
    final winmm = DynamicLibrary.open('winmm.dll');
    final begin =
        winmm.lookupFunction<Uint32 Function(Uint32), int Function(int)>(
            'timeBeginPeriod');
    if (begin(1) == 0) {
      endPeriod =
          winmm.lookupFunction<Uint32 Function(Uint32), int Function(int)>(
              'timeEndPeriod');
    }
  }
  try {
    final Map<String, Object> prefs = args.isEmpty
        ? {'payload': List.filled(120000, '弹幕😀"\\\n').join()}
        : Map<String, Object>.from(
            jsonDecode(await File(args.single).readAsString()));
    for (var i = 0; i < 5; i++) {
      utf8.encode(jsonEncode(prefs));
      await encodePreferences(prefs);
    }
    print(jsonEncode({
      'main_isolate': await measure(prefs, false),
      'worker_isolate': await measure(prefs, true)
    }));
  } finally {
    endPeriod?.call(1);
  }
}
