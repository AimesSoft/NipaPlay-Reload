import 'dart:async';

/// Shared with headless services; only the GUI host changes this value.
abstract final class NextForeground {
  static bool _active = true;
  static bool get active => _active;
  static final _changes = StreamController<bool>.broadcast(sync: true);
  static Stream<bool> get changes => _changes.stream;
  static void setActive(bool value) {
    if (_active == value) return;
    _active = value;
    _changes.add(value);
  }
}

/// Counts actual refresh deliveries, without creating a sampling timer.
abstract final class NextRefreshMetrics {
  static final _counts = <String, int>{};
  static void record(String source) =>
      _counts.update(source, (n) => n + 1, ifAbsent: () => 1);
  static Map<String, int> snapshot() => Map.of(_counts);
  static int periodicCount(Map<String, int> counts) => counts.entries
      .where((entry) => entry.key.endsWith('.periodic'))
      .fold(0, (sum, entry) => sum + entry.value);
}
