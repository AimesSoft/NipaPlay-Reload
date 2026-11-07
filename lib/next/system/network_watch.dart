import 'dart:async';
import 'foreground.dart';

/// 有系统通知时不设轮询；兼容检查也只在前台存在。
final class ForegroundNetworkWatch {
  ForegroundNetworkWatch(this.check,
      {required this.events,
      this.fallbackInterval = const Duration(seconds: 5)});
  final void Function() check;
  final Stream<void>? events;
  final Duration fallbackInterval;
  StreamSubscription<bool>? _foreground;
  StreamSubscription<void>? _network;
  Timer? _fallback;
  bool _started = false;
  void start() {
    if (_started) return;
    _started = true;
    _foreground = NextForeground.changes.listen((_) => _schedule());
    _schedule();
  }

  void _schedule() {
    _network?.cancel();
    _network = null;
    _fallback?.cancel();
    _fallback = null;
    if (!_started || !NextForeground.active) return;
    _check();
    if (events case final changes?) {
      _network = changes.listen((_) {
        if (_started && NextForeground.active) _check();
      }, onError: (Object _, StackTrace __) {
        // Apple 的桥接缺失也不静默退回永久轮询；回前台仍补查。
      });
    } else {
      _fallback = Timer.periodic(fallbackInterval, (_) {
        NextRefreshMetrics.record('mesh.network.periodic');
        _check();
      });
    }
  }

  void _check() {
    NextRefreshMetrics.record('mesh.network.check');
    check();
  }

  Future<void> close() async {
    _started = false;
    _fallback?.cancel();
    // 先同步摘掉两个监听，再等待它们清理，避免原生取消等待期间仍保留监听。
    final foregroundStopped = _foreground?.cancel();
    final networkStopped = _network?.cancel();
    _foreground = null;
    _network = null;
    await foregroundStopped;
    await networkStopped;
  }
}
