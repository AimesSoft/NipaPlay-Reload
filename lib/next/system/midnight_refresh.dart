import 'dart:async';
import 'foreground.dart';

/// 日期在午夜确实变化；使用下一个本地午夜的单次截止点，不轮询。
final class MidnightRefresh {
  MidnightRefresh(this.changed, {DateTime Function()? now})
      : now = now ?? DateTime.now;
  final void Function() changed;
  final DateTime Function() now;
  StreamSubscription<bool>? _foreground;
  Timer? _midnight;
  bool _started = false;
  void start() {
    if (_started) return;
    _started = true;
    _foreground = NextForeground.changes.listen((_) => _schedule());
    _schedule();
  }

  void _schedule() {
    _midnight?.cancel();
    _midnight = null;
    if (!_started || !NextForeground.active) return;
    final today = now();
    final next = DateTime(today.year, today.month, today.day + 1);
    _midnight = Timer(next.difference(today), () {
      if (!_started || !NextForeground.active) return;
      NextRefreshMetrics.record('calendar.midnight');
      changed();
      _schedule();
    });
  }

  Future<void> close() async {
    _started = false;
    _midnight?.cancel();
    _midnight = null;
    await _foreground?.cancel();
    _foreground = null;
  }
}
